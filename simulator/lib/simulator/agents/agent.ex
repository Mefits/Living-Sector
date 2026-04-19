defmodule Simulator.Agents.Agent do
  @moduledoc """
  Common behaviour for all simulation agents.

  Every entity in the simulation that "thinks" is an agent — a GenServer
  process that holds state, receives tick messages, makes decisions, and
  emits actions. This module defines the contract every agent implements
  and provides a `__using__` macro that sets up GenServer boilerplate,
  Registry registration, and tick dispatch.

  ## Usage

      defmodule Simulator.Agents.MarketAgent do
        use Simulator.Agents.Agent

        @impl Simulator.Agents.Agent
        def init_agent(config) do
          {:ok, %{prices: config.initial_prices}}
        end

        @impl Simulator.Agents.Agent
        def handle_tick(tick, state) do
          # Recalculate prices, match orders, etc.
          {:ok, state}
        end
      end

  ## Lifecycle

      spawn → init_agent → loop(receive tick → handle_tick → decide) → terminate

  Every agent registers itself with `Simulator.AgentRegistry` under two keys:

    * `{:agent, agent_id}` — for direct lookup by ID
    * `:tick_subscribers` — so the `TickCoordinator` can fan out ticks

  ## Persistence

  Agents integrate with `Simulator.PersistenceManager` for database persistence.
  The `__using__` macro injects helper functions:

    * `mark_dirty/1` — mark the agent for persistence on the next sweep
    * `persist_now!/1` — immediately write to DB (for critical events)

  Agents store their DB record ID in `state.__db_id__` and their persist
  function is provided by implementing `persist_state/1` (optional callback).

  ## Callbacks

    * `init_agent/1` — initialize agent state from a config map
    * `handle_tick/2` — called every simulation tick with the tick number and current state
    * `handle_event/2` — handle an arbitrary event from another agent or the system
    * `decide/1` — evaluate state and return a list of actions to take (called by handle_tick)
    * `persist_state/1` — (optional) persist agent state to DB, called by PersistenceManager
  """

  @type action :: term()

  @doc """
  Initialize agent state from a configuration map.

  Called once when the agent process starts. The config map typically
  contains the agent's ID, initial parameters, and any seed data.
  """
  @callback init_agent(config :: map()) :: {:ok, state :: map()}

  @doc """
  Handle a simulation tick.

  Called every tick by the coordinator. The agent should update its state,
  make decisions, and emit any actions or events. Return the updated state.
  """
  @callback handle_tick(tick :: non_neg_integer(), state :: map()) :: {:ok, state :: map()}

  @doc """
  Handle an event from another agent or the system.

  Events are arbitrary terms — the agent decides which to act on.
  """
  @callback handle_event(event :: term(), state :: map()) :: {:ok, state :: map()}

  @doc """
  Evaluate the current state and return a list of actions to take.

  Actions are agent-type-specific terms that the agent's `handle_tick/2`
  can execute. Separating decision from execution makes agent logic
  testable as pure functions.
  """
  @callback decide(state :: map()) :: {[action()], state :: map()}

  @doc """
  Persist agent state to the database.

  Called by the `PersistenceManager` during sweep or immediately via
  `persist_now!/1`. Receives the full agent state and should write
  relevant fields to the agent's Ecto schema. Optional — agents that
  don't implement this are not persisted.
  """
  @callback persist_state(state :: map()) :: :ok

  @doc """
  Returns the agent's type atom (:ship, :facility, :market, etc.).

  Compile-time — implementations are typically a single-line
  function clause. Used by the `__using__` macro to populate the
  Registry value at registration time, so callers like
  `Simulator.Metrics` can read type via a pure ETS match spec
  instead of a sync `GenServer.call`.
  """
  @callback agent_type() :: atom()

  @doc """
  Returns the public projection of the agent's state for external
  consumers (`/api/report`, dashboard, etc.). Written to
  `Simulator.AgentSnapshots` once per tick so HTTP handlers never
  have to do a sync call.

  Default implementation strips internal bookkeeping (`__agent_id__`,
  `__db_id__`, `__agent_type__`) and tags the snapshot with `:id` so
  it's stable for external consumers. Agents may override to drop
  expensive fields (behavior-tree state, rolling caches) that
  shouldn't ride on every report.
  """
  @callback public_snapshot(state :: map()) :: map()

  @optional_callbacks [persist_state: 1]

  @doc false
  defmacro __using__(_opts) do
    quote do
      @behaviour Simulator.Agents.Agent

      use GenServer

      @registry Simulator.AgentRegistry

      @doc """
      Starts this agent as a linked process under a supervisor.

      Expects a config map with at least an `:id` key.
      """
      def start_link(config) do
        GenServer.start_link(__MODULE__, config)
      end

      @impl GenServer
      def init(config) do
        agent_id = Map.fetch!(config, :id)

        # Trap exits so `terminate/2` runs on supervisor-initiated
        # shutdown — we rely on it to remove this agent's snapshot
        # from the AgentSnapshots ETS cache. Without trap_exit, an
        # :EXIT {:shutdown} just kills the process silently and the
        # snapshot is left orphaned.
        Process.flag(:trap_exit, true)

        # Store type in the Registry value slot so consumers like
        # Metrics can read it via a single match-spec scan instead of
        # 250 sync GenServer.call(pid, :get_state) fan-outs. The type
        # comes from the compile-time agent_type/0 callback; init_agent
        # still sets :__agent_type__ in state for callers holding the
        # state map directly.
        Registry.register(@registry, {:agent, agent_id}, %{type: agent_type()})

        # Register for tick broadcasts
        Registry.register(@registry, :tick_subscribers, agent_id)

        {:ok, state} = init_agent(config)
        state = Map.put(state, :__agent_id__, agent_id)

        # Seed the AgentSnapshots cache so /api/report returns this
        # agent on the very first call, even before the first tick
        # fires.
        publish_snapshot(state)

        {:ok, state}
      end

      @impl GenServer
      def handle_info({:tick, tick}, state) do
        agent_id = Map.get(state, :__agent_id__, "")

        if Simulator.Spatial.ChunkManager.should_tick?(agent_id, tick) do
          case handle_tick(tick, state) do
            {:ok, new_state} ->
              publish_snapshot(new_state)
              {:noreply, new_state}
          end
        else
          {:noreply, state}
        end
      end

      def handle_info({event_name, _payload} = event, state) when is_atom(event_name) do
        case handle_event(event, state) do
          {:ok, new_state} ->
            # Events can mutate state (passengers arrive, food
            # availability changes, etc.). Refresh the snapshot so
            # readers see the new state without waiting for the
            # next tick.
            publish_snapshot(new_state)
            {:noreply, new_state}
        end
      end

      @impl GenServer
      def terminate(_reason, state) do
        # Clean up the snapshot row on graceful shutdown (supervisor
        # terminate_child, admin destroy, etc.). On brutal kill the
        # row lingers — minor — and would get replaced if a new
        # agent with the same id later takes over.
        case state do
          %{:__agent_id__ => agent_id} when is_binary(agent_id) ->
            Simulator.AgentSnapshots.delete(agent_type(), agent_id)

          _ ->
            :ok
        end

        :ok
      end

      # --- Snapshot helpers ---

      defp publish_snapshot(state) do
        case state do
          %{:__agent_id__ => agent_id} when is_binary(agent_id) ->
            Simulator.AgentSnapshots.put(
              agent_type(),
              agent_id,
              public_snapshot(state)
            )

          _ ->
            :ok
        end
      end

      # --- Persistence helpers ---

      @doc """
      Marks this agent as dirty for the next persistence sweep.

      The agent must have `__db_id__` and `__agent_type__` in its state
      (set during init) and implement `persist_state/1`.
      """
      def mark_dirty(state) do
        mod = __MODULE__
        db_id = Map.get(state, :__db_id__)
        agent_type = Map.get(state, :__agent_type__)
        persistable? = db_id && agent_type && function_exported?(mod, :persist_state, 1)

        if persistable? do
          captured_state = state

          Simulator.PersistenceManager.mark_dirty(agent_type, db_id, fn ->
            apply(mod, :persist_state, [captured_state])
          end)
        end

        state
      end

      @doc """
      Immediately persists the agent state to the database.
      Use for critical events (trades, credit transfers).
      """
      def persist_now!(state) do
        mod = __MODULE__

        if function_exported?(mod, :persist_state, 1) do
          Simulator.PersistenceManager.persist_now(fn ->
            apply(mod, :persist_state, [state])
          end)
        end

        state
      end

      # Default callback implementations — agents can override these

      @impl Simulator.Agents.Agent
      def handle_event(_event, state), do: {:ok, state}

      @impl Simulator.Agents.Agent
      def decide(state), do: {[], state}

      @impl Simulator.Agents.Agent
      def public_snapshot(state) do
        # Default snapshot: strip internal bookkeeping but keep a
        # stable :id field for consumers. Individual agents may
        # override to trim behavior trees, rolling caches, etc.
        state
        |> Map.drop([:__agent_id__, :__db_id__, :__agent_type__])
        |> Map.put(:id, Map.get(state, :__agent_id__))
      end

      defoverridable handle_event: 2, decide: 1, public_snapshot: 1, terminate: 2
    end
  end

  # --- Utility functions for working with agents ---

  @doc """
  Looks up an agent's PID by its ID via the agent registry.

  Returns `{:ok, pid}` if the agent is registered, or `:error` if not found.
  """
  @spec whereis(String.t()) :: {:ok, pid()} | :error
  def whereis(agent_id) do
    case Registry.lookup(Simulator.AgentRegistry, {:agent, agent_id}) do
      [{pid, _}] -> {:ok, pid}
      [] -> :error
    end
  end
end
