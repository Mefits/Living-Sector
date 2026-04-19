defmodule Simulator.Metrics do
  @moduledoc """
  Collects and exposes simulation performance metrics.

  Samples agent health periodically and tracks tick performance. Designed
  for early detection of scaling issues: slow ticks, message queue buildup,
  memory growth, and agent stalls.

  ## Metrics Collected

  **Tick Performance:**
    * `tick_duration_us` — microseconds to dispatch one tick to all agents
    * `ticks_per_second` — actual throughput vs configured interval
    * `tick_lag_ms` — how far behind the coordinator is from target pace

  **Agent Health:**
    * `agent_counts` — count of agents by type
    * `message_queue_depths` — per-agent-type max/avg message queue length
    * `memory_by_type` — total process memory by agent type
    * `stalled_agents` — agents with message queue > threshold

  **Persistence:**
    * `dirty_count` — entries waiting for next flush
    * `last_flush_duration_us` — how long the last persistence sweep took

  ## Usage

      Simulator.Metrics.snapshot()  # returns full metrics map
  """

  use GenServer

  require Logger

  @sample_interval_ms 5_000
  @stall_threshold 100

  # --- Public API ---

  @doc """
  Starts the metrics collector.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns a snapshot of all current metrics.
  """
  @spec snapshot() :: map()
  def snapshot do
    GenServer.call(__MODULE__, :snapshot)
  end

  @doc """
  Records a tick duration measurement (called by TickCoordinator).
  """
  @spec record_tick_duration(non_neg_integer()) :: :ok
  def record_tick_duration(duration_us) do
    GenServer.cast(__MODULE__, {:tick_duration, duration_us})
  end

  @doc """
  Records a persistence flush duration.
  """
  @spec record_flush_duration(non_neg_integer()) :: :ok
  def record_flush_duration(duration_us) do
    GenServer.cast(__MODULE__, {:flush_duration, duration_us})
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(_opts) do
    schedule_sample()

    state = %{
      # Tick metrics (rolling window of last 100)
      tick_durations: [],
      ticks_per_second: 0.0,
      last_tick_time: System.monotonic_time(:millisecond),
      tick_count_window: 0,

      # Agent metrics
      agent_counts: %{},
      message_queues: %{},
      memory_by_type: %{},
      stalled_agents: [],
      total_agent_count: 0,

      # Persistence metrics
      last_flush_duration_us: 0,
      dirty_count: 0,

      # Sampling
      last_sample_at: System.monotonic_time(:millisecond)
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    snapshot = %{
      tick: %{
        avg_duration_us: avg(state.tick_durations),
        max_duration_us: safe_max(state.tick_durations),
        min_duration_us: safe_min(state.tick_durations),
        p99_duration_us: percentile(state.tick_durations, 99),
        ticks_per_second: state.ticks_per_second,
        samples: length(state.tick_durations)
      },
      agents: %{
        counts: state.agent_counts,
        total: state.total_agent_count,
        message_queues: state.message_queues,
        memory_by_type: state.memory_by_type,
        stalled: state.stalled_agents
      },
      persistence: %{
        last_flush_duration_us: state.last_flush_duration_us,
        dirty_count: state.dirty_count
      }
    }

    {:reply, snapshot, state}
  end

  @impl true
  def handle_cast({:tick_duration, duration_us}, state) do
    now = System.monotonic_time(:millisecond)
    durations = Enum.take([duration_us | state.tick_durations], 100)

    # Calculate ticks/second over a rolling window
    elapsed = now - state.last_tick_time
    new_count = state.tick_count_window + 1

    {tps, last_time, count} =
      if elapsed >= 1000 do
        {new_count / (elapsed / 1000), now, 0}
      else
        {state.ticks_per_second, state.last_tick_time, new_count}
      end

    {:noreply,
     %{
       state
       | tick_durations: durations,
         ticks_per_second: Float.round(tps, 2),
         last_tick_time: last_time,
         tick_count_window: count
     }}
  end

  def handle_cast({:flush_duration, duration_us}, state) do
    {:noreply, %{state | last_flush_duration_us: duration_us}}
  end

  @impl true
  def handle_info(:sample, state) do
    state = sample_agents(state)
    state = sample_persistence(state)
    maybe_warn(state)
    schedule_sample()
    {:noreply, %{state | last_sample_at: System.monotonic_time(:millisecond)}}
  end

  # --- Sampling ---

  defp sample_agents(state) do
    agents = list_all_agents()

    counts = count_by_type(agents)
    queues = queue_stats_by_type(agents)
    memory = memory_by_type(agents)
    stalled = find_stalled(agents)

    %{
      state
      | agent_counts: counts,
        message_queues: queues,
        memory_by_type: memory,
        stalled_agents: stalled,
        total_agent_count: length(agents)
    }
  end

  defp sample_persistence(state) do
    dirty =
      try do
        :ets.info(Simulator.PersistenceManager, :size) || 0
      catch
        _, _ -> 0
      end

    %{state | dirty_count: dirty}
  end

  defp list_all_agents do
    # Pull {id, pid, value} from the Registry in one match-spec scan.
    # Value is `%{type: atom()}` — populated at registration time
    # from each agent module's `agent_type/0` callback. Avoids any
    # per-agent GenServer.call, which could starve the Metrics
    # mailbox under tick burst and cause /api/report to time out.
    Registry.select(Simulator.AgentRegistry, [
      {{{:agent, :"$1"}, :"$2", :"$3"}, [], [{{:"$1", :"$2", :"$3"}}]}
    ])
    |> Enum.flat_map(fn {agent_id, pid, value} ->
      if Process.alive?(pid) do
        info = Process.info(pid, [:message_queue_len, :memory])

        [
          %{
            id: agent_id,
            pid: pid,
            type: type_from_value(value),
            queue_len: get_in(info, [:message_queue_len]) || 0,
            memory: get_in(info, [:memory]) || 0
          }
        ]
      else
        []
      end
    end)
  end

  defp type_from_value(%{type: type}) when is_atom(type), do: type
  defp type_from_value(_), do: :unknown

  defp count_by_type(agents) do
    Enum.frequencies_by(agents, & &1.type)
  end

  defp queue_stats_by_type(agents) do
    agents
    |> Enum.group_by(& &1.type)
    |> Map.new(fn {type, group} ->
      queues = Enum.map(group, & &1.queue_len)

      {type,
       %{
         max: safe_max(queues),
         avg: avg(queues),
         total: Enum.sum(queues)
       }}
    end)
  end

  defp memory_by_type(agents) do
    agents
    |> Enum.group_by(& &1.type)
    |> Map.new(fn {type, group} ->
      total = Enum.sum(Enum.map(group, & &1.memory))
      {type, %{total_bytes: total, avg_bytes: div(total, max(length(group), 1))}}
    end)
  end

  defp find_stalled(agents) do
    agents
    |> Enum.filter(&(&1.queue_len > @stall_threshold))
    |> Enum.map(&%{id: &1.id, type: &1.type, queue_len: &1.queue_len})
  end

  defp maybe_warn(state) do
    if state.stalled_agents != [] do
      Logger.warning(
        "Metrics: #{length(state.stalled_agents)} stalled agents (queue > #{@stall_threshold}): " <>
          inspect(Enum.map(state.stalled_agents, & &1.id))
      )
    end

    avg_tick = avg(state.tick_durations)

    if avg_tick > 50_000 do
      Logger.warning(
        "Metrics: avg tick duration #{round(avg_tick / 1000)}ms — may need optimization"
      )
    end
  end

  # --- Math helpers ---

  defp avg([]), do: 0.0
  defp avg(list), do: Enum.sum(list) / length(list)

  defp safe_max([]), do: 0
  defp safe_max(list), do: Enum.max(list)

  defp safe_min([]), do: 0
  defp safe_min(list), do: Enum.min(list)

  defp percentile([], _p), do: 0

  defp percentile(list, p) do
    sorted = Enum.sort(list)
    idx = max(round(length(sorted) * p / 100) - 1, 0)
    Enum.at(sorted, idx, 0)
  end

  defp schedule_sample do
    Process.send_after(self(), :sample, @sample_interval_ms)
  end
end
