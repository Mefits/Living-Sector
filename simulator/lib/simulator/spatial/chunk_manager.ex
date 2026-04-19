defmodule Simulator.Spatial.ChunkManager do
  @moduledoc """
  Manages a unified spatial chunk grid across the entire universe.

  One coordinate space, one quadtree, one chunk grid, one observer system.
  Star systems are just clusters of entities at different universe positions
  (Sol at origin, Alpha Centauri at ~20,5, etc.).

  ## Tick Gating

  `should_tick?/2` is the hot-path function called by every agent on every
  tick. It's a pure ETS read — O(1), no GenServer call. Agents where
  `rem(tick, divisor) == 0` process the tick; others skip.

  ## No Dormant State

  Even the farthest chunk gets `max_divisor` (default 50), meaning it
  still ticks once every 50 ticks. The world is always alive, just at
  lower resolution when nobody's watching.
  """

  use GenServer

  require Logger

  alias Simulator.Spatial.{Observer, Quadtree}

  @ets_divisors :chunk_divisors
  @ets_positions :agent_positions
  @ets_observers :chunk_observers
  @ets_chunk_grid :chunk_grid_data
  @default_chunk_size 10.0
  @default_bounds {-500.0, -500.0, 1000.0, 1000.0}
  @default_recalc_interval 10 * Simulator.Simulation.Config.tick_multiplier()

  # --- Public API (no GenServer call needed) ---

  @doc """
  Checks whether an agent should process this tick.

  Pure ETS read — O(1). Falls back to PriorityManager overrides first,
  then spatial chunk divisor. Unregistered agents always tick.
  """
  @spec should_tick?(String.t(), non_neg_integer()) :: boolean()
  def should_tick?(agent_id, tick) do
    case Simulator.Simulation.PriorityManager.get_override(agent_id) do
      :foreground ->
        true

      :dormant ->
        false

      nil ->
        case :ets.lookup(@ets_divisors, agent_id) do
          [{_, divisor}] -> rem(tick, divisor) == 0
          [] -> true
        end
    end
  end

  @doc """
  Returns the current tick divisor for an agent. 1 = every tick, 50 = every 50th.
  """
  @spec tick_divisor_for(String.t()) :: pos_integer()
  def tick_divisor_for(agent_id) do
    case :ets.lookup(@ets_divisors, agent_id) do
      [{_, divisor}] -> divisor
      [] -> 1
    end
  end

  # --- Public API (GenServer calls/casts) ---

  @doc """
  Starts the ChunkManager.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Registers an entity at universe coordinates.

  Options:
    * `:parent_id` — parent agent whose divisor this entity inherits (for crew)
    * `:body_id` — celestial body this entity is attached to (for bulk orbital updates)
  """
  @spec register_entity(String.t(), float(), float(), keyword()) :: :ok
  def register_entity(agent_id, x, y, opts \\ []) do
    GenServer.call(__MODULE__, {:register, agent_id, x, y, opts})
  end

  @doc """
  Updates an entity's position in universe coordinates. Non-blocking cast.
  """
  @spec update_position(String.t(), float(), float()) :: :ok
  def update_position(agent_id, x, y) do
    GenServer.cast(__MODULE__, {:update_position, agent_id, x, y})
  end

  @doc """
  Returns all tracked entity positions as a list of `{id, x, y}` tuples.
  Reads directly from ETS — no GenServer call.
  """
  @spec all_positions() :: [{String.t(), float(), float()}]
  def all_positions do
    :ets.tab2list(@ets_positions)
  end

  @doc """
  Returns a single entity's position as `{x, y}` or nil.
  Direct ETS read — no GenServer call.
  """
  @spec get_position(String.t()) :: {float(), float()} | nil
  def get_position(agent_id) do
    case :ets.lookup(@ets_positions, agent_id) do
      [{_, x, y}] -> {x, y}
      _ -> nil
    end
  end

  @doc """
  Removes an entity from tracking.
  """
  @spec unregister_entity(String.t()) :: :ok
  def unregister_entity(agent_id) do
    GenServer.cast(__MODULE__, {:unregister, agent_id})
  end

  @doc """
  Adds an observer that activates nearby chunks.
  """
  @spec add_observer(Observer.t()) :: :ok
  def add_observer(%Observer{} = observer) do
    GenServer.call(__MODULE__, {:add_observer, observer})
  end

  @doc """
  Updates an observer's position or radius.
  """
  @spec update_observer(String.t(), map()) :: :ok
  def update_observer(id, changes) do
    GenServer.call(__MODULE__, {:update_observer, id, changes})
  end

  @doc """
  Removes an observer.
  """
  @spec remove_observer(String.t()) :: :ok
  def remove_observer(id) do
    GenServer.call(__MODULE__, {:remove_observer, id})
  end

  @doc """
  Returns all observers. Pure ETS read — no GenServer call.
  """
  @spec list_observers() :: [Observer.t()]
  def list_observers do
    case :ets.whereis(@ets_observers) do
      :undefined -> []
      _ -> :ets.tab2list(@ets_observers) |> Enum.map(&elem(&1, 1))
    end
  end

  @doc """
  Returns the chunk grid with divisor values for dashboard visualization.
  Pure ETS read — no GenServer call.
  """
  @spec get_chunk_grid() :: map()
  def get_chunk_grid do
    case :ets.whereis(@ets_chunk_grid) do
      :undefined ->
        %{}

      _ ->
        case :ets.lookup(@ets_chunk_grid, :grid) do
          [{:grid, grid}] -> grid
          [] -> %{}
        end
    end
  end

  @doc """
  Forces a divisor recalculation. Useful for testing.
  """
  @spec recalculate() :: :ok
  def recalculate do
    GenServer.call(__MODULE__, :recalculate)
  end

  @doc """
  Resets all internal state. Used in tests to ensure clean isolation.
  """
  @spec reset() :: :ok
  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(opts) do
    ets_divisors =
      if :ets.whereis(@ets_divisors) == :undefined do
        :ets.new(@ets_divisors, [
          :named_table,
          :set,
          :public,
          read_concurrency: true,
          write_concurrency: true
        ])
      else
        @ets_divisors
      end

    ets_positions =
      if :ets.whereis(@ets_positions) == :undefined do
        :ets.new(@ets_positions, [
          :named_table,
          :set,
          :public,
          read_concurrency: true,
          write_concurrency: true
        ])
      else
        @ets_positions
      end

    if :ets.whereis(@ets_observers) == :undefined do
      :ets.new(@ets_observers, [
        :named_table,
        :set,
        :public,
        read_concurrency: true
      ])
    end

    if :ets.whereis(@ets_chunk_grid) == :undefined do
      :ets.new(@ets_chunk_grid, [
        :named_table,
        :set,
        :public,
        read_concurrency: true
      ])
    end

    Simulator.Events.subscribe("tick")

    bounds = Keyword.get(opts, :bounds, @default_bounds)
    chunk_size = Keyword.get(opts, :chunk_size, @default_chunk_size)

    state = %{
      quadtree: Quadtree.new(bounds),
      chunks: build_chunk_grid(bounds, chunk_size),
      chunk_divisors: %{},
      observers: [],
      config: %{
        chunk_size: chunk_size,
        bounds: bounds,
        falloff_scale: Keyword.get(opts, :falloff_scale, 150.0),
        gradient_power: Keyword.get(opts, :gradient_power, 1.5),
        max_divisor: Keyword.get(opts, :max_divisor, 50),
        recalc_interval: Keyword.get(opts, :recalc_interval, @default_recalc_interval)
      },
      parent_children: %{},
      body_entities: %{},
      ets_divisors: ets_divisors,
      ets_positions: ets_positions
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:register, agent_id, x, y, opts}, _from, state) do
    qt = Quadtree.insert(state.quadtree, {agent_id, x, y})
    chunk_key = position_to_chunk(x, y, state.config.chunk_size, state.config.bounds)

    chunks =
      Map.update(state.chunks, chunk_key, MapSet.new([agent_id]), &MapSet.put(&1, agent_id))

    state = %{state | quadtree: qt, chunks: chunks}

    # Track parent-child relationships (crew → ship)
    state =
      case Keyword.get(opts, :parent_id) do
        nil ->
          state

        parent_id ->
          children = Map.get(state.parent_children, parent_id, [])

          %{
            state
            | parent_children: Map.put(state.parent_children, parent_id, [agent_id | children])
          }
      end

    # Track body attachments (facility → body for orbital updates)
    state =
      case Keyword.get(opts, :body_id) do
        nil ->
          state

        body_id ->
          entities = Map.get(state.body_entities, body_id, [])
          %{state | body_entities: Map.put(state.body_entities, body_id, [agent_id | entities])}
      end

    # Update ETS
    :ets.insert(@ets_positions, {agent_id, x, y})
    :ets.insert(@ets_divisors, {agent_id, 1})

    {:reply, :ok, state}
  end

  def handle_call({:add_observer, observer}, _from, state) do
    state = %{state | observers: [observer | state.observers]}
    state = recalculate_all_divisors(state)
    broadcast_chunk_state(state)
    {:reply, :ok, state}
  end

  def handle_call({:update_observer, id, changes}, _from, state) do
    observers =
      Enum.map(state.observers, fn obs ->
        if obs.id == id, do: struct(obs, changes), else: obs
      end)

    state = %{state | observers: observers}
    state = recalculate_all_divisors(state)
    broadcast_chunk_state(state)
    {:reply, :ok, state}
  end

  def handle_call({:remove_observer, id}, _from, state) do
    state = %{state | observers: Enum.reject(state.observers, &(&1.id == id))}
    state = recalculate_all_divisors(state)
    broadcast_chunk_state(state)
    {:reply, :ok, state}
  end

  def handle_call(:recalculate, _from, state) do
    state = recalculate_all_divisors(state)
    {:reply, :ok, state}
  end

  def handle_call(:reset, _from, _state) do
    :ets.delete_all_objects(@ets_divisors)
    :ets.delete_all_objects(@ets_positions)
    :ets.delete_all_objects(@ets_observers)
    :ets.delete_all_objects(@ets_chunk_grid)

    bounds = @default_bounds
    chunk_size = @default_chunk_size

    fresh_state = %{
      quadtree: Quadtree.new(bounds),
      chunks: build_chunk_grid(bounds, chunk_size),
      chunk_divisors: %{},
      observers: [],
      config: %{
        chunk_size: chunk_size,
        bounds: bounds,
        falloff_scale: 15.0,
        gradient_power: 1.8,
        max_divisor: 50,
        recalc_interval: @default_recalc_interval
      },
      parent_children: %{},
      body_entities: %{},
      ets_divisors: @ets_divisors,
      ets_positions: @ets_positions
    }

    {:reply, :ok, fresh_state}
  end

  @impl true
  def handle_cast({:update_position, agent_id, x, y}, state) do
    qt = Quadtree.update(state.quadtree, agent_id, {x, y})

    old_chunk = find_entity_chunk(agent_id, state.chunks)
    new_chunk = position_to_chunk(x, y, state.config.chunk_size, state.config.bounds)

    chunks =
      if old_chunk != new_chunk do
        chunks =
          if old_chunk do
            Map.update!(state.chunks, old_chunk, &MapSet.delete(&1, agent_id))
          else
            state.chunks
          end

        Map.update(chunks, new_chunk, MapSet.new([agent_id]), &MapSet.put(&1, agent_id))
      else
        state.chunks
      end

    state = %{state | quadtree: qt, chunks: chunks}

    :ets.insert(@ets_positions, {agent_id, x, y})

    {:noreply, state}
  end

  def handle_cast({:unregister, agent_id}, state) do
    qt = Quadtree.remove(state.quadtree, agent_id)
    old_chunk = find_entity_chunk(agent_id, state.chunks)

    chunks =
      if old_chunk do
        Map.update!(state.chunks, old_chunk, &MapSet.delete(&1, agent_id))
      else
        state.chunks
      end

    # Clean up parent_children: remove as parent, and remove from any parent's child list
    parent_children =
      state.parent_children
      |> Map.delete(agent_id)
      |> Map.new(fn {parent, children} -> {parent, List.delete(children, agent_id)} end)

    state = %{state | quadtree: qt, chunks: chunks, parent_children: parent_children}
    :ets.delete(@ets_divisors, agent_id)
    :ets.delete(@ets_positions, agent_id)

    {:noreply, state}
  end

  @impl true
  def handle_info({:tick, %{tick: tick}}, state) do
    if rem(tick, state.config.recalc_interval) == 0 do
      state = recalculate_all_divisors(state)
      broadcast_chunk_state(state)
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # --- Private: Chunk Grid ---

  defp build_chunk_grid({_bx, _by, bw, bh}, chunk_size) do
    cols = round(bw / chunk_size)
    rows = round(bh / chunk_size)

    for col <- 0..(cols - 1), row <- 0..(rows - 1), into: %{} do
      {{col, row}, MapSet.new()}
    end
  end

  # --- Private: Divisor Calculation ---

  defp recalculate_all_divisors(state) do
    {bx, by, _bw, _bh} = state.config.bounds
    chunk_size = state.config.chunk_size

    chunk_divisors =
      Map.new(state.chunks, fn {{col, row}, entity_ids} ->
        cx = bx + (col + 0.5) * chunk_size
        cy = by + (row + 0.5) * chunk_size
        divisor = compute_divisor({cx, cy}, state.observers, state.config)

        for entity_id <- entity_ids do
          :ets.insert(@ets_divisors, {entity_id, divisor})

          for child_id <- Map.get(state.parent_children, entity_id, []) do
            :ets.insert(@ets_divisors, {child_id, divisor})
          end
        end

        {{col, row}, divisor}
      end)

    %{state | chunk_divisors: chunk_divisors}
  end

  defp compute_divisor(_center, [], config), do: config.max_divisor

  defp compute_divisor({cx, cy}, observers, config) do
    min_effective_distance =
      observers
      |> Enum.map(fn obs ->
        dist = :math.sqrt(:math.pow(cx - obs.x, 2) + :math.pow(cy - obs.y, 2))
        max(dist - obs.radius, 0.0)
      end)
      |> Enum.min()

    raw =
      1 +
        :math.pow(min_effective_distance / config.falloff_scale, config.gradient_power) *
          (config.max_divisor - 1)

    raw |> round() |> max(1) |> min(config.max_divisor)
  end

  # --- Private: Chunk Helpers ---

  defp position_to_chunk(x, y, chunk_size, {bx, by, bw, bh}) do
    max_col = round(bw / chunk_size) - 1
    max_row = round(bh / chunk_size) - 1
    col = floor((x - bx) / chunk_size) |> max(0) |> min(max_col)
    row = floor((y - by) / chunk_size) |> max(0) |> min(max_row)
    {col, row}
  end

  defp find_entity_chunk(agent_id, chunks) do
    Enum.find_value(chunks, fn {key, entity_ids} ->
      if MapSet.member?(entity_ids, agent_id), do: key
    end)
  end

  defp broadcast_chunk_state(state) do
    sync_ets_reads(state)

    Simulator.Events.broadcast("chunks", :chunk_update, %{
      chunk_divisors: state.chunk_divisors,
      observers: state.observers
    })
  end

  defp sync_ets_reads(state) do
    # Write observers to ETS for lock-free reads
    :ets.delete_all_objects(@ets_observers)

    for obs <- state.observers do
      :ets.insert(@ets_observers, {obs.id, obs})
    end

    # Write chunk grid to ETS for lock-free reads
    :ets.insert(@ets_chunk_grid, {:grid, state.chunk_divisors})
  end
end
