defmodule Simulator.Simulation.SpawnerTest do
  use Simulator.SimulationCase, async: false
  use Simulator.DataCase, async: false

  alias Simulator.Simulation.Spawner
  alias Simulator.Queries

  describe "spawn_world/0" do
    setup do
      # Seed the test DB so spawner has data to read
      Simulator.Seed.seed_all()
      Simulator.World.Registry.reload()
      :ok
    end

    test "creates all expected agents" do
      Spawner.spawn_world()

      # Wait for agents to register
      Process.sleep(50)

      ships = Queries.all_ships()
      markets = Queries.all_markets()
      facilities = Queries.all_facilities()
      system = Queries.system_state()

      # Expanded universe — 3 systems, many ships/facilities/markets
      assert length(ships) > 20
      assert length(markets) > 10
      assert length(facilities) > 15
      assert system != nil
    end

    test "tick coordinator is running after spawn" do
      Spawner.spawn_world()

      assert Simulator.TickCoordinator.running?() == true
      assert Simulator.TickCoordinator.get_tick() >= 0
    end

    test "teardown stops all agents" do
      Spawner.spawn_world()
      Process.sleep(50)

      assert Queries.all_ships() != []

      Spawner.teardown()
      Process.sleep(50)

      assert Queries.all_ships() == []
      assert Simulator.TickCoordinator.running?() == false
    end
  end
end
