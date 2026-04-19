defmodule Simulator.AI.UtilityTest do
  use ExUnit.Case, async: true

  alias Simulator.AI.{Utility, Personality, Considerations}

  describe "score_action/3" do
    test "positive factor increases score" do
      considerations = %{fuel_urgency: {0.8, :safety}}
      personality = %{safety: 1.0}
      action = {:refuel, [{:fuel_urgency, :positive}]}

      score = Utility.score_action(action, considerations, personality)
      assert score == 0.8
    end

    test "negative factor decreases score" do
      considerations = %{fuel_urgency: {0.8, :safety}}
      personality = %{safety: 1.0}
      action = {:trade_run, [{:fuel_urgency, :negative}]}

      score = Utility.score_action(action, considerations, personality)
      assert score == -0.8
    end

    test "personality weight scales the score" do
      considerations = %{fuel_urgency: {0.8, :safety}}
      personality = %{safety: 0.5}
      action = {:refuel, [{:fuel_urgency, :positive}]}

      score = Utility.score_action(action, considerations, personality)
      assert score == 0.4
    end

    test "multiple factors sum" do
      considerations = %{
        fuel_urgency: {0.8, :safety},
        trade_profit: {0.6, :profit}
      }

      personality = %{safety: 0.5, profit: 0.8}

      action =
        {:trade_run,
         [
           {:trade_profit, :positive},
           {:fuel_urgency, :negative}
         ]}

      score = Utility.score_action(action, considerations, personality)
      # 0.6 * 0.8 - 0.8 * 0.5 = 0.48 - 0.4 = 0.08
      assert_in_delta score, 0.08, 0.001
    end

    test "missing consideration is ignored" do
      considerations = %{}
      personality = %{safety: 1.0}
      action = {:refuel, [{:nonexistent, :positive}]}

      score = Utility.score_action(action, considerations, personality)
      assert score == 0.0
    end
  end

  describe "best_action/3" do
    test "returns highest scoring action" do
      considerations = %{
        fuel_urgency: {0.9, :safety},
        trade_profit: {0.3, :profit}
      }

      personality = Personality.cautious_trader()

      actions = [
        {:trade_run, [{:trade_profit, :positive}]},
        {:refuel, [{:fuel_urgency, :positive}]},
        {:idle, []}
      ]

      {action, _score} = Utility.best_action(actions, considerations, personality)
      assert action == :refuel
    end

    test "aggressive trader prefers profit over safety" do
      considerations = %{
        fuel_urgency: {0.5, :safety},
        trade_profit: {0.7, :profit}
      }

      personality = Personality.aggressive_trader()

      actions = [
        {:trade_run, [{:trade_profit, :positive}]},
        {:refuel, [{:fuel_urgency, :positive}]},
        {:idle, []}
      ]

      {action, _score} = Utility.best_action(actions, considerations, personality)
      assert action == :trade_run
    end

    test "returns idle when no actions score above 0" do
      considerations = %{}
      personality = Personality.balanced_trader()
      actions = [{:trade_run, [{:nonexistent, :positive}]}]

      {action, score} = Utility.best_action(actions, considerations, personality)
      assert action == :idle
      assert score == 0.0
    end
  end

  describe "archetype prefer_goals" do
    test "cautious trader gets a boost on contract goals" do
      # All considerations zero — only prefer_goals bonus survives.
      considerations = %{}
      personality = Personality.cautious_trader()

      actions = [
        {:trade_run, []},
        {:fulfill_contract, []},
        {:station_job, []}
      ]

      {action, score} = Utility.best_action(actions, considerations, personality)
      assert action == :fulfill_contract
      assert score > 0.0
    end

    test "aggressive trader gets a boost on trade_run" do
      considerations = %{}
      personality = Personality.aggressive_trader()

      actions = [
        {:trade_run, []},
        {:fulfill_contract, []}
      ]

      {action, _score} = Utility.best_action(actions, considerations, personality)
      assert action == :trade_run
    end

    test "prefer bonus breaks ties between otherwise equal goals" do
      considerations = %{
        op: {0.5, :profit}
      }

      personality =
        Personality.cautious_trader()
        # Override prefer_goals so only one goal gets the bonus.
        |> Map.put(:prefer_goals, %{fulfill_contract: 0.3})

      actions = [
        {:trade_run, [{:op, :positive}]},
        {:fulfill_contract, [{:op, :positive}]}
      ]

      {action, _score} = Utility.best_action(actions, considerations, personality)
      assert action == :fulfill_contract
    end

    test "missing prefer_goals map is tolerated" do
      considerations = %{op: {0.5, :profit}}
      personality = %{profit: 1.0}
      actions = [{:trade_run, [{:op, :positive}]}]

      {action, _score} = Utility.best_action(actions, considerations, personality)
      assert action == :trade_run
    end
  end

  describe "rank_actions/3" do
    test "returns actions sorted by score descending" do
      considerations = %{
        fuel_urgency: {0.9, :safety},
        trade_profit: {0.5, :profit},
        crew_morale: {0.3, :morale}
      }

      personality = %{safety: 0.8, profit: 0.6, morale: 0.4}

      actions = [
        {:trade_run, [{:trade_profit, :positive}]},
        {:refuel, [{:fuel_urgency, :positive}]},
        {:rest_crew, [{:crew_morale, :positive}]}
      ]

      ranked = Utility.rank_actions(actions, considerations, personality)
      [first, second, third] = ranked

      assert elem(first, 0) == :refuel
      assert elem(first, 1) > elem(second, 1)
      assert elem(second, 1) > elem(third, 1)
    end
  end

  describe "considerations integration" do
    test "ship considerations produce valid values" do
      ship_state = %{
        fuel: 30.0,
        fuel_capacity: 100.0,
        credits: 2000,
        efficiency: 0.6,
        cargo: %{ore: 100},
        cargo_capacity: 500,
        memory: %{
          known_prices: %{
            "earth-station" => %{ore: %{price: 10.0, tick: 0}},
            "belt-outpost" => %{ore: %{price: 50.0, tick: 0}}
          },
          visited: ["earth-station"]
        }
      }

      {fuel_val, :safety} = Considerations.fuel_urgency(ship_state)
      assert fuel_val >= 0.0 and fuel_val <= 1.0
      # 30/100 = 0.7 urgency
      assert fuel_val > 0.5

      {profit_val, :profit} = Considerations.trade_opportunity(ship_state)
      assert profit_val >= 0.0 and profit_val <= 1.0
      # There's a price differential
      assert profit_val > 0.0

      {morale_val, :morale} = Considerations.crew_morale_concern(ship_state)
      assert morale_val >= 0.0 and morale_val <= 1.0

      {cargo_val, :profit} = Considerations.cargo_opportunity(ship_state)
      assert cargo_val >= 0.0 and cargo_val <= 1.0
      # Ship is mostly empty
      assert cargo_val > 0.5
    end

    test "contract_distance_concern scales with best available distance" do
      near_state = %{available_contracts: [%{distance: 20, payment: 1000}]}
      far_state = %{available_contracts: [%{distance: 180, payment: 1000}]}
      empty_state = %{available_contracts: []}

      {near_val, :safety} = Considerations.contract_distance_concern(near_state)
      {far_val, :safety} = Considerations.contract_distance_concern(far_state)
      {empty_val, :safety} = Considerations.contract_distance_concern(empty_state)

      assert near_val < far_val
      assert far_val > 0.5
      assert empty_val == 0.0
    end

    test "contract_distance_concern weighs negatively for cautious ships via utility" do
      state = %{available_contracts: [%{distance: 180, payment: 1000}]}

      considerations = %{
        contract_distance_concern: Considerations.contract_distance_concern(state)
      }

      cautious = Personality.cautious_trader()
      aggressive = Personality.aggressive_trader()

      action = {:fulfill_contract, [{:contract_distance_concern, :negative}]}

      cautious_score = Utility.score_action(action, considerations, cautious)
      aggressive_score = Utility.score_action(action, considerations, aggressive)

      # Both penalties are negative. Cautious (high safety weight) gets a
      # larger penalty than aggressive (low safety weight).
      assert cautious_score < aggressive_score
    end
  end
end
