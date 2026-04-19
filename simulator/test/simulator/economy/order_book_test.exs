defmodule Simulator.Economy.OrderBookTest do
  use ExUnit.Case, async: true

  alias Simulator.Economy.{Order, OrderBook}

  defp buy_order(attrs) do
    defaults = %{
      agent_id: "buyer",
      type: :buy,
      commodity: :ore,
      quantity: 100,
      price: 50.0,
      placed_at_tick: 1
    }

    Order.new(Map.merge(defaults, attrs))
  end

  defp sell_order(attrs) do
    defaults = %{
      agent_id: "seller",
      type: :sell,
      commodity: :ore,
      quantity: 100,
      price: 40.0,
      placed_at_tick: 1
    }

    Order.new(Map.merge(defaults, attrs))
  end

  describe "match_orders/3" do
    test "matches a buy and sell when prices cross" do
      buy = buy_order(%{price: 50.0, quantity: 100})
      sell = sell_order(%{price: 40.0, quantity: 100})

      {trades, remaining_buys, remaining_sells} = OrderBook.match_orders([buy], [sell])

      assert length(trades) == 1
      assert remaining_buys == []
      assert remaining_sells == []

      [trade] = trades
      assert trade.quantity == 100
      assert trade.buyer_id == "buyer"
      assert trade.seller_id == "seller"
      assert trade.commodity == :ore
      # Midpoint is 45.0, minus half spread (5%) = 42.75
      assert_in_delta trade.price, 42.75, 0.01
    end

    test "no match when buy price is below sell price" do
      buy = buy_order(%{price: 30.0})
      sell = sell_order(%{price: 40.0})

      {trades, remaining_buys, remaining_sells} = OrderBook.match_orders([buy], [sell])

      assert trades == []
      assert length(remaining_buys) == 1
      assert length(remaining_sells) == 1
    end

    test "partial fill when buy wants more than sell offers" do
      buy = buy_order(%{quantity: 200})
      sell = sell_order(%{quantity: 80})

      {trades, remaining_buys, remaining_sells} = OrderBook.match_orders([buy], [sell])

      assert length(trades) == 1
      assert [trade] = trades
      assert trade.quantity == 80

      assert [remaining_buy] = remaining_buys
      assert remaining_buy.quantity == 120
      assert remaining_sells == []
    end

    test "partial fill when sell offers more than buy wants" do
      buy = buy_order(%{quantity: 50})
      sell = sell_order(%{quantity: 100})

      {trades, remaining_buys, remaining_sells} = OrderBook.match_orders([buy], [sell])

      assert length(trades) == 1
      assert [trade] = trades
      assert trade.quantity == 50

      assert remaining_buys == []
      assert [remaining_sell] = remaining_sells
      assert remaining_sell.quantity == 50
    end

    test "multiple matches across several orders" do
      buys = [
        buy_order(%{agent_id: "b1", price: 55.0, quantity: 50}),
        buy_order(%{agent_id: "b2", price: 48.0, quantity: 50})
      ]

      sells = [
        sell_order(%{agent_id: "s1", price: 38.0, quantity: 30}),
        sell_order(%{agent_id: "s2", price: 42.0, quantity: 40})
      ]

      {trades, _remaining_buys, remaining_sells} = OrderBook.match_orders(buys, sells)

      # b1 (55) matches s1 (38) for 30, then s2 (42) for 20
      # b2 (48) matches remaining s2 (42) for 20
      total_traded = Enum.reduce(trades, 0, fn t, acc -> acc + t.quantity end)
      assert total_traded == 70
      assert remaining_sells == []
    end

    test "empty order book returns no trades" do
      {trades, remaining_buys, remaining_sells} = OrderBook.match_orders([], [])

      assert trades == []
      assert remaining_buys == []
      assert remaining_sells == []
    end

    test "buys with no sells returns all buys as remaining" do
      buys = [buy_order(%{})]

      {trades, remaining_buys, remaining_sells} = OrderBook.match_orders(buys, [])

      assert trades == []
      assert length(remaining_buys) == 1
      assert remaining_sells == []
    end

    test "custom spread affects trade price" do
      buy = buy_order(%{price: 50.0, quantity: 100})
      sell = sell_order(%{price: 40.0, quantity: 100})

      # Zero spread — trade at exact midpoint
      {[trade], _, _} = OrderBook.match_orders([buy], [sell], 0.0)
      assert_in_delta trade.price, 45.0, 0.01

      # 20% spread
      {[trade], _, _} = OrderBook.match_orders([buy], [sell], 0.20)
      assert_in_delta trade.price, 40.5, 0.01
    end
  end
end
