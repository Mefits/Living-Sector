defmodule Simulator.Economy.OrderBook do
  @moduledoc """
  Pure functional order matching engine.

  Matches buy and sell orders for a single commodity. Buy orders are matched
  against sell orders when the buyer's max price meets or exceeds the seller's
  min price. Trades execute at the midpoint price minus the market spread.

  This module contains no side effects — it takes orders in and returns
  matched trades plus remainders. The `Simulator.Agents.MarketAgent` calls
  this each tick to clear its order book.
  """

  alias Simulator.Economy.Order

  @type trade :: %{
          buyer_id: String.t(),
          seller_id: String.t(),
          commodity: atom(),
          quantity: pos_integer(),
          price: float(),
          total_cost: float()
        }

  @doc """
  Matches buy and sell orders for a commodity, returning executed trades
  and any remaining unmatched orders.

  Buy orders are sorted by max price descending (most aggressive first).
  Sell orders are sorted by min price ascending (cheapest first).
  A match occurs when `buy.price >= sell.price`. The trade executes at
  the midpoint: `(buy.price + sell.price) / 2`, minus the spread.

  Partial fills are supported — if a buy order wants 100 units but the
  cheapest sell only has 50, the buy is partially filled and remains in
  the book with reduced quantity.

  ## Parameters

    * `buy_orders` - list of `%Order{type: :buy}` structs
    * `sell_orders` - list of `%Order{type: :sell}` structs
    * `spread` - market's cut as a fraction (e.g., 0.10 for 10%)

  ## Returns

  A tuple of `{trades, remaining_buys, remaining_sells}`.

  ## Examples

      iex> buy = %Order{id: 1, agent_id: "ship1", type: :buy, commodity: :ore, quantity: 100, price: 50.0, placed_at_tick: 1}
      iex> sell = %Order{id: 2, agent_id: "miner", type: :sell, commodity: :ore, quantity: 100, price: 40.0, placed_at_tick: 1}
      iex> {trades, remaining_buys, remaining_sells} = OrderBook.match_orders([buy], [sell], 0.10)
      iex> length(trades)
      1
      iex> remaining_buys
      []
      iex> remaining_sells
      []
  """
  @spec match_orders([Order.t()], [Order.t()], float()) ::
          {[trade()], [Order.t()], [Order.t()]}
  def match_orders(buy_orders, sell_orders, spread \\ 0.10) do
    buys = Enum.sort_by(buy_orders, & &1.price, :desc)
    sells = Enum.sort_by(sell_orders, & &1.price, :asc)

    do_match(buys, sells, spread, [])
  end

  defp do_match([], sells, _spread, trades) do
    {Enum.reverse(trades), [], sells}
  end

  defp do_match(buys, [], _spread, trades) do
    {Enum.reverse(trades), buys, []}
  end

  defp do_match([buy | rest_buys], [sell | rest_sells], spread, trades) do
    if buy.price >= sell.price do
      midpoint = (buy.price + sell.price) / 2
      trade_price = midpoint * (1 - spread / 2)
      trade_qty = min(buy.quantity, sell.quantity)

      trade = %{
        buyer_id: buy.agent_id,
        seller_id: sell.agent_id,
        commodity: buy.commodity,
        quantity: trade_qty,
        price: trade_price,
        total_cost: trade_price * trade_qty
      }

      remaining_buy_qty = buy.quantity - trade_qty
      remaining_sell_qty = sell.quantity - trade_qty

      next_buys =
        if remaining_buy_qty > 0,
          do: [%{buy | quantity: remaining_buy_qty} | rest_buys],
          else: rest_buys

      next_sells =
        if remaining_sell_qty > 0,
          do: [%{sell | quantity: remaining_sell_qty} | rest_sells],
          else: rest_sells

      do_match(next_buys, next_sells, spread, [trade | trades])
    else
      # Best buy can't meet cheapest sell — no more matches possible
      {Enum.reverse(trades), [buy | rest_buys], [sell | rest_sells]}
    end
  end
end
