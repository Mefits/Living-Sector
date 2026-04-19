defmodule Simulator.PersistenceManager do
  @moduledoc """
  Periodically flushes dirty agent state to the database.

  Agents mark themselves as dirty when meaningful state changes occur
  (trades, arrivals, price shifts, need thresholds). The PersistenceManager
  sweeps on a configurable interval and batch-writes all dirty agents in
  a single transaction.

  ## How It Works

  1. Agents call `mark_dirty/3` with their type, DB id, and a persist function
  2. The manager accumulates these in an ETS table for O(1) dedup
  3. Every `sweep_interval_ms` (default 5s), the manager flushes all dirty
     entries by calling each agent's persist function inside a transaction
  4. The tick coordinator's current tick is also persisted each sweep

  ## Critical vs Batched Writes

  Most state persists on the sweep interval. For critical events (trades,
  credit transfers), agents can call `persist_now/3` for immediate write.
  """

  use GenServer

  require Logger

  @sweep_interval_ms 5_000
  @table __MODULE__

  # --- Public API ---

  @doc """
  Starts the persistence manager.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Marks an agent as dirty. The `persist_fn` is a zero-arity function that
  performs the actual DB write when called during the next sweep.

  If the same `{agent_type, db_id}` is marked dirty multiple times between
  sweeps, only the latest `persist_fn` is kept.

  ## Examples

      PersistenceManager.mark_dirty(:market, market_db_id, fn ->
        Repo.update!(Market.changeset(record, changes))
      end)
  """
  @spec mark_dirty(atom(), integer(), (-> any())) :: :ok
  def mark_dirty(agent_type, db_id, persist_fn) when is_function(persist_fn, 0) do
    :ets.insert(@table, {{agent_type, db_id}, persist_fn})
    :ok
  end

  @doc """
  Immediately persists a single write. Use for critical events like
  trade execution or credit transfers that must not be lost.
  """
  @spec persist_now((-> any())) :: any()
  def persist_now(persist_fn) when is_function(persist_fn, 0) do
    persist_fn.()
  end

  @doc """
  Forces an immediate flush of all dirty agents. Useful for graceful
  shutdown or testing.
  """
  @spec flush() :: :ok
  def flush do
    GenServer.call(__MODULE__, :flush, 30_000)
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(opts) do
    table = :ets.new(@table, [:named_table, :set, :public, write_concurrency: true])
    interval = Keyword.get(opts, :sweep_interval_ms, @sweep_interval_ms)

    schedule_sweep(interval)

    {:ok, %{table: table, sweep_interval_ms: interval}}
  end

  @impl true
  def handle_call(:flush, _from, state) do
    do_flush(state.table)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:sweep, state) do
    do_flush(state.table)
    schedule_sweep(state.sweep_interval_ms)
    {:noreply, state}
  end

  # --- Private ---

  defp do_flush(table) do
    entries = :ets.tab2list(table)

    if entries != [] do
      :ets.delete_all_objects(table)

      start = System.monotonic_time(:microsecond)
      run_persist_batch(entries)
      duration = System.monotonic_time(:microsecond) - start
      Simulator.Metrics.record_flush_duration(duration)
      persist_tick()
    end

    length(entries)
  end

  defp run_persist_batch(entries) do
    Simulator.Repo.transaction(fn ->
      Enum.each(entries, &safe_persist/1)
    end)
  end

  defp safe_persist({_key, persist_fn}) do
    persist_fn.()
  rescue
    e ->
      Logger.error("PersistenceManager: failed to persist: #{Exception.message(e)}")
  end

  defp persist_tick do
    tick =
      try do
        Simulator.TickCoordinator.get_tick()
      catch
        :exit, _ -> 0
      end

    Simulator.Repo.insert(
      Simulator.Schemas.SimulationState.changeset(
        %Simulator.Schemas.SimulationState{key: "tick_coordinator"},
        %{value: %{"current_tick" => tick}}
      ),
      on_conflict: {:replace, [:value, :updated_at]},
      conflict_target: :key
    )
  rescue
    _ -> :ok
  end

  defp schedule_sweep(interval) do
    Process.send_after(self(), :sweep, interval)
  end
end
