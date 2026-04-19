defmodule Simulator.Economy.DemandAnalyzer do
  @moduledoc """
  Detects chronic supply shortages and triggers facility construction.

  Runs every `@analysis_interval` ticks. Scans all markets for commodities
  stuck at zero supply, determines what facility type would fix it, and
  posts delivery contracts to bring construction materials to the site.
  When all materials arrive, spawns the new facility at runtime.

  This makes the economy self-correcting: shortage → demand signal →
  construction → new facility → shortage resolved.

  ## Construction Flow

  1. Detect shortage (commodity at 0 supply for `@shortage_threshold` ticks)
  2. Determine facility type needed (refinery for fuel, farm for food, etc.)
  3. Post zero-deposit delivery contracts for required materials
  4. Track delivery progress in ETS
  5. When all materials delivered to destination, spawn facility + market
  6. Broadcast `:facility_constructed` event
  """

  use GenServer

  require Logger

  alias Simulator.{Queries, Repo}
  alias Simulator.Agents.{FacilityAgent, MarketAgent}
  alias Simulator.Economy.ContractBoard
  alias Simulator.Schemas

  alias Simulator.Simulation.Config

  # Analysis runs every ~30 sec, shortage must persist ~1 min before construction triggers
  @analysis_interval 30 * Config.tick_multiplier()
  @shortage_threshold 60 * Config.tick_multiplier()
  @ets_projects :construction_projects
  @ets_shortage_tracking :shortage_tracking

  @construction_costs %{
    mining_rig: %{metals: 300, tools: 100},
    refinery: %{metals: 500, components: 200, tools: 100},
    factory: %{metals: 800, components: 300, tools: 200},
    farm: %{metals: 200, components: 100, water: 200},
    station: %{metals: 1000, components: 500, tools: 200}
  }

  @shortage_to_facility %{
    fuel: :refinery,
    food: :farm,
    tools: :factory,
    components: :factory,
    electronics: :factory,
    metals: :refinery,
    polymers: :refinery,
    water: :refinery,
    ore: :mining_rig,
    ice: :mining_rig,
    gas: :mining_rig
  }

  # --- Public API ---

  @doc """
  Starts the DemandAnalyzer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns all active construction projects.
  """
  @spec active_projects() :: [map()]
  def active_projects do
    if :ets.whereis(@ets_projects) != :undefined do
      :ets.tab2list(@ets_projects) |> Enum.map(&elem(&1, 1))
    else
      []
    end
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(_opts) do
    if :ets.whereis(@ets_projects) == :undefined do
      :ets.new(@ets_projects, [:named_table, :set, :public, read_concurrency: true])
    end

    if :ets.whereis(@ets_shortage_tracking) == :undefined do
      :ets.new(@ets_shortage_tracking, [:named_table, :set, :public, write_concurrency: true])
    end

    Simulator.Events.subscribe("tick")

    {:ok, %{last_analysis_tick: 0}}
  end

  @impl true
  def handle_info({:tick, %{tick: tick}}, state) do
    if tick - state.last_analysis_tick >= @analysis_interval do
      analyze_and_build(tick)
      check_construction_progress(tick)
      {:noreply, %{state | last_analysis_tick: tick}}
    else
      {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # --- Analysis ---

  defp analyze_and_build(tick) do
    markets = Queries.all_markets()

    for market <- markets do
      supply = market.supply || %{}
      location = market.facility_id || market.id

      for {commodity, qty} <- supply do
        tracking_key = {location, commodity}

        if is_number(qty) and qty == 0 do
          # Track how long this commodity has been at zero
          case :ets.lookup(@ets_shortage_tracking, tracking_key) do
            [{_, first_zero_tick}] ->
              duration = tick - first_zero_tick

              if duration >= @shortage_threshold do
                maybe_start_construction(location, commodity, tick)
              end

            [] ->
              :ets.insert(@ets_shortage_tracking, {tracking_key, tick})
          end
        else
          # Supply recovered — clear tracking
          :ets.delete(@ets_shortage_tracking, tracking_key)
        end
      end
    end
  end

  defp maybe_start_construction(location, commodity, tick) do
    facility_type = Map.get(@shortage_to_facility, commodity)

    if facility_type do
      project_key = {location, facility_type}

      # Check if we already have a project for this location + type
      case :ets.lookup(@ets_projects, project_key) do
        [{_, _existing}] ->
          :ok

        [] ->
          # Check if this facility type already exists at this location
          existing = existing_facility_types_at(location)

          if facility_type not in existing do
            start_construction(location, facility_type, commodity, tick)
          end
      end
    end
  end

  defp existing_facility_types_at(location) do
    Queries.all_facilities()
    |> Enum.filter(&(&1.location == location))
    |> Enum.map(& &1.type)
  end

  defp start_construction(location, facility_type, shortage_commodity, tick) do
    materials = Map.get(@construction_costs, facility_type, %{})
    body_id = find_body_for_location(location)
    faction_id = find_faction_for_location(location)
    facility_name = generate_facility_name(location, facility_type)

    project = %{
      location: location,
      facility_type: facility_type,
      facility_name: facility_name,
      body_id: body_id,
      faction_id: faction_id,
      shortage_commodity: shortage_commodity,
      materials_required: materials,
      materials_delivered: %{},
      contracts_posted: false,
      started_at_tick: tick,
      status: :pending_materials
    }

    project_key = {location, facility_type}
    :ets.insert(@ets_projects, {project_key, project})

    Logger.info(
      "DemandAnalyzer: starting construction of #{facility_name} (#{facility_type}) at #{location} " <>
        "to address #{shortage_commodity} shortage. Materials: #{inspect(materials)}"
    )

    Simulator.Events.log(:construction_started, %{
      location: location,
      facility_type: facility_type,
      facility_name: facility_name,
      materials: materials,
      tick: tick
    })

    # Post delivery contracts for each material
    post_material_contracts(project, tick)
  end

  defp post_material_contracts(project, tick) do
    for {commodity, quantity} <- project.materials_required do
      # Find a source market that has this commodity
      source = find_source_for_commodity(commodity, project.location)

      case source do
        {source_location, source_pid} ->
          # Reserve goods at source
          case MarketAgent.reserve_goods(source_pid, %{
                 commodity: commodity,
                 quantity: min(quantity, 100),
                 owner_id: "construction-#{project.location}",
                 tick: tick
               }) do
            {:ok, reserve_id} ->
              distance = resolve_distance(source_location, project.location)
              delivery_fee = round(300 + distance * 3 + quantity * 0.5)

              ContractBoard.post_contract(%{
                contract_type: "construction_delivery",
                requestor_type: "construction",
                requestor_id: "construction-#{project.location}",
                faction_id: project.faction_id,
                commodity: to_string(commodity),
                quantity: min(quantity, 100),
                source_location: source_location,
                destination_location: project.location,
                payment: delivery_fee,
                delivery_fee: delivery_fee,
                cargo_deposit: 0,
                cargo_value: 0,
                reserve_id: reserve_id,
                urgency: 0.3,
                escalation_rate: 0.003,
                posted_at_tick: tick,
                deadline_tick: tick + (200 + distance * 3) * Config.tick_multiplier()
              })

            {:error, _} ->
              :ok
          end

        nil ->
          :ok
      end
    end
  end

  # --- Construction Progress ---

  defp check_construction_progress(tick) do
    projects = :ets.tab2list(@ets_projects)

    for {project_key, project} <- projects do
      # Check what materials have been delivered to the destination
      delivered = check_deliveries_at(project.location, project.materials_required)

      complete? =
        Enum.all?(project.materials_required, fn {commodity, needed} ->
          Map.get(delivered, commodity, 0) >= needed
        end)

      if complete? do
        # All materials delivered — build the facility!
        complete_construction(project, tick)
        :ets.delete(@ets_projects, project_key)
      else
        # Update delivered tracking and repost contracts if needed
        updated = %{project | materials_delivered: delivered}
        :ets.insert(@ets_projects, {project_key, updated})

        # Repost contracts for materials not yet fully delivered
        if tick - project.started_at_tick > 60 * Config.tick_multiplier() and
             not project.contracts_posted do
          post_material_contracts(updated, tick)
          :ets.insert(@ets_projects, {project_key, %{updated | contracts_posted: true}})
        end
      end
    end
  end

  defp check_deliveries_at(location, materials_required) do
    # Check the facility reserves at the location for construction materials
    facilities = Queries.all_facilities() |> Enum.filter(&(&1.location == location))

    combined_reserves =
      Enum.reduce(facilities, %{}, fn f, acc ->
        reserves = f.reserves || %{}

        Enum.reduce(reserves, acc, fn {commodity, qty}, inner ->
          if Map.has_key?(materials_required, commodity) do
            Map.update(inner, commodity, qty, &(&1 + qty))
          else
            inner
          end
        end)
      end)

    combined_reserves
  end

  # --- Facility Creation ---

  defp complete_construction(project, tick) do
    Logger.info(
      "DemandAnalyzer: construction complete! #{project.facility_name} " <>
        "(#{project.facility_type}) at #{project.location}"
    )

    # Consume construction materials from facility reserves
    consume_construction_materials(project)

    # Create DB records and spawn agents
    case create_facility(project) do
      {:ok, facility_id, market_id} ->
        Simulator.Events.log(:facility_constructed, %{
          facility_id: facility_id,
          market_id: market_id,
          facility_name: project.facility_name,
          facility_type: project.facility_type,
          location: project.location,
          tick: tick
        })

      {:error, reason} ->
        Logger.error("DemandAnalyzer: failed to create facility: #{inspect(reason)}")
    end
  end

  defp consume_construction_materials(project) do
    # Find the primary facility at the location and deduct materials from reserves
    case Simulator.Agents.Agent.whereis("facility-#{project.location}") do
      {:ok, pid} ->
        for {commodity, quantity} <- project.materials_required do
          GenServer.cast(pid, {:consume_reserve, commodity, quantity})
        end

      :error ->
        :ok
    end
  end

  defp create_facility(project) do
    # Find or create the location
    location =
      case Repo.get_by(Schemas.Location, name: project.location) do
        %Schemas.Location{} = loc -> loc
        nil -> nil
      end

    if location do
      facility_id =
        "facility-#{project.location}-#{project.facility_type}"

      type_str = to_string(project.facility_type)

      # Initial reserves based on facility type
      initial_reserves = initial_reserves_for(project.facility_type)

      # Create facility DB record
      case Repo.insert(
             %Schemas.Facility{
               name: project.facility_name,
               type: type_str,
               location_id: location.id,
               faction_id: project.faction_id,
               body_id: project.body_id,
               docking_capacity: 4,
               services: ["market"],
               condition: 1.0,
               reputation: 50,
               credits: 5000,
               initial_reserves: stringify_map(initial_reserves),
               state: %{"reserves" => stringify_map(initial_reserves)}
             },
             on_conflict: :nothing
           ) do
        {:ok, db_record} ->
          # Spawn FacilityAgent
          facility_config = %{
            id: facility_id,
            db_id: db_record.id,
            name: project.facility_name,
            location: project.location,
            type: project.facility_type,
            body: project.body_id,
            faction_id: project.faction_id,
            docking_capacity: 4,
            services: [:market],
            condition: 1.0,
            credits: 5000,
            reserves: initial_reserves,
            level: 1
          }

          DynamicSupervisor.start_child(
            Simulator.AgentSupervisor,
            {FacilityAgent, facility_config}
          )

          # Only spawn a new market if one doesn't already exist at this location
          market_id = "market-#{project.location}"

          case Simulator.Agents.Agent.whereis(market_id) do
            {:ok, _pid} ->
              # Market already exists
              {:ok, facility_id, market_id}

            :error ->
              # Create market DB record
              market_db =
                Repo.insert!(
                  %Schemas.Market{
                    facility_id: db_record.id,
                    facility_location: project.location,
                    prices: default_prices(),
                    supply: stringify_map(initial_reserves),
                    demand: %{},
                    production: %{},
                    consumption: %{"fuel" => 1},
                    price_elasticity: 0.02,
                    spread: 0.10,
                    state: %{}
                  },
                  on_conflict: :nothing,
                  conflict_target: :facility_id
                )

              market_config = %{
                id: market_id,
                db_id: market_db.id,
                facility_id: project.location,
                prices: default_prices(),
                supply: initial_reserves,
                demand: %{},
                production: %{},
                consumption: %{fuel: 1},
                price_elasticity: 0.02,
                spread: 0.10
              }

              DynamicSupervisor.start_child(
                Simulator.AgentSupervisor,
                {MarketAgent, market_config}
              )

              {:ok, facility_id, market_id}
          end

        {:error, changeset} ->
          {:error, changeset.errors}
      end
    else
      {:error, :location_not_found}
    end
  end

  # --- Helpers ---

  defp find_source_for_commodity(commodity, exclude_location) do
    Queries.all_markets()
    |> Enum.flat_map(fn market ->
      location = market.facility_id || market.id
      supply = Map.get(market.supply || %{}, commodity, 0)

      if is_number(supply) and supply > 50 and location != exclude_location do
        case Simulator.Agents.Agent.whereis("market-#{location}") do
          {:ok, pid} -> [{location, pid, supply}]
          :error -> []
        end
      else
        []
      end
    end)
    |> Enum.sort_by(&elem(&1, 2), :desc)
    |> case do
      [{loc, pid, _} | _] -> {loc, pid}
      [] -> nil
    end
  end

  defp find_body_for_location(location) do
    Simulator.World.Registry.body_id_for_location(location)
  end

  defp find_faction_for_location(location) do
    facilities = Queries.all_facilities() |> Enum.filter(&(&1.location == location))

    case facilities do
      [f | _] -> f.faction_id || "independent"
      [] -> "independent"
    end
  end

  defp generate_facility_name(location, facility_type) do
    location_name =
      location
      |> String.split("-")
      |> Enum.map(&String.capitalize/1)
      |> Enum.join(" ")

    type_name =
      case facility_type do
        :refinery -> "Refinery"
        :factory -> "Manufacturing"
        :farm -> "Hydroponics"
        :mining_rig -> "Mining Rig"
        :station -> "Station"
        other -> to_string(other) |> String.capitalize()
      end

    "#{location_name} #{type_name}"
  end

  defp initial_reserves_for(:refinery), do: %{fuel: 500, ore: 500, ice: 500}
  defp initial_reserves_for(:factory), do: %{fuel: 300, metals: 500, polymers: 300}
  defp initial_reserves_for(:farm), do: %{fuel: 200, water: 1000}
  defp initial_reserves_for(:mining_rig), do: %{fuel: 500}
  defp initial_reserves_for(:station), do: %{fuel: 1000, food: 500}
  defp initial_reserves_for(_), do: %{fuel: 300}

  defp resolve_distance(from, to) do
    case Simulator.World.Travel.travel_time(from, to) do
      {:ok, ticks} -> ticks
      {:error, _} -> 100
    end
  end

  defp default_prices do
    Map.new(Simulator.Economy.Commodities.all(), fn c ->
      {to_string(c), Simulator.Economy.Commodities.base_price(c)}
    end)
  end

  defp stringify_map(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  defp stringify_map(other), do: other
end
