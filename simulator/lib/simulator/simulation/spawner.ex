defmodule Simulator.Simulation.Spawner do
  @moduledoc """
  Boots the simulation world from Postgres.

  Reads all world data (systems, facilities, markets, ships, populations)
  from the database and spawns GenServer agents for each. The DB is
  populated by JSON seed files via `mix seed`.

  Call `spawn_world/0` to boot everything. Call `teardown/0` to stop all
  agents and reset the tick counter.
  """

  require Logger

  alias Simulator.Repo
  alias Simulator.Schemas.{CelestialBody, Faction, Facility, Market, Population, Ship, StarSystem}
  alias Simulator.Simulation.Config
  alias Simulator.World.{Body, Registry}
  alias Simulator.World.System, as: SystemAgent

  alias Simulator.Agents.{
    BodyAgent,
    FactionAgent,
    FacilityAgent,
    MarketAgent,
    PopAgent,
    ShipAgent
  }

  @doc """
  Spawns the complete world from database records.
  """
  @spec spawn_world() :: :ok
  def spawn_world do
    Logger.info("Spawner: booting simulation from database...")

    # Reload WorldRegistry from DB — retry if seed hasn't finished yet
    system_count = wait_for_systems(5)

    if system_count == 0 do
      raise "Spawner: no systems started — cannot boot simulation (is DB seeded?)"
    end

    spawn_all_facilities()
    market_count = spawn_all_markets()

    if market_count == 0 do
      raise "Spawner: no markets started — cannot boot ships safely"
    end

    spawn_all_body_agents()
    spawn_all_populations()
    spawn_all_faction_agents()
    spawn_all_ships()
    register_spatial()
    start_ticking()

    Logger.info("Spawner: world is live!")
    :ok
  end

  @doc """
  Stops all agents and the tick coordinator. Used for reset/testing.
  """
  @spec teardown() :: :ok
  def teardown do
    Simulator.TickCoordinator.stop()

    for {_, pid, _, _} <- DynamicSupervisor.which_children(Simulator.AgentSupervisor) do
      DynamicSupervisor.terminate_child(Simulator.AgentSupervisor, pid)
    end

    :ok
  end

  # --- Systems ---

  defp wait_for_systems(retries) do
    Registry.reload()
    count = spawn_all_systems()

    if count == 0 and retries > 0 do
      Logger.info("Spawner: no systems found, waiting for seed... (#{retries} retries left)")
      Process.sleep(2_000)
      wait_for_systems(retries - 1)
    else
      count
    end
  end

  defp spawn_all_systems do
    systems = Repo.all(StarSystem) |> Repo.preload(celestial_bodies: :locations)

    started =
      Enum.count(systems, fn system ->
        system_id = build_system_id(system.name)

        bodies =
          Map.new(system.celestial_bodies, fn cb ->
            bid = cb.body_id || String.downcase(cb.name)

            {bid,
             %Body{
               id: bid,
               name: cb.name,
               type: safe_to_atom(cb.type),
               orbit_radius: cb.orbit_radius,
               orbit_period: cb.orbit_period,
               current_angle: cb.current_angle || 0.0,
               resources: atomize_map(cb.resources || %{})
             }}
          end)

        # Build facilities map: body_id → [location_names]
        facilities_map =
          Enum.reduce(system.celestial_bodies, %{}, fn cb, acc ->
            body_id = cb.body_id || String.downcase(cb.name)
            location_names = Enum.map(cb.locations, & &1.name)

            if location_names != [] do
              Map.put(acc, body_id, location_names)
            else
              acc
            end
          end)

        config = %{
          id: system_id,
          name: system.name,
          bodies: bodies,
          facilities: facilities_map
        }

        start_agent(SystemAgent, config) != nil
      end)

    Logger.info("Spawner: #{started}/#{length(systems)} systems online")
    started
  end

  # --- Facilities ---

  defp spawn_all_facilities do
    facilities = Repo.all(Facility) |> Repo.preload(:location)
    crew_count = 0

    crew_count =
      Enum.reduce(facilities, crew_count, fn facility, acc ->
        facility_type = safe_to_atom(facility.type)
        location_name = if facility.location, do: facility.location.name

        # Use the original JSON-style ID convention: facility-{location} for
        # the main facility, facility-{location}-{type} for secondary ones
        facility_id =
          if location_name do
            base = "facility-#{location_name}"

            # Check if this ID is already taken (multiple facilities per location)
            case Simulator.Agents.Agent.whereis(base) do
              {:ok, _} -> "facility-#{location_name}-#{facility.type}"
              :error -> base
            end
          else
            "facility-#{String.downcase(String.replace(facility.name, " ", "-"))}"
          end

        crew_roles = facility_crew_roles(facility_type)

        # Prefer the live-tick reserves from state JSONB over the seed
        # `initial_reserves` — the persist_state hook keeps the former
        # current as mining / recipes / contracts run.
        saved_state = facility.state || %{}

        reserves =
          atomize_map(saved_state["reserves"] || facility.initial_reserves || %{})

        config = %{
          id: facility_id,
          db_id: facility.id,
          name: facility.name,
          location: location_name,
          body: facility.body_id,
          type: facility_type,
          docking_capacity: facility.docking_capacity,
          services: Enum.map(facility.services || [], &safe_to_atom/1),
          reserves: reserves,
          faction_id: facility.faction_id,
          crew_roles: crew_roles,
          # FacilityAgent.restore_crew/1 rehydrates via
          # CrewComplement.deserialize/2 when the blob is present.
          crew: saved_state["crew"],
          condition: facility.condition,
          reputation: facility.reputation,
          credits: facility.credits,
          level: saved_state["level"] || 5
        }

        start_agent(FacilityAgent, config)
        acc + length(crew_roles)
      end)

    Logger.info("Spawner: #{length(facilities)} facilities + #{crew_count} crew online")
  end

  # --- Markets ---

  defp spawn_all_markets do
    markets = Repo.all(Market) |> Repo.preload(:facility)

    started =
      Enum.count(markets, fn market ->
        facility_location = market.facility_location || (market.facility && market.facility.name)

        db_state = market.state || %{}

        config = %{
          id: "market-#{facility_location}",
          facility_id: facility_location,
          prices: atomize_map(market.prices || %{}),
          supply: atomize_map(market.supply || %{}),
          demand: atomize_map(market.demand || %{}),
          production: atomize_map(market.production || %{}),
          consumption: atomize_map(market.consumption || %{}),
          price_elasticity: market.price_elasticity || 0.02,
          spread: market.spread || 0.10,
          pending_buy_orders: MarketAgent.deserialize_orders(db_state["pending_buy_orders"]),
          pending_sell_orders: MarketAgent.deserialize_orders(db_state["pending_sell_orders"]),
          # Preserve the price chart + latest trade volume so the UI
          # and any price-memory consumers don't snap back to empty
          # on restart. Legit volatile buffers (shortage_ticks,
          # consumption_window) stay volatile — rebuild in <100 ticks.
          price_history: atomize_map(db_state["price_history"] || %{}),
          trade_volume: atomize_map(db_state["trade_volume"] || %{}),
          db_id: market.id
        }

        start_agent(MarketAgent, config) != nil
      end)

    Logger.info("Spawner: #{started}/#{length(markets)} markets online")
    started
  end

  # --- Body Agents ---

  defp spawn_all_body_agents do
    bodies = Repo.all(CelestialBody) |> Repo.preload(:locations)

    started =
      Enum.count(bodies, fn body ->
        body_id = body.body_id || String.downcase(String.replace(body.name, " ", "-"))
        locations = Enum.map(body.locations, & &1.name)

        # Restore any persisted mutable state (richness after mining, etc.);
        # fall back to seed richness from the resources column on first boot.
        persisted_resources =
          case body.state do
            %{"resources" => r} when is_map(r) -> r
            _ -> nil
          end

        resources = persisted_resources || body.resources || %{}

        config = %{
          id: "body-#{body_id}",
          body_id: body_id,
          name: body.name,
          biome: body.biome,
          resources: resources,
          locations: locations,
          db_id: body.id
        }

        start_agent(BodyAgent, config) != nil
      end)

    Logger.info("Spawner: #{started}/#{length(bodies)} body agents online")
    started
  end

  # --- Faction Agents ---

  defp spawn_all_faction_agents do
    factions = Repo.all(Faction)

    # Group facility locations by faction_id so each FactionAgent knows
    # which markets to subscribe to and which facilities to tax.
    facilities = Repo.all(Facility) |> Repo.preload(:location)

    members_by_faction =
      Enum.reduce(facilities, %{}, fn facility, acc ->
        faction_id = facility.faction_id || "independent"
        loc = if facility.location, do: facility.location.name

        if loc do
          Map.update(acc, faction_id, [loc], &[loc | &1])
        else
          acc
        end
      end)

    started =
      Enum.count(factions, fn faction ->
        member_facilities =
          members_by_faction
          |> Map.get(faction.id, [])
          |> Enum.uniq()

        config = %{
          id: "faction-#{faction.id}",
          faction_id: faction.id,
          name: faction.name,
          personality: faction.personality || %{},
          treasury: faction.treasury || 0,
          member_facilities: member_facilities,
          db_id: faction.id
        }

        start_agent(FactionAgent, config) != nil
      end)

    Logger.info("Spawner: #{started}/#{length(factions)} faction agents online")
    started
  end

  # --- Populations ---

  defp spawn_all_populations do
    populations = Repo.all(Population) |> Repo.preload(facility: :location)

    for pop <- populations do
      facility_location =
        if pop.facility && pop.facility.location, do: pop.facility.location.name

      prod_commodity =
        if pop.production_commodity,
          do: safe_to_atom(pop.production_commodity),
          else: nil

      # Top-level columns (population_count, overall_sentiment, unrest,
      # total_wealth, food_satisfaction) are updated in place by
      # PopAgent.persist_state, so `pop.*` IS the live value, not a seed.
      # The state JSONB carries the softer secondary fields.
      saved_state = pop.state || %{}

      config = %{
        id: "pop-#{String.downcase(String.replace(pop.label, " ", "-"))}",
        db_id: pop.id,
        label: pop.label,
        facility_id: facility_location,
        demographic: safe_to_atom(pop.demographic),
        faction_id: pop.faction_id,
        population_count: pop.population_count,
        overall_sentiment: pop.overall_sentiment,
        unrest: pop.unrest,
        food_satisfaction: pop.food_satisfaction || 50,
        total_wealth: pop.total_wealth,
        consumption: atomize_map(pop.consumption || %{}),
        production_commodity: prod_commodity,
        production_amount: pop.production_amount || 0,
        growth_rate: pop.growth_rate || 0.001,
        spending_rate: pop.spending_rate || 0.02,
        employed_fraction: pop.employed_fraction || 0.85,
        migration_pressure: saved_state["migration_pressure"] || 0.0,
        safety_satisfaction: saved_state["safety_satisfaction"] || 80,
        entertainment_satisfaction: saved_state["entertainment_satisfaction"] || 50,
        labor_output: saved_state["labor_output"] || 0,
        body_food_multiplier: saved_state["body_food_multiplier"] || 1.0
      }

      start_agent(PopAgent, config)
    end

    Logger.info("Spawner: #{length(populations)} populations online")
  end

  # --- Ships ---

  defp spawn_all_ships do
    ships = Repo.all(Ship) |> Repo.preload(:location)

    # Pre-cache all market prices from DB (one query instead of N per ship)
    price_cache = build_price_cache()

    crew_count =
      Enum.reduce(ships, 0, fn ship, acc ->
        class_atom = safe_to_atom(ship.class || "freighter")
        saved = ship.state || %{}

        # Resolve location: use DB location, or if ship was in transit,
        # place it at the transit destination (it would have arrived by now)
        location_name =
          cond do
            ship.location -> ship.location.name
            transit = saved["transit"] -> transit["to"]
            true -> nil
          end

        {ox, oy} = {ship.universe_offset_x || 0.0, ship.universe_offset_y || 0.0}

        ship_id = "ship-#{String.downcase(String.replace(ship.name, ~r/[^a-zA-Z0-9]/, "-"))}"

        class_stats = Map.get(Config.ship_classes(), class_atom, Config.ship_classes().freighter)
        crew_roles = class_stats.crew_roles

        faction_rep =
          if ship.faction_reputation && map_size(ship.faction_reputation) > 0 do
            ship.faction_reputation
          else
            Config.default_reputation(ship.faction_id || "independent")
          end

        # Restore volatile state from JSONB (saved is defined above)
        personality =
          if p = saved["personality"] do
            atomize_map(p)
          else
            nil
          end

        saved_rep =
          if r = saved["faction_reputation"] do
            Map.new(r, fn {k, v} -> {to_string(k), v} end)
          end

        known_prices =
          if kp = saved["memory"]["known_prices"] do
            restore_price_memory(kp)
          else
            build_price_knowledge_cached(location_name, price_cache)
          end

        config = %{
          id: ship_id,
          db_id: ship.id,
          name: ship.name,
          class: class_atom,
          location: location_name,
          system_id: ship.system_id || "system-sol",
          universe_offset: {ox, oy},
          credits: ship.credits,
          fuel: ship.fuel,
          fuel_capacity: ship.fuel_capacity,
          fuel_consumption_rate: ship.fuel_consumption_rate,
          speed_modifier: ship.speed_modifier || 1.0,
          cargo: atomize_map(ship.cargo || %{}),
          cargo_capacity: ship.cargo_capacity,
          passenger_capacity: Map.get(class_stats, :passenger_capacity, 0),
          passengers: saved["passengers"] || 0,
          faction_id: ship.faction_id || "independent",
          faction_reputation: saved_rep || faction_rep,
          personality: personality,
          crew_roles: crew_roles,
          # Passed as a map; ShipAgent.restore_crew/1 rehydrates via
          # CrewComplement.deserialize/2 when present.
          crew: saved["crew"],
          known_prices: known_prices,
          position: {ship.position_x || 0.0, ship.position_y || 0.0},
          broke_strikes: saved["broke_strikes"] || 0,
          idle_ticks: saved["idle_ticks"] || 0,
          hoard_strikes: saved["hoard_strikes"] || 0,
          cargo_age: atomize_map(saved["cargo_age"] || %{})
        }

        start_agent(ShipAgent, config)
        acc + length(crew_roles)
      end)

    Logger.info("Spawner: #{length(ships)} ships + #{crew_count} crew online")
  end

  # --- Crew ---

  defp facility_crew_roles(type) do
    case type do
      :station -> [:engineer, :engineer, :medic, :trader, :general, :general]
      :outpost -> [:engineer, :general, :general]
      _ -> [:engineer, :general]
    end
  end

  # --- Spatial Registration ---

  defp register_spatial do
    alias Simulator.Spatial.{ChunkManager, Observer, PositionTracker}

    for system_id <- Registry.system_ids() do
      {ox, oy} = Registry.universe_offset(system_id)

      body_positions =
        case Simulator.Agents.Agent.whereis(system_id) do
          {:ok, pid} ->
            Simulator.World.System.get_body_positions(pid)
            |> Map.new(fn {body_id, %{x: x, y: y}} -> {body_id, {ox + x, oy + y}} end)

          :error ->
            %{}
        end

      # Register all agents at this system's locations
      agents =
        Simulator.Queries.all_agents_of_type(:ship) ++
          Simulator.Queries.all_agents_of_type(:facility) ++
          Simulator.Queries.all_agents_of_type(:market) ++
          Simulator.Queries.all_agents_of_type(:population)

      for {agent_id, agent_state} <- agents do
        location = Map.get(agent_state, :location)

        if location do
          case PositionTracker.body_id_for_location(location) do
            nil ->
              :ok

            body_id ->
              {x, y} = Map.get(body_positions, body_id, {ox, oy})
              ChunkManager.register_entity(agent_id, x, y)
          end
        end
      end
    end

    # Add default observer
    ChunkManager.add_observer(%Observer{
      id: "default",
      x: 0.0,
      y: 0.0,
      radius: 50.0,
      owner: :system,
      label: "Observer"
    })

    entity_count = :ets.info(:agent_positions, :size) || 0
    Logger.info("Spawner: spatial system registered (#{entity_count} entities)")
  end

  # --- Helpers ---

  defp start_ticking do
    Simulator.TickCoordinator.set_speed(Config.tick_interval_ms())
    Simulator.TickCoordinator.start()
    Logger.info("Spawner: tick coordinator started (#{Config.tick_interval_ms()}ms interval)")
  end

  defp start_agent(module, config) do
    case DynamicSupervisor.start_child(Simulator.AgentSupervisor, {module, config}) do
      {:ok, pid} ->
        pid

      {:error, reason} ->
        Logger.error(
          "Spawner: failed to start #{inspect(module)} #{config[:id] || config[:name]}: #{inspect(reason)}"
        )

        nil
    end
  end

  defp build_system_id(name) do
    "system-#{name |> String.downcase() |> String.replace(" ", "-")}"
  end

  defp build_price_cache do
    # Single query: load all market prices into a location => prices map
    Repo.all(Market)
    |> Map.new(fn market ->
      prices =
        Map.new(market.prices || %{}, fn {commodity, price} ->
          {safe_to_atom(commodity), %{price: price, tick: 0}}
        end)

      {market.facility_location, prices}
    end)
  end

  defp restore_price_memory(saved_prices) when is_map(saved_prices) do
    Map.new(saved_prices, fn {location, commodities} ->
      restored =
        Map.new(commodities || %{}, fn
          {commodity, %{"price" => p, "tick" => t}} ->
            {safe_to_atom(commodity), %{price: p, tick: t}}

          {commodity, price} when is_number(price) ->
            {safe_to_atom(commodity), price}

          {commodity, other} ->
            {safe_to_atom(commodity), other}
        end)

      {to_string(location), restored}
    end)
  end

  defp restore_price_memory(_), do: %{}

  defp build_price_knowledge_cached(nil, _cache), do: %{}

  defp build_price_knowledge_cached(location, cache) do
    reachable = [location | Simulator.World.Travel.reachable_from(location)]

    Map.new(reachable, fn loc ->
      {loc, Map.get(cache, loc, %{})}
    end)
  end

  defp atomize_map(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_binary(k) ->
        atom_key =
          try do
            safe_to_atom(k)
          rescue
            ArgumentError -> String.to_atom(k)
          end

        {atom_key, v}

      {k, v} ->
        {k, v}
    end)
  end

  defp atomize_map(other), do: other

  defp safe_to_atom(str) when is_binary(str) do
    String.to_atom(str)
  end

  defp safe_to_atom(atom) when is_atom(atom), do: atom
end
