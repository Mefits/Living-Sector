defmodule Simulator.TickCoordinatorTest do
  use Simulator.SimulationCase, async: false

  alias Simulator.TickCoordinator

  # The TickCoordinator is started by the application supervisor.
  # SimulationCase resets it between tests via stop/0.
  # We set a fast tick interval for responsive tests.

  describe "start/0" do
    test "begins ticking and increments the tick counter" do
      assert TickCoordinator.get_tick() == 0

      TickCoordinator.set_speed(5)
      TickCoordinator.start()

      Process.sleep(50)

      tick = TickCoordinator.get_tick()
      assert tick > 0
    end

    test "dispatches ticks to registered agents" do
      Registry.register(Simulator.AgentRegistry, :tick_subscribers, "test")

      TickCoordinator.set_speed(5)
      TickCoordinator.start()

      assert_receive {:tick, 1}, 200
      assert_receive {:tick, 2}, 200
    end

    test "broadcasts ticks to PubSub" do
      Simulator.Events.subscribe("tick")

      TickCoordinator.set_speed(5)
      TickCoordinator.start()

      assert_receive {:tick, %{tick: 1}}, 200
      assert_receive {:tick, %{tick: 2}}, 200
    end
  end

  describe "pause/0 and resume/0" do
    test "pause stops ticking, resume continues" do
      TickCoordinator.set_speed(5)
      TickCoordinator.start()
      Process.sleep(30)

      TickCoordinator.pause()
      tick_at_pause = TickCoordinator.get_tick()
      assert tick_at_pause > 0

      Process.sleep(30)
      assert TickCoordinator.get_tick() == tick_at_pause

      TickCoordinator.resume()
      Process.sleep(30)
      assert TickCoordinator.get_tick() > tick_at_pause
    end
  end

  describe "stop/0" do
    test "stops ticking and resets counter to 0" do
      TickCoordinator.set_speed(5)
      TickCoordinator.start()
      Process.sleep(30)
      assert TickCoordinator.get_tick() > 0

      TickCoordinator.stop()
      assert TickCoordinator.get_tick() == 0
      assert TickCoordinator.running?() == false
    end
  end

  describe "set_speed/1" do
    test "changes the tick interval" do
      TickCoordinator.set_speed(20)
      TickCoordinator.start()
      Process.sleep(50)
      slow_ticks = TickCoordinator.get_tick()

      TickCoordinator.stop()

      TickCoordinator.set_speed(1)
      TickCoordinator.start()
      Process.sleep(50)
      fast_ticks = TickCoordinator.get_tick()

      assert fast_ticks > slow_ticks
    end
  end

  describe "running?/0" do
    test "returns false when paused, true when running" do
      assert TickCoordinator.running?() == false

      TickCoordinator.start()
      assert TickCoordinator.running?() == true

      TickCoordinator.pause()
      assert TickCoordinator.running?() == false
    end
  end

  describe "market_states broadcast" do
    test "broadcasts a full market snapshot every ~2s" do
      {:ok, _market_pid} =
        DynamicSupervisor.start_child(
          Simulator.AgentSupervisor,
          {Simulator.Agents.MarketAgent,
           %{
             id: "market-tickertest",
             facility_id: "tickertest-station",
             prices: %{ore: 40.0, fuel: 25.0},
             supply: %{ore: 500, fuel: 500},
             demand: %{ore: 20, fuel: 50},
             production: %{ore: 0, fuel: 0},
             consumption: %{ore: 0, fuel: 0}
           }}
        )

      Simulator.Events.subscribe("markets")

      TickCoordinator.set_speed(5)
      TickCoordinator.start()

      # Broadcast interval is 16 ticks → 80ms at 5ms/tick.
      assert_receive {:market_states, %{tick: tick, markets: markets}}, 500
      assert tick > 0
      assert is_list(markets)

      found = Enum.find(markets, &(&1.id == "market-tickertest"))
      assert found
      assert found.facility_id == "tickertest-station"
      assert %{ore: _, fuel: _} = found.prices
      assert %{ore: _, fuel: _} = found.supply
      assert is_map(found.demand)
      assert is_map(found.shortage_ticks)
    end
  end
end
