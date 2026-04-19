defmodule Simulator.Agents.MarketAgent.PriceEngineTest do
  use ExUnit.Case, async: true

  alias Simulator.Agents.MarketAgent.PriceEngine

  describe "recalculate/4 — coverage model" do
    test "scarce supply (< 1 tick coverage) drives price up" do
      # 5 supply, 100 demand = 0.05 ticks coverage → strong upward
      new_price = PriceEngine.recalculate(40.0, 5, 100, 0.05)
      assert new_price > 40.0
    end

    test "tight supply (5 ticks coverage) drives price up moderately" do
      # 500 supply, 100 demand = 5 ticks coverage → moderate upward
      new_price = PriceEngine.recalculate(40.0, 500, 100, 0.05)
      assert new_price > 40.0
    end

    test "adequate supply (50 ticks coverage) keeps price stable" do
      # 5000 supply, 100 demand = 50 ticks coverage → stable
      new_price = PriceEngine.recalculate(40.0, 5000, 100, 0.05)
      assert new_price == 40.0
    end

    test "abundant supply (200+ ticks coverage) drifts price down slightly" do
      # 20000 supply, 100 demand = 200 ticks → slight downward drift
      new_price = PriceEngine.recalculate(40.0, 20_000, 100, 0.05)
      assert new_price < 40.0
      # But not a crash — should be very gentle
      assert new_price > 39.0
    end

    test "higher elasticity produces larger swings" do
      low_swing = PriceEngine.recalculate(40.0, 5, 100, 0.01)
      high_swing = PriceEngine.recalculate(40.0, 5, 100, 0.10)
      assert high_swing > low_swing
    end

    test "price has a floor of 1.0" do
      new_price = PriceEngine.recalculate(2.0, 100_000, 1, 0.50)
      assert new_price >= 1.0
    end

    test "price has a ceiling of 500" do
      new_price = PriceEngine.recalculate(400.0, 0, 10_000, 0.50)
      assert new_price <= 500.0
    end

    test "handles zero supply" do
      new_price = PriceEngine.recalculate(40.0, 0, 100, 0.05)
      assert new_price > 40.0
    end

    test "handles zero demand" do
      # Zero demand with supply = adequate coverage
      new_price = PriceEngine.recalculate(40.0, 100, 0, 0.05)
      # With demand defaulting to 1, coverage = 100 → stable
      assert_in_delta new_price, 40.0, 1.0
    end

    test "prices stabilize over many ticks with balanced supply/demand" do
      # Simulate 200 ticks with adequate coverage
      final_price =
        Enum.reduce(1..200, 40.0, fn _tick, price ->
          PriceEngine.recalculate(price, 1000, 20, 0.02)
        end)

      # Should stay near 40.0, not crash to 1.0
      assert final_price > 30.0
      assert final_price < 50.0
    end

    test "scarcity takes many ticks to reach ceiling" do
      # Simulate 50 ticks with critical shortage
      final_price =
        Enum.reduce(1..50, 40.0, fn _tick, price ->
          PriceEngine.recalculate(price, 2, 100, 0.02)
        end)

      # Should be rising but not at ceiling yet after only 50 ticks
      assert final_price > 40.0
      assert final_price < 200.0
    end
  end

  describe "urgency_multiplier/1" do
    test "returns 1.0 below the onset threshold" do
      assert PriceEngine.urgency_multiplier(0) == 1.0
      assert PriceEngine.urgency_multiplier(10) == 1.0
      assert PriceEngine.urgency_multiplier(20) == 1.0
    end

    test "scales linearly above the onset threshold" do
      assert PriceEngine.urgency_multiplier(35) > 1.0
      assert PriceEngine.urgency_multiplier(50) > PriceEngine.urgency_multiplier(35)
    end

    test "is capped at the max multiplier" do
      assert PriceEngine.urgency_multiplier(10_000) <= 4.0
    end
  end

  describe "recalculate/5 — shortage urgency" do
    test "sustained shortage amplifies upward pressure" do
      # Low coverage, same supply/demand — just different shortage duration.
      price_cold = PriceEngine.recalculate(40.0, 2, 100, 0.05, 0)
      price_warm = PriceEngine.recalculate(40.0, 2, 100, 0.05, 60)

      assert price_warm > price_cold
    end

    test "urgency does not affect downward pressure on oversupply" do
      # Massive coverage — pressure is negative.
      price_cold = PriceEngine.recalculate(40.0, 100_000, 10, 0.05, 0)
      price_warm = PriceEngine.recalculate(40.0, 100_000, 10, 0.05, 200)

      assert price_warm == price_cold
    end

    test "urgency respects the absolute ceiling" do
      # Large urgency still can't push past the ceiling.
      assert PriceEngine.recalculate(499.0, 0, 100, 0.50, 500) <= 500.0
    end

    test "shortage with urgency reaches ceiling faster than without" do
      baseline =
        Enum.reduce(1..100, 40.0, fn _t, price ->
          PriceEngine.recalculate(price, 2, 100, 0.02, 0)
        end)

      urgent =
        Enum.reduce(1..100, 40.0, fn tick, price ->
          PriceEngine.recalculate(price, 2, 100, 0.02, tick)
        end)

      assert urgent > baseline
    end
  end

  describe "apply_spread/2" do
    test "returns buy and sell prices around the base" do
      {buy, sell} = PriceEngine.apply_spread(40.0, 0.10)

      assert buy > 40.0
      assert sell < 40.0
      assert_in_delta buy, 42.0, 0.01
      assert_in_delta sell, 38.0, 0.01
    end

    test "zero spread returns identical prices" do
      {buy, sell} = PriceEngine.apply_spread(40.0, 0.0)

      assert buy == 40.0
      assert sell == 40.0
    end
  end
end
