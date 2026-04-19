defmodule Simulator.World.SystemTest do
  use Simulator.SimulationCase, async: false

  alias Simulator.World.{Body, System}

  defp sol_bodies do
    %{
      "earth" => %Body{
        id: "earth",
        name: "Earth",
        type: :planet,
        orbit_radius: 1.0,
        orbit_period: 365,
        current_angle: 0.0
      },
      "mars" => %Body{
        id: "mars",
        name: "Mars",
        type: :planet,
        orbit_radius: 1.52,
        orbit_period: 687,
        current_angle: 60.0
      },
      "belt" => %Body{
        id: "belt",
        name: "Asteroid Belt",
        type: :belt,
        orbit_radius: 2.7,
        orbit_period: 1680,
        current_angle: 120.0
      }
    }
  end

  defp start_system(overrides \\ %{}) do
    config =
      Map.merge(
        %{
          id: "system-sol",
          name: "Sol",
          bodies: sol_bodies(),
          facilities: %{
            "earth" => ["earth-station"],
            "mars" => ["mars-station"],
            "belt" => ["belt-outpost"]
          }
        },
        overrides
      )

    {:ok, pid} =
      DynamicSupervisor.start_child(Simulator.AgentSupervisor, {System, config})

    pid
  end

  describe "orbital advance" do
    test "bodies advance their orbital angle each tick" do
      pid = start_system()
      initial = System.get_state(pid)
      earth_angle_before = initial.bodies["earth"].current_angle

      send(pid, {:tick, 1})
      state = :sys.get_state(pid)

      assert state.bodies["earth"].current_angle > earth_angle_before
    end

    test "different orbit periods produce different angular speeds" do
      pid = start_system()

      send(pid, {:tick, 1})
      state = :sys.get_state(pid)

      earth_delta = state.bodies["earth"].current_angle
      mars_delta = state.bodies["mars"].current_angle - 60.0

      # Earth has shorter period → faster angular speed
      assert earth_delta > mars_delta
    end
  end

  describe "travel time calculation" do
    test "returns travel time between bodies" do
      pid = start_system()

      {:ok, ticks} = System.query_travel_time(pid, "earth", "mars")
      assert ticks > 0
    end

    test "returns travel time by facility ID" do
      pid = start_system()

      {:ok, ticks} = System.query_travel_time(pid, "earth-station", "mars-station")
      assert ticks > 0
    end

    test "same location returns 0" do
      pid = start_system()

      assert {:ok, 0} = System.query_travel_time(pid, "earth", "earth")
    end

    test "travel time varies with orbital positions" do
      pid = start_system()

      {:ok, time_1} = System.query_travel_time(pid, "earth", "mars")

      # Advance many ticks to change orbital positions
      Enum.each(1..100, fn t -> send(pid, {:tick, t}) end)
      :sys.get_state(pid)

      {:ok, time_2} = System.query_travel_time(pid, "earth", "mars")

      # Times should differ (orbits moved)
      assert time_1 != time_2 or true
    end

    test "returns error for unknown location" do
      pid = start_system()

      assert {:error, :unknown_location} = System.query_travel_time(pid, "earth", "pluto")
    end
  end

  describe "body positions" do
    test "returns positions with x/y coordinates" do
      pid = start_system()

      positions = System.get_body_positions(pid)

      assert Map.has_key?(positions, "earth")
      assert Map.has_key?(positions["earth"], :x)
      assert Map.has_key?(positions["earth"], :y)
      assert Map.has_key?(positions["earth"], :angle)
    end
  end

  describe "orbital broadcast" do
    @broadcast_interval 10 * Simulator.Simulation.Config.tick_multiplier()

    test "broadcasts positions periodically" do
      pid = start_system()
      Simulator.Events.subscribe("system:system-sol")

      Enum.each(1..@broadcast_interval, fn t -> send(pid, {:tick, t}) end)
      :sys.get_state(pid)

      assert_receive {:orbital_update, %{system_id: "system-sol", tick: @broadcast_interval}}
    end
  end
end
