defmodule Simulator.Admin do
  @moduledoc """
  God-mode helpers for the Godot client: create / destroy / adjust
  live agents.

  Wraps the DB + supervisor dance so the REST layer stays thin.
  Every mutation is atomic from the caller's perspective:

    * `create_ship/1` — inserts the DB row, spawns the agent, returns
      the unique id (name collisions get `-2`, `-3`, ... suffixes).
    * `destroy_ship/1` — terminates the agent, deletes the row,
      broadcasts a `:ship_decommissioned` event.
    * `create_facility/1` — inserts Location + Facility + Market rows
      and spawns all three agents (FacilityAgent, MarketAgent, plus a
      matching BodyAgent refresh).
    * `destroy_facility/1` — cascade: evict docked ships, drop
      contracts, terminate market/pop/facility agents, cascade DB
      delete handles populations + markets.
    * `adjust_supply/3` — send a delta (positive or negative) to a
      market's supply ledger.

  No auth — the endpoint is loopback-only by default.
  """

  require Logger

  alias Simulator.Agents.{FacilityAgent, MarketAgent, ShipAgent}
  alias Simulator.Economy.{Commodities, ContractBoard}
  alias Simulator.Repo
  alias Simulator.Schemas.{CelestialBody, Facility, Location, Market, Ship}
  alias Simulator.Simulation.Config
  alias Simulator.World.Registry, as: WorldRegistry

  @supervisor Simulator.AgentSupervisor

  # --- Ships ---

  @doc """
  Creates a ship with the given params and spawns its agent.

  Expected keys (strings or atoms): `name`, `class`, `faction_id`,
  `location`, and optionally `credits`. Missing / unknown class falls
  back to `:freighter`.
  """
  @spec create_ship(map()) :: {:ok, map()} | {:error, atom() | String.t()}
  def create_ship(params) do
    with {:ok, name} <- fetch_nonempty(params, "name"),
         {:ok, class_atom} <- resolve_ship_class(params),
         {:ok, faction_id} <- fetch_nonempty(params, "faction_id"),
         {:ok, location} <- fetch_nonempty(params, "location"),
         {:ok, location_row} <- fetch_location(location) do
      ship_id = uniquify_ship_id(slugify("ship-" <> name))
      class_stats = Map.fetch!(Config.ship_classes(), class_atom)
      credits = fetch_int(params, "credits", 5_000)

      ship_row =
        %Ship{}
        |> Ship.changeset(%{
          name: name,
          class: to_string(class_atom),
          location_id: location_row.id,
          cargo: %{},
          cargo_capacity: class_stats.cargo_capacity,
          fuel: class_stats.fuel_capacity,
          fuel_capacity: class_stats.fuel_capacity,
          fuel_consumption_rate: class_stats.fuel_consumption_rate,
          credits: credits,
          state: %{}
        })
        |> Repo.insert!()

      config = %{
        id: ship_id,
        db_id: ship_row.id,
        name: name,
        class: class_atom,
        location: location,
        system_id: default_system_id(location_row),
        credits: credits,
        fuel: class_stats.fuel_capacity,
        fuel_capacity: class_stats.fuel_capacity,
        fuel_consumption_rate: class_stats.fuel_consumption_rate,
        speed_modifier: Map.get(class_stats, :speed_modifier, 1.0),
        cargo_capacity: class_stats.cargo_capacity,
        passenger_capacity: Map.get(class_stats, :passenger_capacity, 0),
        faction_id: faction_id,
        faction_reputation: Config.default_reputation(faction_id),
        crew_roles: class_stats.crew_roles
      }

      {:ok, _pid} = DynamicSupervisor.start_child(@supervisor, {ShipAgent, config})

      {:ok,
       %{
         id: ship_id,
         name: name,
         class: class_atom,
         faction_id: faction_id,
         location: location,
         credits: credits
       }}
    end
  end

  @doc """
  Terminates a ship's agent and deletes its DB row.
  """
  @spec destroy_ship(String.t()) :: :ok | {:error, :not_found}
  def destroy_ship(ship_id) when is_binary(ship_id) do
    case Simulator.Agents.Agent.whereis(ship_id) do
      {:ok, pid} ->
        state = :sys.get_state(pid)
        DynamicSupervisor.terminate_child(@supervisor, pid)

        if db_id = state[:__db_id__] do
          case Repo.get(Ship, db_id) do
            nil -> :ok
            ship -> Repo.delete!(ship)
          end
        end

        Simulator.Events.broadcast("ship_events", :ship_decommissioned, %{
          ship_id: ship_id,
          reason: :admin_destroyed,
          tick: Simulator.TickCoordinator.get_tick()
        })

        :ok

      :error ->
        {:error, :not_found}
    end
  end

  # --- Facilities ---

  @doc """
  Creates a facility + location + market triple and spawns all agents.

  Expected keys: `name`, `type`, `faction_id`, `body_id`, `location_name`,
  optional `credits`, optional `docking_capacity`.
  """
  @spec create_facility(map()) :: {:ok, map()} | {:error, atom() | String.t()}
  def create_facility(params) do
    with {:ok, name} <- fetch_nonempty(params, "name"),
         {:ok, type_atom} <- resolve_facility_type(params),
         {:ok, faction_id} <- fetch_nonempty(params, "faction_id"),
         {:ok, body_id} <- fetch_nonempty(params, "body_id"),
         {:ok, body_row} <- fetch_body(body_id),
         {:ok, location_name} <- fetch_nonempty(params, "location_name") do
      location_name = uniquify_location_name(slugify(location_name))
      credits = fetch_int(params, "credits", 10_000)
      docking_capacity = fetch_int(params, "docking_capacity", 4)
      reserves = initial_reserves_for(type_atom)

      # Location row first — Facility FK targets it. Pin to the body.
      location_row =
        %Location{}
        |> Ecto.Changeset.change(%{
          name: location_name,
          type: to_string(type_atom),
          celestial_body_id: body_row.id
        })
        |> Repo.insert!()

      # Facility row. Use the permissive changeset that now accepts
      # the full set of types the sim uses.
      facility_row =
        %Facility{}
        |> Facility.changeset(%{
          name: name,
          type: to_string(type_atom),
          location_id: location_row.id,
          faction_id: faction_id,
          body_id: body_id,
          docking_capacity: docking_capacity,
          services: ["refuel", "market"],
          condition: 1.0,
          reputation: 50,
          credits: credits,
          initial_reserves: stringify_keys(reserves),
          state: %{"reserves" => stringify_keys(reserves)}
        })
        |> Repo.insert!()

      # Market row paired with the facility.
      market_row =
        %Market{}
        |> Ecto.Changeset.change(%{
          facility_id: facility_row.id,
          facility_location: location_name,
          prices: default_prices(),
          supply: %{},
          demand: %{},
          production: %{},
          consumption: %{},
          price_elasticity: 0.02,
          spread: 0.10,
          state: %{}
        })
        |> Repo.insert!()

      facility_id = "facility-#{location_name}"
      market_id = "market-#{location_name}"

      facility_config = %{
        id: facility_id,
        db_id: facility_row.id,
        name: name,
        location: location_name,
        body: body_id,
        type: type_atom,
        docking_capacity: docking_capacity,
        services: [:refuel, :market],
        reserves: reserves,
        faction_id: faction_id,
        crew_roles: facility_crew_roles(type_atom),
        condition: 1.0,
        reputation: 50,
        credits: credits,
        level: 1
      }

      market_config = %{
        id: market_id,
        db_id: market_row.id,
        facility_id: location_name,
        prices: default_prices(),
        supply: %{},
        demand: %{},
        production: %{},
        consumption: %{},
        price_elasticity: 0.02,
        spread: 0.10
      }

      {:ok, _} = DynamicSupervisor.start_child(@supervisor, {FacilityAgent, facility_config})
      {:ok, _} = DynamicSupervisor.start_child(@supervisor, {MarketAgent, market_config})

      # Refresh the World Registry so other lookups see the new
      # location → body mapping immediately.
      WorldRegistry.reload()

      Simulator.Events.broadcast("facility_events", :facility_constructed, %{
        facility_id: facility_id,
        market_id: market_id,
        location: location_name,
        body_id: body_id,
        faction_id: faction_id,
        tick: Simulator.TickCoordinator.get_tick()
      })

      {:ok,
       %{
         facility_id: facility_id,
         market_id: market_id,
         location: location_name,
         type: type_atom,
         faction_id: faction_id,
         body_id: body_id,
         credits: credits
       }}
    end
  end

  @doc """
  Destroys a facility and its co-located market + pops. Evicts any
  docked ships and drops all contracts the facility was requestor for.
  """
  @spec destroy_facility(String.t()) :: :ok | {:error, :not_found}
  def destroy_facility(facility_id) when is_binary(facility_id) do
    case Simulator.Agents.Agent.whereis(facility_id) do
      {:ok, facility_pid} ->
        facility_state = :sys.get_state(facility_pid)
        location = facility_state.location

        evict_docked_ships(facility_state.docked_ships)
        drop_contracts_for(facility_id)
        terminate_pops_at(location)
        terminate_agent_at("market-#{location}")
        DynamicSupervisor.terminate_child(@supervisor, facility_pid)

        if db_id = facility_state[:__db_id__] do
          case Repo.get(Facility, db_id) do
            nil -> :ok
            facility -> Repo.delete!(facility)
          end
        end

        WorldRegistry.reload()

        Simulator.Events.broadcast("facility_events", :facility_destroyed, %{
          facility_id: facility_id,
          location: location,
          tick: Simulator.TickCoordinator.get_tick()
        })

        :ok

      :error ->
        {:error, :not_found}
    end
  end

  # --- Markets ---

  @doc """
  Adjusts supply at a market by the given delta map (positive adds,
  negative subtracts, floored at 0).
  """
  @spec adjust_supply(String.t(), String.t(), number()) :: :ok | {:error, :not_found}
  def adjust_supply(location, commodity, delta)
      when is_binary(location) and is_binary(commodity) and is_number(delta) do
    case Simulator.Agents.Agent.whereis("market-#{location}") do
      {:ok, pid} ->
        atom = to_commodity_atom(commodity)
        MarketAgent.add_supply(pid, %{atom => delta})
        :ok

      :error ->
        {:error, :not_found}
    end
  end

  # --- Save games ---

  @doc """
  Forces a synchronous flush of all agent state to the DB and
  checkpoints the SQLite WAL so the `.db` file is safe to copy.

  Returns `{:ok, %{tick: current_tick, flushed: count, duration_ms: n}}`.
  """
  @spec save() :: {:ok, map()}
  def save do
    start = System.monotonic_time(:millisecond)
    # Drain the dirty set first so any agents that just mark_dirty'd
    # don't miss the snapshot. Then walk every registered agent and
    # ask it to persist — bypasses the dirty flag so agents that
    # haven't ticked recently still write.
    Simulator.PersistenceManager.flush()
    count = persist_all_agents()
    contracts = snapshot_contract_board()
    checkpoint_wal()
    duration_ms = System.monotonic_time(:millisecond) - start

    {:ok,
     %{
       tick: tick_or_zero(),
       flushed: count,
       contracts: contracts,
       duration_ms: duration_ms
     }}
  end

  @doc """
  Copies the active `.db` (plus `-wal` and `-shm` sidecars if present)
  to `saves_dir()/<name>.db` after a full flush.
  """
  @spec save_as(String.t()) :: {:ok, map()} | {:error, atom() | {atom(), String.t()}}
  def save_as(raw_name) when is_binary(raw_name) do
    with {:ok, name} <- sanitize_save_name(raw_name) do
      dest = Path.join(saves_dir(), name <> ".db")
      src = current_db_path()

      cond do
        dest == src -> {:error, :cannot_overwrite_active_save}
        true -> do_save_as(src, dest, name)
      end
    end
  end

  def save_as(_), do: {:error, :invalid_name}

  @doc """
  Lists `.db` files in the saves directory. Each entry includes file
  size and mtime; the currently-active DB is marked `active: true`.
  """
  @spec list_saves() :: {:ok, [map()]}
  def list_saves do
    dir = saves_dir()
    active = current_db_path() |> Path.basename()

    entries =
      case File.ls(dir) do
        {:ok, files} -> files
        {:error, _} -> []
      end

    saves =
      entries
      |> Enum.filter(&String.ends_with?(&1, ".db"))
      |> Enum.map(fn filename ->
        path = Path.join(dir, filename)
        stat = File.stat!(path, time: :posix)

        %{
          name: Path.rootname(filename),
          filename: filename,
          path: path,
          size_bytes: stat.size,
          modified_at: DateTime.from_unix!(stat.mtime),
          active: filename == active
        }
      end)
      |> Enum.sort_by(& &1.modified_at, {:desc, DateTime})

    {:ok, saves}
  end

  # --- Save-game helpers ---

  @agent_type_modules %{
    ship: Simulator.Agents.ShipAgent,
    facility: Simulator.Agents.FacilityAgent,
    market: Simulator.Agents.MarketAgent,
    population: Simulator.Agents.PopAgent,
    body: Simulator.Agents.BodyAgent,
    faction: Simulator.Agents.FactionAgent
  }

  defp persist_all_agents do
    Registry.select(Simulator.AgentRegistry, [
      {{{:agent, :"$1"}, :"$2", :"$3"}, [], [:"$2"]}
    ])
    |> Enum.reduce(0, fn pid, acc ->
      try do
        state = :sys.get_state(pid, 2_000)

        case @agent_type_modules[state[:__agent_type__]] do
          nil ->
            acc

          mod ->
            if function_exported?(mod, :persist_state, 1) do
              mod.persist_state(state)
              acc + 1
            else
              acc
            end
        end
      rescue
        _ -> acc
      catch
        :exit, _ -> acc
      end
    end)
  end

  defp snapshot_contract_board do
    case ContractBoard.snapshot() do
      {:ok, count} -> count
    end
  rescue
    _ -> 0
  catch
    :exit, _ -> 0
  end

  defp checkpoint_wal do
    # TRUNCATE forces WAL contents into the main DB and truncates the
    # WAL file to zero — the file snapshot taken immediately after is
    # a complete, copyable DB.
    Simulator.Repo.query!("PRAGMA wal_checkpoint(TRUNCATE)", [])
    :ok
  rescue
    _ -> :ok
  end

  defp do_save_as(src, dest, name) do
    File.cp!(src, dest)

    # WAL sidecars — defensive copy so even if a page is still in the
    # WAL at copy time, the destination remains consistent.
    for ext <- ["-wal", "-shm"] do
      sidecar = src <> ext
      if File.exists?(sidecar), do: File.cp!(sidecar, dest <> ext)
    end

    %{size: size} = File.stat!(dest)

    {:ok,
     %{
       name: name,
       filename: name <> ".db",
       path: dest,
       size_bytes: size
     }}
  end

  defp sanitize_save_name(name) do
    cleaned =
      name
      |> String.trim()
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9_-]+/, "_")
      |> String.slice(0, 64)

    cond do
      cleaned == "" -> {:error, :invalid_name}
      String.contains?(name, "..") -> {:error, :invalid_name}
      true -> {:ok, cleaned}
    end
  end

  defp current_db_path do
    Application.get_env(:simulator, Simulator.Repo)[:database] ||
      raise "Simulator.Repo has no :database configured"
  end

  defp saves_dir do
    current_db_path() |> Path.dirname()
  end

  defp tick_or_zero do
    Simulator.TickCoordinator.get_tick()
  catch
    :exit, _ -> 0
  end

  # --- Facility destroy cascade helpers ---

  defp evict_docked_ships(ship_ids) do
    for ship_id <- ship_ids do
      case Simulator.Agents.Agent.whereis(ship_id) do
        {:ok, pid} -> GenServer.cast(pid, :force_undock)
        :error -> :ok
      end
    end
  end

  defp drop_contracts_for(facility_id) do
    contracts = ContractBoard.contracts_for(facility_id)

    for c <- contracts do
      # Goes through the board so ETS + DB rows come out together.
      ContractBoard.delete_contract(c.id)
    end
  end

  defp terminate_pops_at(location) do
    prefix = "pop-" <> String.replace(location, "-", "-")

    Registry.select(Simulator.AgentRegistry, [
      {{{:agent, :"$1"}, :"$2", :"$3"}, [], [{{:"$1", :"$2"}}]}
    ])
    |> Enum.each(fn {agent_id, pid} ->
      # Pop IDs are derived from the facility location (e.g.,
      # "pop-earth-station-workers"), so a location prefix match is a
      # safe filter.
      if String.starts_with?(agent_id, prefix) do
        DynamicSupervisor.terminate_child(@supervisor, pid)
      end
    end)

    # Pop DB rows cascade when the facility row is deleted via
    # populations.facility_id on_delete: :delete_all — no explicit
    # deletion needed here.
  end

  defp terminate_agent_at(id) do
    case Simulator.Agents.Agent.whereis(id) do
      {:ok, pid} -> DynamicSupervisor.terminate_child(@supervisor, pid)
      :error -> :ok
    end
  end

  # --- Name / ID plumbing ---

  defp slugify(s) do
    s
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp uniquify_ship_id(base), do: uniquify(base, &Simulator.Agents.Agent.whereis/1)

  defp uniquify_location_name(base) do
    uniquify(base, fn name ->
      case Repo.get_by(Location, name: name) do
        nil -> :error
        _ -> {:ok, :exists}
      end
    end)
  end

  defp uniquify(base, probe_fn, suffix \\ 1) do
    candidate = if suffix == 1, do: base, else: "#{base}-#{suffix}"

    case probe_fn.(candidate) do
      :error -> candidate
      _ -> uniquify(base, probe_fn, suffix + 1)
    end
  end

  # --- Parameter plumbing ---

  defp fetch_nonempty(params, key) do
    case params[key] || params[String.to_atom(key)] do
      v when is_binary(v) and byte_size(v) > 0 -> {:ok, v}
      _ -> {:error, {:missing_param, key}}
    end
  end

  defp fetch_int(params, key, default) do
    case params[key] || params[String.to_atom(key)] do
      n when is_integer(n) ->
        n

      n when is_binary(n) ->
        case Integer.parse(n) do
          {int, _} -> int
          _ -> default
        end

      _ ->
        default
    end
  end

  defp fetch_location(name) do
    case Repo.get_by(Location, name: name) do
      nil -> {:error, {:unknown_location, name}}
      loc -> {:ok, loc}
    end
  end

  defp fetch_body(body_id) do
    case Repo.get_by(CelestialBody, body_id: body_id) do
      nil -> {:error, {:unknown_body, body_id}}
      body -> {:ok, body}
    end
  end

  defp resolve_ship_class(params) do
    raw = params["class"] || params[:class] || "freighter"
    atom = safe_atom(raw)

    cond do
      is_atom(atom) and Map.has_key?(Config.ship_classes(), atom) -> {:ok, atom}
      true -> {:error, {:unknown_ship_class, raw}}
    end
  end

  defp resolve_facility_type(params) do
    raw = params["type"] || params[:type] || "station"

    case safe_atom(raw) do
      atom when atom in [:station, :outpost, :mining_rig, :refinery, :factory, :farm, :hub] ->
        {:ok, atom}

      _ ->
        {:error, {:unknown_facility_type, raw}}
    end
  end

  defp safe_atom(a) when is_atom(a), do: a

  defp safe_atom(s) when is_binary(s) do
    try do
      String.to_existing_atom(s)
    rescue
      ArgumentError -> nil
    end
  end

  defp safe_atom(_), do: nil

  defp to_commodity_atom(s) when is_binary(s) do
    safe_atom(s) || :unknown
  end

  defp facility_crew_roles(:station),
    do: [:engineer, :engineer, :medic, :trader, :general, :general]

  defp facility_crew_roles(:outpost), do: [:engineer, :general, :general]
  defp facility_crew_roles(_), do: [:engineer, :general]

  # Starter reserves by facility type — mirrors the private defaults
  # inside DemandAnalyzer (which uses them for mid-sim construction).
  # Duplicated here rather than making them public because the
  # semantics are "initial inventory for a brand-new facility" which
  # is an admin concern, not a demand-analysis concern.
  defp initial_reserves_for(:refinery), do: %{fuel: 500, ore: 500, ice: 500}
  defp initial_reserves_for(:factory), do: %{fuel: 300, metals: 500, polymers: 300}
  defp initial_reserves_for(:farm), do: %{fuel: 200, water: 1000}
  defp initial_reserves_for(:mining_rig), do: %{fuel: 500}
  defp initial_reserves_for(:station), do: %{fuel: 1000, food: 500}
  defp initial_reserves_for(_), do: %{fuel: 300}

  defp default_prices do
    Map.new(Commodities.all(), fn c ->
      {to_string(c), Commodities.base_price(c)}
    end)
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  defp stringify_keys(other), do: other

  defp default_system_id(location_row) do
    # Best-effort — for v1 we pin to Sol if we can't determine from the
    # location's body. Spawner does something similar and tolerates
    # mis-assignment (spatial gets refreshed via the Registry).
    location_row
    |> Repo.preload(celestial_body: :star_system)
    |> case do
      %{celestial_body: %{star_system: %{name: name}}} -> "system-" <> slugify(name)
      _ -> "system-sol"
    end
  rescue
    _ -> "system-sol"
  end
end
