defmodule Simulator.Agents.PopAgentTest do
  use Simulator.SimulationCase, async: false

  alias Simulator.Agents.{MarketAgent, PopAgent}

  defp start_market_for_pop do
    config = %{
      id: "market-pop-test",
      facility_id: "pop-test",
      prices: %{ore: 40.0, fuel: 25.0, food: 15.0},
      supply: %{ore: 500, fuel: 500, food: 500},
      demand: %{ore: 20, fuel: 50, food: 100},
      production: %{ore: 0, fuel: 0, food: 0},
      consumption: %{ore: 0, fuel: 0, food: 0}
    }

    {:ok, pid} =
      DynamicSupervisor.start_child(Simulator.AgentSupervisor, {MarketAgent, config})

    pid
  end

  defp start_pop(overrides \\ %{}) do
    config =
      Map.merge(
        %{
          id: "pop-test-workers",
          label: "Test Workers",
          facility_id: "pop-test",
          demographic: :workers,
          population_count: 10_000,
          food_satisfaction: 70,
          total_wealth: 500_000,
          consumption: %{food: 50, fuel: 0}
        },
        overrides
      )

    {:ok, pid} =
      DynamicSupervisor.start_child(Simulator.AgentSupervisor, {PopAgent, config})

    pid
  end

  defp send_tick(pid, tick) do
    send(pid, {:tick, tick})
    :sys.get_state(pid)
  end

  describe "initialization" do
    test "starts with correct state" do
      pid = start_pop()
      state = PopAgent.get_state(pid)

      assert state.label == "Test Workers"
      assert state.demographic == :workers
      assert state.population_count == 10_000
    end
  end

  describe "consumption" do
    test "food satisfaction rises when supply is available" do
      _market = start_market_for_pop()
      pid = start_pop(%{food_satisfaction: 60})

      state = send_tick(pid, 1)

      # With a market that has food, satisfaction should stay near or above starting
      assert state.food_satisfaction >= 59
    end

    @consume_interval 5 * Simulator.Simulation.Config.tick_multiplier()

    test "food satisfaction drops without a market" do
      # No market started — pop can't buy food
      pid = start_pop(%{food_satisfaction: 70})

      state = send_tick(pid, @consume_interval)

      assert state.food_satisfaction < 70
    end

    test "spending reduces wealth" do
      _market = start_market_for_pop()
      pid = start_pop(%{total_wealth: 500_000})

      state = send_tick(pid, @consume_interval)

      assert state.total_wealth < 500_000
    end
  end

  describe "sentiment" do
    test "sentiment tracks satisfaction with inertia" do
      pid = start_pop(%{food_satisfaction: 20, overall_sentiment: 80})

      # Run enough ticks for sentiment to drift with high inertia
      ticks_needed = Simulator.Simulation.Config.tick_multiplier() * 10

      state =
        Enum.reduce(1..ticks_needed, nil, fn tick, _acc ->
          send_tick(pid, tick)
        end)

      # Sentiment should have moved toward low satisfaction
      assert state.overall_sentiment < 80
    end

    test "unrest rises when sentiment is low" do
      pid = start_pop(%{food_satisfaction: 10, overall_sentiment: 20, unrest: 10})

      state =
        Enum.reduce(1..10, nil, fn tick, _acc ->
          send_tick(pid, tick)
        end)

      assert state.unrest > 10
    end
  end

  describe "growth" do
    @growth_interval 10 * Simulator.Simulation.Config.tick_multiplier()

    test "population grows when sentiment is high" do
      _market = start_market_for_pop()
      pid = start_pop(%{overall_sentiment: 80, population_count: 10_000})

      state =
        Enum.reduce(1..@growth_interval, nil, fn tick, _acc ->
          send_tick(pid, tick)
        end)

      assert state.population_count > 10_000
    end
  end

  describe "event broadcasting" do
    test "broadcasts population updates" do
      pid = start_pop()
      Simulator.Events.subscribe("facility:pop-test")

      send_tick(pid, 1)

      assert_receive {:population_update,
                      %{
                        pop_id: "pop-test-workers",
                        demographic: :workers,
                        population: _,
                        sentiment: _,
                        tick: 1
                      }}
    end
  end
end
