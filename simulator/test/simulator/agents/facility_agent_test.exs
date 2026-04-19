defmodule Simulator.Agents.FacilityAgentTest do
  use Simulator.SimulationCase, async: false

  alias Simulator.Agents.FacilityAgent

  defp start_facility(overrides \\ %{}) do
    config =
      Map.merge(
        %{
          id: "facility-earth",
          name: "Earth Station",
          location: "earth-station",
          docking_capacity: 3,
          services: [:refuel, :market],
          reserves: %{fuel: 5000, food: 2000}
        },
        overrides
      )

    {:ok, pid} =
      DynamicSupervisor.start_child(Simulator.AgentSupervisor, {FacilityAgent, config})

    pid
  end

  describe "docking protocol" do
    test "grants dock when capacity available" do
      pid = start_facility()

      assert {:ok, info} = FacilityAgent.request_dock(pid, %{ship_id: "ship-1"})
      assert info.facility_id == "facility-earth"
      assert :refuel in info.services
    end

    test "denies dock when at capacity" do
      pid = start_facility(%{docking_capacity: 2})

      assert {:ok, _} = FacilityAgent.request_dock(pid, %{ship_id: "ship-1"})
      assert {:ok, _} = FacilityAgent.request_dock(pid, %{ship_id: "ship-2"})
      assert {:error, :full} = FacilityAgent.request_dock(pid, %{ship_id: "ship-3"})
    end

    test "allows re-docking already docked ship" do
      pid = start_facility(%{docking_capacity: 1})

      assert {:ok, _} = FacilityAgent.request_dock(pid, %{ship_id: "ship-1"})
      assert {:ok, _} = FacilityAgent.request_dock(pid, %{ship_id: "ship-1"})
    end

    test "undocking frees a slot" do
      pid = start_facility(%{docking_capacity: 1})

      assert {:ok, _} = FacilityAgent.request_dock(pid, %{ship_id: "ship-1"})
      assert :ok = FacilityAgent.request_undock(pid, "ship-1")
      assert {:ok, _} = FacilityAgent.request_dock(pid, %{ship_id: "ship-2"})
    end

    test "broadcasts docking events" do
      pid = start_facility()
      Simulator.Events.subscribe("facility:facility-earth")

      FacilityAgent.request_dock(pid, %{ship_id: "ship-1"})
      assert_receive {:docking_event, %{ship_id: "ship-1", type: :docked}}

      FacilityAgent.request_undock(pid, "ship-1")
      assert_receive {:docking_event, %{ship_id: "ship-1", type: :undocked}}
    end
  end

  describe "refueling" do
    test "transfers fuel from reserves" do
      pid = start_facility(%{reserves: %{fuel: 100, food: 0}})

      assert {:ok, info} = FacilityAgent.request_refuel(pid, %{amount: 30})
      assert info.amount == 30
      assert info.cost > 0

      state = FacilityAgent.get_state(pid)
      assert state.reserves.fuel == 70
    end

    test "caps refuel at available supply" do
      pid = start_facility(%{reserves: %{fuel: 10, food: 0}})

      assert {:ok, info} = FacilityAgent.request_refuel(pid, %{amount: 50})
      assert info.amount == 10
    end

    test "returns error when no fuel available" do
      pid = start_facility(%{reserves: %{fuel: 0, food: 0}})

      assert {:error, :no_fuel} = FacilityAgent.request_refuel(pid, %{amount: 30})
    end
  end

  describe "condition degradation" do
    test "condition degrades each tick" do
      pid = start_facility(%{condition: 1.0})

      send(pid, {:tick, 1})
      state = :sys.get_state(pid)

      assert state.condition < 1.0
    end

    test "services go offline when condition is critical" do
      pid = start_facility(%{condition: 0.1})

      # Degrade further
      Enum.each(1..10, fn t -> send(pid, {:tick, t}) end)

      state = :sys.get_state(pid)
      # Below 0.3 threshold — services shut down
      assert {:ok, info} = FacilityAgent.request_dock(pid, %{ship_id: "ship-1"})
      assert info.services == [] or state.condition >= 0.3
    end
  end
end
