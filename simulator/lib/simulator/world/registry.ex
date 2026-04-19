defmodule Simulator.World.Registry do
  @moduledoc """
  Central registry of known star systems, locations, and travel routes.

  Populated from Postgres at startup. Provides lookups that replace
  hardcoded system IDs, location-to-body maps, and travel routes
  scattered across the codebase.

  Uses ETS for O(1) reads on the hot path (travel time resolution,
  position tracking, dashboard rendering).
  """

  use GenServer

  require Logger

  @ets_table :world_registry

  # --- Public API (ETS reads, no GenServer call) ---

  @doc """
  Returns all known system IDs.
  """
  @spec system_ids() :: [String.t()]
  def system_ids do
    case :ets.lookup(@ets_table, :system_ids) do
      [{_, ids}] -> ids
      [] -> []
    end
  end

  @doc """
  Returns the universe offset for a system.
  """
  @spec universe_offset(String.t()) :: {float(), float()}
  def universe_offset(system_id) do
    case :ets.lookup(@ets_table, {:system_offset, system_id}) do
      [{_, offset}] -> offset
      [] -> {0.0, 0.0}
    end
  end

  @doc """
  Returns all system offsets as a map.
  """
  @spec all_system_offsets() :: %{String.t() => {float(), float()}}
  def all_system_offsets do
    case :ets.lookup(@ets_table, :system_offsets) do
      [{_, offsets}] -> offsets
      [] -> %{}
    end
  end

  @doc """
  Returns the body_id for a location name (e.g., "earth-station" → "earth").
  Uses exact lookup against location → body mappings loaded from DB.
  """
  @spec body_id_for_location(String.t()) :: String.t() | nil
  def body_id_for_location(location) do
    case :ets.lookup(@ets_table, :location_body_map) do
      [{_, map}] -> Map.get(map, location)
      [] -> nil
    end
  end

  @doc """
  Returns the travel time between two locations, or nil if unknown.
  """
  @spec travel_time(String.t(), String.t()) :: non_neg_integer() | nil
  def travel_time(from, to) do
    case :ets.lookup(@ets_table, {:route, from, to}) do
      [{_, ticks}] -> ticks
      [] -> nil
    end
  end

  @doc """
  Returns all locations reachable from a given location.
  """
  @spec reachable_from(String.t()) :: [String.t()]
  def reachable_from(location) do
    case :ets.lookup(@ets_table, {:reachable, location}) do
      [{_, destinations}] -> destinations
      [] -> []
    end
  end

  @doc """
  Returns system metadata (name, star color, etc.) for all systems.
  """
  @spec all_systems() :: %{String.t() => map()}
  def all_systems do
    case :ets.lookup(@ets_table, :systems_meta) do
      [{_, meta}] -> meta
      [] -> %{}
    end
  end

  # --- GenServer ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Reloads all data from Postgres. Call after seeding.
  """
  def reload do
    GenServer.call(__MODULE__, :reload)
  end

  @impl true
  def init(_opts) do
    table =
      if :ets.whereis(@ets_table) == :undefined do
        :ets.new(@ets_table, [:named_table, :set, :public, read_concurrency: true])
      else
        @ets_table
      end

    load_from_db()

    {:ok, %{table: table}}
  end

  @impl true
  def handle_call(:reload, _from, state) do
    load_from_db()
    {:reply, :ok, state}
  end

  # --- Private: Load from DB ---

  defp load_from_db do
    alias Simulator.Repo
    alias Simulator.Schemas.{CelestialBody, StarSystem}

    # Systems
    systems = Repo.all(StarSystem)

    system_ids =
      Enum.map(systems, fn s -> "system-#{String.downcase(String.replace(s.name, " ", "-"))}" end)

    :ets.insert(@ets_table, {:system_ids, system_ids})

    system_offsets =
      Map.new(systems, fn s ->
        id = "system-#{String.downcase(String.replace(s.name, " ", "-"))}"
        {id, {s.universe_offset_x || 0.0, s.universe_offset_y || 0.0}}
      end)

    :ets.insert(@ets_table, {:system_offsets, system_offsets})

    for {id, offset} <- system_offsets do
      :ets.insert(@ets_table, {{:system_offset, id}, offset})
    end

    # Systems metadata (for dashboard)
    systems_meta =
      Map.new(systems, fn s ->
        id = "system-#{String.downcase(String.replace(s.name, " ", "-"))}"
        {id, %{name: s.name, id: id}}
      end)

    :ets.insert(@ets_table, {:systems_meta, systems_meta})

    # Location → Body map (exact lookup from location names to body IDs)
    bodies = Repo.all(CelestialBody) |> Repo.preload(:locations)

    location_body_map =
      Enum.reduce(bodies, %{}, fn body, acc ->
        bid = body.body_id || String.downcase(body.name)

        Enum.reduce(body.locations, acc, fn location, inner_acc ->
          Map.put(inner_acc, location.name, bid)
        end)
      end)

    :ets.insert(@ets_table, {:location_body_map, location_body_map})

    # Travel routes from JSON world files (loaded into ETS)
    load_travel_routes()

    Logger.info(
      "WorldRegistry: loaded #{length(system_ids)} systems, #{length(bodies)} bodies, #{map_size(location_body_map)} location mappings"
    )
  end

  defp load_travel_routes do
    for world_file <- Path.wildcard("priv/data/worlds/*.json") do
      data = world_file |> File.read!() |> Jason.decode!()

      for route <- data["travel_routes"] || [] do
        from = route["from"]
        to = route["to"]
        distance = route["distance"]

        # Bidirectional
        :ets.insert(@ets_table, {{:route, from, to}, distance})
        :ets.insert(@ets_table, {{:route, to, from}, distance})
      end
    end

    # Build reachable_from index
    routes =
      :ets.match(@ets_table, {{:route, :"$1", :"$2"}, :"$3"})
      |> Enum.map(fn [from, to, _dist] -> {from, to} end)

    routes
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.each(fn {from, destinations} ->
      :ets.insert(@ets_table, {{:reachable, from}, Enum.uniq(destinations)})
    end)
  end
end
