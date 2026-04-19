defmodule Simulator.Agents.AgentTest do
  use Simulator.SimulationCase, async: false

  defmodule TestAgent do
    @moduledoc false
    use Simulator.Agents.Agent

    @impl Simulator.Agents.Agent
    def agent_type, do: :test

    @impl Simulator.Agents.Agent
    def init_agent(config) do
      {:ok, %{ticks_received: [], events_received: [], data: config[:data] || "default"}}
    end

    @impl Simulator.Agents.Agent
    def handle_tick(tick, state) do
      {:ok, %{state | ticks_received: state.ticks_received ++ [tick]}}
    end

    @impl Simulator.Agents.Agent
    def handle_event(event, state) do
      {:ok, %{state | events_received: state.events_received ++ [event]}}
    end

    @impl Simulator.Agents.Agent
    def decide(state) do
      {[:noop], state}
    end
  end

  defp start_agent(config) do
    {:ok, pid} =
      DynamicSupervisor.start_child(
        Simulator.AgentSupervisor,
        {TestAgent, config}
      )

    pid
  end

  describe "agent lifecycle" do
    test "starts and registers with the agent registry" do
      pid = start_agent(%{id: "test-agent-1", data: "hello"})

      assert Process.alive?(pid)
      assert {:ok, ^pid} = Simulator.Agents.Agent.whereis("test-agent-1")
    end

    test "stores agent ID in state" do
      pid = start_agent(%{id: "test-agent-2"})

      state = :sys.get_state(pid)
      assert state.__agent_id__ == "test-agent-2"
    end

    test "passes config to init_agent callback" do
      pid = start_agent(%{id: "test-agent-3", data: "custom"})

      state = :sys.get_state(pid)
      assert state.data == "custom"
    end
  end

  describe "tick handling" do
    test "handle_tick callback is invoked on tick messages" do
      pid = start_agent(%{id: "test-agent-tick"})

      send(pid, {:tick, 1})
      send(pid, {:tick, 2})
      send(pid, {:tick, 3})

      # :sys.get_state waits for all prior messages to be processed
      state = :sys.get_state(pid)
      assert state.ticks_received == [1, 2, 3]
    end
  end

  describe "event handling" do
    test "handle_event callback is invoked on event messages" do
      pid = start_agent(%{id: "test-agent-event"})

      send(pid, {:price_update, %{ore: 42.0}})
      send(pid, {:ship_arrived, %{ship_id: "artemis"}})

      state = :sys.get_state(pid)
      assert length(state.events_received) == 2
    end
  end

  describe "tick subscriber registration" do
    test "agent registers as a tick subscriber" do
      _pid = start_agent(%{id: "test-agent-sub"})

      entries = Registry.lookup(Simulator.AgentRegistry, :tick_subscribers)
      agent_ids = Enum.map(entries, fn {_pid, id} -> id end)
      assert "test-agent-sub" in agent_ids
    end
  end

  describe "agent_type registration" do
    test "stores the type in the Registry value" do
      _pid = start_agent(%{id: "test-agent-type"})

      assert [{_pid, %{type: :test}}] =
               Registry.lookup(Simulator.AgentRegistry, {:agent, "test-agent-type"})
    end

    test "Metrics.list_all_agents can read the type without a sync call" do
      _pid = start_agent(%{id: "test-agent-metrics"})

      agents =
        Registry.select(Simulator.AgentRegistry, [
          {{{:agent, :"$1"}, :"$2", :"$3"}, [], [{{:"$1", :"$2", :"$3"}}]}
        ])
        |> Enum.filter(fn {id, _pid, _val} -> id == "test-agent-metrics" end)

      assert [{"test-agent-metrics", _pid, %{type: :test}}] = agents
    end
  end

  describe "whereis/1" do
    test "returns {:ok, pid} for registered agent" do
      pid = start_agent(%{id: "findme"})

      assert {:ok, ^pid} = Simulator.Agents.Agent.whereis("findme")
    end

    test "returns :error for unknown agent" do
      assert :error = Simulator.Agents.Agent.whereis("nonexistent")
    end
  end
end
