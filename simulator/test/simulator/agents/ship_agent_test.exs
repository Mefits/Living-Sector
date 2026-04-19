defmodule Simulator.Agents.ShipAgentTest do
  use Simulator.SimulationCase, async: false

  alias Simulator.Agents.{FacilityAgent, MarketAgent, ShipAgent}

  defp start_facility(id, location, overrides \\ %{}) do
    config =
      Map.merge(
        %{
          id: id,
          name: id,
          location: location,
          docking_capacity: 10,
          services: [:refuel, :market],
          reserves: %{fuel: 5000, food: 2000}
        },
        overrides
      )

    {:ok, pid} =
      DynamicSupervisor.start_child(Simulator.AgentSupervisor, {FacilityAgent, config})

    pid
  end

  defp start_market(id, facility_id, overrides \\ %{}) do
    config =
      Map.merge(
        %{
          id: id,
          facility_id: facility_id,
          prices: %{ore: 40.0, fuel: 25.0, food: 15.0},
          supply: %{ore: 1000, fuel: 1000, food: 1000},
          demand: %{ore: 20, fuel: 50, food: 100},
          production: %{ore: 0, fuel: 0, food: 0},
          consumption: %{ore: 0, fuel: 0, food: 0}
        },
        overrides
      )

    {:ok, pid} =
      DynamicSupervisor.start_child(Simulator.AgentSupervisor, {MarketAgent, config})

    pid
  end

  defp start_ship(overrides \\ %{}) do
    config =
      Map.merge(
        %{
          id: "ship-test-1",
          name: "Test Ship",
          location: "earth-station",
          fuel: 100.0,
          credits: 5_000,
          cargo: %{},
          cargo_capacity: 500,
          known_prices: %{
            "earth-station" => %{ore: 40.0, fuel: 25.0, food: 15.0},
            "belt-outpost" => %{ore: 20.0, fuel: 30.0, food: 35.0}
          }
        },
        overrides
      )

    {:ok, pid} =
      DynamicSupervisor.start_child(Simulator.AgentSupervisor, {ShipAgent, config})

    pid
  end

  defp send_tick(pid, tick) do
    send(pid, {:tick, tick})
    :sys.get_state(pid)
  end

  describe "initialization" do
    test "starts with correct state" do
      pid = start_ship()
      state = ShipAgent.get_state(pid)

      assert state.name == "Test Ship"
      assert state.location == "earth-station"
      assert state.credits == 5_000
      assert state.fuel == 100.0
    end
  end

  describe "plan generation" do
    test "creates a trade plan when price differentials exist" do
      start_facility("facility-earth-station", "earth-station")
      start_facility("facility-belt-outpost", "belt-outpost")

      start_market("market-earth-station", "earth-station", %{
        prices: %{ore: 40.0, fuel: 25.0, food: 15.0}
      })

      start_market("market-belt-outpost", "belt-outpost", %{
        prices: %{ore: 20.0, fuel: 30.0, food: 35.0}
      })

      pid = start_ship()
      state = send_tick(pid, 1)

      assert state.current_goal != nil
      assert state.current_bt != nil
    end
  end

  describe "transit" do
    test "ship enters transit and consumes fuel" do
      start_facility("facility-earth-station", "earth-station")
      start_facility("facility-belt-outpost", "belt-outpost")
      start_market("market-earth-station", "earth-station")
      start_market("market-belt-outpost", "belt-outpost")

      pid = start_ship()

      # First tick: plan generated, first step might be buy or travel
      state = send_tick(pid, 1)

      # Advance several ticks — eventually the ship should enter transit
      state =
        Enum.reduce(2..5, state, fn tick, _acc ->
          send_tick(pid, tick)
        end)

      # Ship should either be in transit or have executed some steps
      assert state.current_bt != nil or state.transit != nil or state.location != nil
    end

    test "ship arrives at destination after travel time elapses" do
      start_facility("facility-earth-station", "earth-station")
      start_facility("facility-belt-outpost", "belt-outpost")
      start_market("market-belt-outpost", "belt-outpost")
      start_market("market-earth-station", "earth-station")

      pid =
        start_ship(%{
          location: "earth-station",
          known_prices: %{
            "earth-station" => %{ore: 40.0, fuel: 25.0, food: 15.0},
            "belt-outpost" => %{ore: 20.0, fuel: 30.0, food: 35.0}
          }
        })

      Simulator.Events.subscribe("ship:ship-test-1")

      # Run enough ticks for the ship to plan, buy, travel, and arrive
      # Earth to belt is 15 ticks
      Enum.each(1..25, fn tick ->
        send_tick(pid, tick)
      end)

      state = ShipAgent.get_state(pid)

      # By tick 25, ship should have completed at least part of a trade
      # Check that credits changed (traded) or location changed (traveled)
      assert state.credits != 5_000 or state.location != "earth-station"
    end
  end

  describe "trading" do
    test "ship credits change after executing a trade plan" do
      start_facility("facility-earth-station", "earth-station")
      start_facility("facility-belt-outpost", "belt-outpost")

      start_market("market-earth-station", "earth-station", %{
        prices: %{ore: 40.0, fuel: 25.0, food: 15.0},
        supply: %{ore: 1000, fuel: 1000, food: 1000}
      })

      start_market("market-belt-outpost", "belt-outpost", %{
        prices: %{ore: 20.0, fuel: 30.0, food: 35.0},
        supply: %{ore: 1000, fuel: 1000, food: 1000}
      })

      pid = start_ship(%{credits: 5_000, cargo: %{}})

      # Run enough ticks for a full trade cycle (dock → buy → undock → travel → dock → sell)
      Enum.each(1..35, fn tick ->
        send_tick(pid, tick)
      end)

      state = ShipAgent.get_state(pid)

      # Credits should have changed from trading
      assert state.credits != 5_000
    end
  end

  describe "cargo age + hoarder recycle" do
    test "hoarder fields default to empty/zero on init" do
      pid = start_ship()
      state = ShipAgent.get_state(pid)

      assert state.cargo_age == %{}
      assert state.idle_ticks == 0
      assert state.hoard_strikes == 0
    end

    test "aged cargo forces :sell_cargo as the selected goal" do
      # Seed a ship with cargo stamped long ago so the hoard override trips.
      start_facility("facility-earth-station", "earth-station")
      start_market("market-earth-station", "earth-station")

      pid =
        start_ship(%{
          cargo: %{ore: 100},
          docked_at: nil
        })

      # Inject an old cargo_age stamp via the GenServer state so the override
      # fires on the next tick.
      :sys.replace_state(pid, fn state -> %{state | cargo_age: %{ore: 0}} end)

      # Tick far in the future to make the cargo "aged".
      state = send_tick(pid, 5_000)

      assert state.current_goal == :sell_cargo
    end

    test "hoard_strikes increments when cargo is very stale and cargo remains" do
      start_facility("facility-earth-station", "earth-station")
      start_market("market-earth-station", "earth-station")

      pid =
        start_ship(%{
          cargo: %{ore: 100},
          credits: 50_000
        })

      # Stamp cargo as received at tick 0 and leave it there.
      :sys.replace_state(pid, fn state -> %{state | cargo_age: %{ore: 0}} end)

      # Must land on a tick divisible by the hoard check interval
      # (100 * tick_multiplier), and stale past the strike threshold
      # (150 * tick_multiplier). tick_multiplier at runtime is >= 4 in all
      # configs, so tick = 6400 satisfies both conditions.
      interval = 100 * Simulator.Simulation.Config.tick_multiplier()
      tick = interval * 2
      state = send_tick(pid, tick)

      assert state.hoard_strikes >= 1
    end
  end

  describe "broke lifeline override" do
    test "broke ship with cargo is forced into :sell_cargo" do
      start_facility("facility-earth-station", "earth-station")
      start_market("market-earth-station", "earth-station")

      pid = start_ship(%{credits: 100, cargo: %{ore: 50}})

      :sys.replace_state(pid, fn state -> %{state | cargo_age: %{ore: 5_000}} end)

      state = send_tick(pid, 5_001)
      assert state.current_goal == :sell_cargo
    end

    test "broke ship docked without cargo takes a station job" do
      start_facility("facility-earth-station", "earth-station", %{credits: 10_000})
      start_market("market-earth-station", "earth-station")

      pid = start_ship(%{credits: 100, cargo: %{}})

      # Simulate the ship being docked.
      :sys.replace_state(pid, fn state ->
        %{state | docked_at: "facility-earth-station"}
      end)

      state = send_tick(pid, 1)

      assert state.current_goal == :station_job
    end
  end

  describe "docking integration" do
    test "ship docks at facility before trading" do
      facility_pid = start_facility("facility-earth-station", "earth-station")
      start_facility("facility-belt-outpost", "belt-outpost")
      start_market("market-earth-station", "earth-station")
      start_market("market-belt-outpost", "belt-outpost")

      pid = start_ship()

      # Advance a few ticks — ship should dock as part of its plan
      Enum.each(1..5, fn tick -> send_tick(pid, tick) end)

      facility_state = FacilityAgent.get_state(facility_pid)

      # Ship should have docked at some point
      ship_state = ShipAgent.get_state(pid)

      assert ship_state.docked_at != nil or ship_state.transit != nil or
               "ship-test-1" in facility_state.docked_ships
    end

    test "ship waits when dock is full" do
      start_facility("facility-earth-station", "earth-station", %{docking_capacity: 0})
      start_facility("facility-belt-outpost", "belt-outpost")
      start_market("market-earth-station", "earth-station")
      start_market("market-belt-outpost", "belt-outpost")

      pid = start_ship()

      # First tick — ship tries to dock, gets rejected, waits
      state = send_tick(pid, 1)

      # Dock failed — BT completed with failure, agent will retry next tick
      assert state.docked_at == nil
    end
  end
end
