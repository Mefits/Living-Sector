defmodule Simulator.TickCoordinator do
  @moduledoc """
  Drives the simulation clock by broadcasting periodic `:tick` messages
  to all registered agents.

  The simulation advances through a hybrid model: agents react to events
  continuously, but a periodic sync tick reconciles macro state (market prices,
  population growth, resource extraction).

  The coordinator starts in a **paused** state. Call `start/0` to begin
  ticking (typically done by `Simulator.Simulation.Spawner` after the world
  is seeded).

  ## Tick Dispatch

  On each tick, the coordinator dispatches `{:tick, tick_number}` to every
  process registered under `{Simulator.AgentRegistry, :tick_subscribers}`
  via `Registry.dispatch/3`, and broadcasts to the `"tick"` PubSub topic
  for UI consumers.
  """

  use GenServer

  require Logger

  @registry Simulator.AgentRegistry
  @default_interval_ms Simulator.Simulation.Config.tick_interval_ms()
  # Broadcast ship positions every N ticks (1 = every tick = 4/sec at 1x)
  @position_broadcast_interval 1
  # Ship state deltas (location/transit/goal/docked_at) broadcast every N ticks
  # 8 ticks = ~1 sec at 8 tps. Empty broadcast skipped (no change since last flush).
  @ship_states_interval 8
  # Market snapshot broadcast — full current state of all markets every N ticks.
  # 16 ticks = ~2 sec at 8 tps. Not a delta — markets change every tick so deltas
  # would nearly always include everything. Clients overwrite their market map.
  @market_states_interval 16

  # --- Public API ---

  @doc """
  Starts the tick coordinator as a named process.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Begins ticking. The coordinator will advance one tick every `tick_interval_ms`
  milliseconds until paused or stopped.
  """
  @spec start() :: :ok
  def start do
    GenServer.call(__MODULE__, :start)
  end

  @doc """
  Pauses the tick loop. The current tick number is preserved and ticking
  resumes from where it left off when `resume/0` is called.
  """
  @spec pause() :: :ok
  def pause do
    GenServer.call(__MODULE__, :pause)
  end

  @doc """
  Resumes ticking after a pause.
  """
  @spec resume() :: :ok
  def resume do
    GenServer.call(__MODULE__, :resume)
  end

  @doc """
  Stops the tick loop and resets the tick counter to 0.
  """
  @spec stop() :: :ok
  def stop do
    GenServer.call(__MODULE__, :stop)
  end

  @doc """
  Sets the tick interval in milliseconds. Lower values = faster simulation.

  ## Examples

      Simulator.TickCoordinator.set_speed(500)  # 2 ticks per second
      Simulator.TickCoordinator.set_speed(100)  # 10 ticks per second
  """
  @spec set_speed(pos_integer()) :: :ok
  def set_speed(interval_ms) when is_integer(interval_ms) and interval_ms > 0 do
    GenServer.call(__MODULE__, {:set_speed, interval_ms})
  end

  @doc """
  Returns the current tick number.
  """
  @spec get_tick() :: non_neg_integer()
  def get_tick do
    GenServer.call(__MODULE__, :get_tick)
  end

  @doc """
  Returns the current tick interval in milliseconds.
  """
  @spec get_speed() :: pos_integer()
  def get_speed do
    GenServer.call(__MODULE__, :get_speed)
  end

  @doc """
  Returns whether the coordinator is currently ticking.
  """
  @spec running?() :: boolean()
  def running? do
    GenServer.call(__MODULE__, :running?)
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(opts) do
    restored_tick = restore_tick_from_db()

    if restored_tick > 0 do
      Logger.info("TickCoordinator: restored tick #{restored_tick} from DB")
    end

    state = %{
      current_tick: restored_tick,
      tick_interval_ms: Keyword.get(opts, :tick_interval_ms, @default_interval_ms),
      running: false,
      timer_ref: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:start, _from, state) do
    # Preserve restored tick — only reset to 0 if no tick was restored
    state = %{state | running: true}
    state = schedule_tick(state)
    {:reply, :ok, state}
  end

  def handle_call(:pause, _from, state) do
    state = cancel_timer(state)
    {:reply, :ok, %{state | running: false}}
  end

  def handle_call(:resume, _from, %{running: false, current_tick: tick} = state) when tick > 0 do
    state = %{state | running: true}
    state = schedule_tick(state)
    {:reply, :ok, state}
  end

  def handle_call(:resume, _from, state) do
    {:reply, :ok, state}
  end

  def handle_call(:stop, _from, state) do
    state = cancel_timer(state)
    {:reply, :ok, %{state | running: false, current_tick: 0}}
  end

  def handle_call({:set_speed, interval_ms}, _from, state) do
    state = %{state | tick_interval_ms: interval_ms}

    state =
      if state.running do
        state |> cancel_timer() |> schedule_tick()
      else
        state
      end

    {:reply, :ok, state}
  end

  def handle_call(:get_tick, _from, state) do
    {:reply, state.current_tick, state}
  end

  def handle_call(:get_speed, _from, state) do
    {:reply, state.tick_interval_ms, state}
  end

  def handle_call(:running?, _from, state) do
    {:reply, state.running, state}
  end

  @impl true
  def handle_info(:advance, %{running: true} = state) do
    tick = state.current_tick + 1

    # Measure tick dispatch duration
    start = System.monotonic_time(:microsecond)

    # Fan out tick to all registered agents
    Registry.dispatch(@registry, :tick_subscribers, fn entries ->
      for {pid, _} <- entries, do: send(pid, {:tick, tick})
    end)

    duration = System.monotonic_time(:microsecond) - start
    Simulator.Metrics.record_tick_duration(duration)

    # Broadcast to PubSub for UI consumers
    Simulator.Events.broadcast("tick", :tick, %{tick: tick})

    # Broadcast bulk ship positions every tick for game clients
    # ETS read is O(n) but fast — no GenServer bottleneck
    if rem(tick, @position_broadcast_interval) == 0 do
      positions =
        Simulator.Spatial.ChunkManager.all_positions()
        |> Enum.map(fn {id, x, y} ->
          %{id: id, x: Float.round(x * 1.0, 3), y: Float.round(y * 1.0, 3)}
        end)

      observers =
        Simulator.Spatial.ChunkManager.list_observers()
        |> Enum.map(fn obs -> %{id: obs.id, x: obs.x, y: obs.y, radius: obs.radius} end)

      Simulator.Events.broadcast("positions", :positions, %{
        tick: tick,
        interval_ms: state.tick_interval_ms,
        ships: positions,
        observers: observers
      })
    end

    # Ship state deltas — only push ships whose metadata changed
    if rem(tick, @ship_states_interval) == 0 do
      changed = Simulator.Spatial.ShipMetadata.flush_dirty()

      if changed != [] do
        ships =
          Enum.map(changed, fn {id, meta} ->
            Map.put(meta, :id, id)
          end)

        Simulator.Events.broadcast("ship_states", :ship_states, %{
          tick: tick,
          ships: ships
        })
      end
    end

    # Market snapshot — full state of all markets every ~2 sec.
    # Clients overwrite their market map on each broadcast.
    if rem(tick, @market_states_interval) == 0 do
      markets = collect_market_snapshots()

      if markets != [] do
        Simulator.Events.broadcast("markets", :market_states, %{
          tick: tick,
          markets: markets
        })
      end
    end

    state = %{state | current_tick: tick}
    state = schedule_tick(state)
    {:noreply, state}
  end

  def handle_info(:advance, state) do
    # Tick arrived but we're no longer running — ignore
    {:noreply, state}
  end

  # --- Private ---

  # Collects a compact per-market snapshot from every live MarketAgent. Runs
  # GenServer.calls in parallel with a short per-call timeout so one slow
  # market can't stall the broadcast; silently drops any market that times out
  # or crashes — it'll reappear on the next 2-second cycle.
  defp collect_market_snapshots do
    pairs =
      Registry.select(@registry, [
        {{{:agent, :"$1"}, :"$2", :"$3"}, [], [{{:"$1", :"$2"}}]}
      ])

    pairs
    |> Task.async_stream(
      fn {agent_id, pid} ->
        try do
          state = GenServer.call(pid, :get_state, 250)

          if Map.get(state, :__agent_type__) == :market do
            %{
              id: agent_id,
              facility_id: state.facility_id,
              prices: state.prices,
              supply: state.supply,
              demand: state.demand,
              shortage_ticks: Map.get(state, :shortage_ticks, %{})
            }
          else
            nil
          end
        catch
          :exit, _ -> nil
        end
      end,
      max_concurrency: 16,
      timeout: 500,
      on_timeout: :kill_task,
      ordered: false
    )
    |> Enum.reduce([], fn
      {:ok, nil}, acc -> acc
      {:ok, snapshot}, acc -> [snapshot | acc]
      _, acc -> acc
    end)
  end

  defp schedule_tick(state) do
    ref = Process.send_after(self(), :advance, state.tick_interval_ms)
    %{state | timer_ref: ref}
  end

  defp cancel_timer(%{timer_ref: nil} = state), do: state

  defp cancel_timer(%{timer_ref: ref} = state) do
    Process.cancel_timer(ref)
    %{state | timer_ref: nil}
  end

  defp restore_tick_from_db do
    case Simulator.Repo.get(Simulator.Schemas.SimulationState, "tick_coordinator") do
      %{value: %{"current_tick" => tick}} when is_integer(tick) -> tick
      _ -> 0
    end
  rescue
    _ -> 0
  end
end
