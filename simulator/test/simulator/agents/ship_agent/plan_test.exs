defmodule Simulator.Agents.ShipAgent.PlanTest do
  use ExUnit.Case, async: true

  alias Simulator.Agents.ShipAgent.{Plan, PlanStep}

  defp sample_plan do
    %Plan{
      type: :trade_run,
      steps: [
        %PlanStep{action: :buy, commodity: :ore, quantity: 100, at: "earth-station"},
        %PlanStep{action: :travel, to: "mars-station"},
        %PlanStep{action: :sell, commodity: :ore, quantity: 100, at: "mars-station"}
      ],
      expected_profit: 500.0,
      created_at_tick: 10,
      expires_at_tick: 160
    }
  end

  describe "next_step/1" do
    test "returns the first step initially" do
      plan = sample_plan()
      step = Plan.next_step(plan)
      assert step.action == :buy
    end

    test "returns nil when plan is complete" do
      plan = %{sample_plan() | current_step_index: 3}
      assert Plan.next_step(plan) == nil
    end
  end

  describe "advance/1" do
    test "moves to the next step" do
      plan = sample_plan()
      advanced = Plan.advance(plan)
      assert advanced.current_step_index == 1
      assert Plan.next_step(advanced).action == :travel
    end
  end

  describe "complete?/1" do
    test "returns false when steps remain" do
      refute Plan.complete?(sample_plan())
    end

    test "returns true when all steps executed" do
      plan = %{sample_plan() | current_step_index: 3}
      assert Plan.complete?(plan)
    end
  end

  describe "expired?/2" do
    test "returns false before expiry" do
      refute Plan.expired?(sample_plan(), 50)
    end

    test "returns true after expiry" do
      assert Plan.expired?(sample_plan(), 200)
    end
  end
end
