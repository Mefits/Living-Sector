defmodule Simulator.Agents.ShipAgent.PlannerTest do
  use ExUnit.Case, async: true

  alias Simulator.Agents.ShipAgent.Planner

  defp ship_state(overrides \\ %{}) do
    Map.merge(
      %{
        location: "earth-station",
        cargo: %{},
        cargo_capacity: 500,
        fuel: 100.0,
        fuel_capacity: 100.0,
        fuel_consumption_rate: 0.5,
        credits: 5_000,
        efficiency: 1.0,
        memory: %{
          known_prices: %{
            "earth-station" => %{ore: 40.0, fuel: 25.0, food: 15.0},
            "mars-station" => %{ore: 30.0, fuel: 25.0, food: 25.0},
            "belt-outpost" => %{ore: 20.0, fuel: 30.0, food: 35.0}
          },
          visited: [],
          blacklist: []
        }
      },
      overrides
    )
  end

  describe "best_plan/2" do
    test "generates a profitable trade plan when price differentials exist" do
      state = ship_state()
      plan = Planner.best_plan(state, 1)

      assert plan != nil
      assert plan.type == :trade_run
      assert plan.expected_profit > 0
      assert plan.steps != []
    end

    test "returns idle plan when no profitable routes exist" do
      state =
        ship_state(%{
          memory: %{
            known_prices: %{
              "earth-station" => %{ore: 40.0, fuel: 25.0, food: 15.0},
              "mars-station" => %{ore: 40.0, fuel: 25.0, food: 15.0},
              "belt-outpost" => %{ore: 40.0, fuel: 25.0, food: 15.0}
            },
            visited: [],
            blacklist: []
          }
        })

      plan = Planner.best_plan(state, 1)
      assert plan.type == :idle
    end

    test "returns idle when ship has no location (in transit)" do
      state = ship_state(%{location: nil})
      plan = Planner.best_plan(state, 1)
      assert plan.type == :idle
    end

    test "avoids destinations requiring too much fuel" do
      state = ship_state(%{fuel: 2.0, fuel_consumption_rate: 1.0})
      plans = Planner.generate_plans(state, 1)

      # With 2.0 fuel and 1.0/tick rate, no destination is reachable
      # (closest is 8 ticks = 8.0 fuel needed, but safety margin requires < 1.8)
      assert plans == []
    end
  end

  describe "generate_plans/2" do
    test "generates plans for each profitable commodity route" do
      state = ship_state()
      plans = Planner.generate_plans(state, 1)

      assert plans != []
      assert Enum.all?(plans, &(&1.type == :trade_run))
      assert Enum.all?(plans, &(&1.expected_profit > 0))
    end

    test "ship with no price knowledge generates no plans" do
      state = ship_state(%{memory: %{known_prices: %{}, visited: [], blacklist: []}})
      plans = Planner.generate_plans(state, 1)
      assert plans == []
    end
  end
end
