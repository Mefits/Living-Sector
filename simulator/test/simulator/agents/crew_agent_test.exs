defmodule Simulator.Agents.CrewAgentTest do
  use Simulator.SimulationCase, async: false

  alias Simulator.Agents.CrewAgent

  defp start_crew(overrides \\ %{}) do
    config =
      Map.merge(
        %{id: "crew-test-1", name: "Test Crew", role: :pilot, assigned_to: nil},
        overrides
      )

    {:ok, pid} =
      DynamicSupervisor.start_child(Simulator.AgentSupervisor, {CrewAgent, config})

    pid
  end

  defp send_tick(pid, tick) do
    send(pid, {:tick, tick})
    :sys.get_state(pid)
  end

  describe "initialization" do
    test "starts with correct defaults" do
      pid = start_crew()
      state = CrewAgent.get_state(pid)

      assert state.name == "Test Crew"
      assert state.role == :pilot
      assert state.morale == 70
      assert state.health == 100
    end
  end

  describe "hunger" do
    test "hunger increases each tick" do
      pid = start_crew(%{hunger: 10})
      state = send_tick(pid, 1)

      assert state.hunger > 10
    end

    test "crew switches to eating when hunger exceeds threshold" do
      pid = start_crew(%{hunger: 85, current_task: :piloting})
      state = send_tick(pid, 1)

      assert state.current_task == :eating
    end

    test "eating reduces hunger" do
      pid = start_crew(%{hunger: 85, current_task: :eating})
      state = send_tick(pid, 1)

      assert state.hunger < 85
    end

    test "crew resumes duty after eating enough" do
      # hunger < 30 and fatigue < 30 → crew returns to duty
      pid = start_crew(%{hunger: 20, fatigue: 10, current_task: :eating})
      state = send_tick(pid, 1)

      assert state.current_task == :idle
    end
  end

  describe "fatigue" do
    test "active tasks increase fatigue" do
      pid =
        start_crew(%{
          fatigue: 10,
          current_task: :piloting,
          personality: Simulator.AI.Personality.diligent()
        })

      state = send_tick(pid, 1)

      assert state.fatigue > 10
    end

    test "resting reduces fatigue" do
      pid = start_crew(%{fatigue: 50, current_task: :resting})
      state = send_tick(pid, 1)

      assert state.fatigue < 50
    end

    test "crew switches to resting when fatigue exceeds threshold" do
      pid = start_crew(%{fatigue: 90, current_task: :piloting})
      state = send_tick(pid, 1)

      assert state.current_task == :resting
    end
  end

  describe "morale" do
    test "morale adjusts periodically based on conditions" do
      # Crew with very high hunger and no way to eat — morale drops
      # Set hunger above threshold and personality that ignores needs
      stubborn = %{
        profit: 0.9,
        safety: 0.0,
        morale: 0.0,
        exploration: 0.0,
        loyalty: 0.9,
        aggression: 0.0
      }

      pid =
        start_crew(%{
          morale: 70,
          hunger: 90,
          current_task: :piloting,
          personality: stubborn
        })

      # Advance to a morale-check tick (5 * tick_multiplier)
      morale_tick = 5 * Simulator.Simulation.Config.tick_multiplier()
      state = send_tick(pid, morale_tick)

      # hunger > 60 → penalty + drift
      assert state.morale < 70
    end
  end

  describe "skills" do
    test "active navigation task grows navigation skill" do
      pid =
        start_crew(%{
          current_task: :piloting,
          personality: Simulator.AI.Personality.diligent(),
          skills: %{navigation: 30, engineering: 30, trading: 30, combat: 20}
        })

      state = send_tick(pid, 1)

      assert state.skills.navigation > 30
    end
  end

  describe "report_status/1" do
    test "returns a status summary" do
      pid = start_crew()
      report = CrewAgent.report_status(pid)

      assert report.name == "Test Crew"
      assert report.role == :pilot
      assert is_integer(report.morale)
      assert is_integer(report.health)
      assert is_map(report.skills)
    end
  end

  describe "assign_task/2" do
    test "changes the crew member's task" do
      pid = start_crew()
      :ok = CrewAgent.assign_task(pid, :engineering)
      state = CrewAgent.get_state(pid)

      assert state.current_task == :engineering
    end
  end

  describe "complaints" do
    test "sends complaint to parent when morale is low" do
      # Create a "parent" ship that we can receive messages from
      parent_id = "ship-complaint-test"
      Registry.register(Simulator.AgentRegistry, {:agent, parent_id}, parent_id)

      pid = start_crew(%{morale: 15, assigned_to: parent_id})
      send_tick(pid, 1)

      assert_receive {:crew_complaint, %{crew_id: "crew-test-1"}}
    end
  end
end
