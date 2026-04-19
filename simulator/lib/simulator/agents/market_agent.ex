defmodule Simulator.Agents.MarketAgent do
  @moduledoc """
  Runs a local market at a facility.

  Each facility has one MarketAgent that collects buy/sell orders from ships
  and other agents, matches them via `Simulator.Economy.OrderBook`, adjusts
  prices based on supply and demand, and broadcasts updated prices through
  the event bus.

  Markets are the economic heartbeat of the simulation. Prices are not
  arbitrary — they emerge from supply and demand each tick.

  ## Reserved Goods

  Markets support a **reserved goods** ledger for remote purchasing.
  Facilities can buy goods at remote markets — the goods are moved from
  supply to `reserved_goods` and held until a trucker ship picks them up
  or the reservation expires (200 ticks). This enables the delivery
  contract system where facilities are economic principals and ships
  are logistics agents.

  ## Tick Cycle

  Each tick, the market executes these phases in order:

  1. **Production** — add local production output to supply
  2. **Consumption** — subtract local consumption from supply (PopAgent demand)
  3. **Emergency orders** — place large premium buy orders for essentials at critical supply
  4. **Order matching** — match pending buy/sell orders via `OrderBook`
  5. **Price update** — recalculate prices from post-trade supply/demand
  6. **Broadcast** — publish updated prices to the event bus
  7. **Cleanup** — expire old unmatched orders and expired reserves
  """

  use Simulator.Agents.Agent

  alias Simulator.Agents.MarketAgent.PriceEngine
  alias Simulator.Economy.{Order, OrderBook}
  alias Simulator.Schemas

  alias Simulator.Simulation.Config

  @base_order_expiry 50 * Config.tick_multiplier()
  @reserve_expiry_ticks 200 * Config.tick_multiplier()

  # Rolling consumption window (ticks). Demand is recomputed each tick as the
  # sum of recent consumption over this window × `@demand_lookahead_factor`.
  @demand_window_ticks 100 * Config.tick_multiplier()
  @demand_lookahead_factor 1.0
  # Below this window age, we trust the JSON-seeded demand as a cold-start
  # floor so prices don't collapse while the rolling window fills up.
  @demand_warmup_ticks 50 * Config.tick_multiplier()

  # Per-commodity shortage tracking. A commodity is "in shortage" when its
  # supply is below a low fraction of its demand — this feeds a per-commodity
  # urgency multiplier that PriceEngine uses to widen the per-tick elasticity
  # cap, letting prices actually climb under sustained scarcity.
  @shortage_supply_ratio 0.1
  @shortage_min_floor 10

  # --- Public API ---

  @doc """
  Returns current prices for all commodities at this market.
  """
  @spec query_prices(pid()) :: %{atom() => float()}
  def query_prices(pid) do
    GenServer.call(pid, :query_prices)
  end

  @doc """
  Places a buy order on this market.

  Returns `{:ok, order_id}` if the order was accepted.
  """
  @spec place_buy_order(pid(), map()) :: {:ok, integer()}
  def place_buy_order(pid, attrs) do
    GenServer.call(pid, {:place_order, :buy, attrs})
  end

  @doc """
  Places a sell order on this market.

  Returns `{:ok, order_id}` if the order was accepted.
  """
  @spec place_sell_order(pid(), attrs :: map()) :: {:ok, integer()}
  def place_sell_order(pid, attrs) do
    GenServer.call(pid, {:place_order, :sell, attrs})
  end

  @doc """
  Reserves goods that have been purchased remotely.

  Moves goods from supply to a reserved ledger. The goods are held
  until a ship picks them up or the reservation expires.

  Returns `{:ok, reserve_id}` or `{:error, :insufficient_supply}`.
  """
  @spec reserve_goods(pid(), map()) :: {:ok, String.t()} | {:error, atom()}
  def reserve_goods(pid, attrs) do
    GenServer.call(pid, {:reserve_goods, attrs})
  end

  @doc """
  Ship picks up reserved goods. Removes from the reserve ledger.

  Returns `{:ok, commodity, quantity}` or `{:error, reason}`.
  """
  @spec pickup_reserved(pid(), String.t(), String.t()) ::
          {:ok, atom(), non_neg_integer()} | {:error, atom()}
  def pickup_reserved(pid, reserve_id, ship_id) do
    GenServer.call(pid, {:pickup_reserved, reserve_id, ship_id})
  end

  @doc """
  Returns reserved goods to supply. Used for expiry or cancellation.
  """
  @spec release_reserved(pid(), String.t()) :: :ok | {:error, atom()}
  def release_reserved(pid, reserve_id) do
    GenServer.call(pid, {:release_reserved, reserve_id})
  end

  @doc """
  Returns all reserved goods for a given owner.
  """
  @spec query_reserved(pid(), String.t()) :: [map()]
  def query_reserved(pid, owner_id) do
    GenServer.call(pid, {:query_reserved, owner_id})
  end

  @doc """
  Returns current supply levels for all commodities.
  """
  @spec get_supply(pid()) :: %{atom() => number()}
  def get_supply(pid) do
    GenServer.call(pid, :get_supply)
  end

  @doc """
  Atomically adjusts supply by the given per-commodity deltas.

  Unlike `update_supply`, this merges additively — concurrent calls
  from multiple facilities won't overwrite each other. Positive deltas
  add (extraction / production / deliveries). Negative deltas subtract
  (admin-driven removal, leakage). Supply is floored at 0 so a delta
  larger than the current supply just zeros out rather than going
  negative.
  """
  @spec add_supply(pid(), %{atom() => number()}) :: :ok
  def add_supply(pid, additions) do
    GenServer.cast(pid, {:add_supply, additions})
  end

  @doc """
  Atomically consumes inputs and adds outputs in one operation.

  Used by facility recipe execution to avoid the read-modify-write
  race condition that would occur with separate read + update calls.
  """
  @spec consume_and_produce(pid(), %{atom() => number()}, %{atom() => number()}) :: :ok
  def consume_and_produce(pid, consumed, produced) do
    GenServer.cast(pid, {:consume_and_produce, consumed, produced})
  end

  @doc """
  Records demand pressure for a commodity without moving supply.

  Used by contract escalation and other upstream signals that represent
  unmet demand the market wouldn't otherwise see (a facility wants to
  buy X units but no ship has delivered yet). The amount is added to
  the rolling consumption window so it feeds back into dynamic demand
  and, if sustained, into shortage urgency.
  """
  @spec bump_demand(pid(), atom(), number()) :: :ok
  def bump_demand(pid, commodity, quantity) when is_atom(commodity) and is_number(quantity) do
    GenServer.cast(pid, {:bump_demand, commodity, quantity})
  end

  @doc """
  Returns the full market state. Used by the dashboard inspector.
  """
  @spec get_state(pid()) :: map()
  def get_state(pid) do
    GenServer.call(pid, :get_state)
  end

  # --- Agent Callbacks ---

  @impl Simulator.Agents.Agent
  def agent_type, do: :market

  @impl Simulator.Agents.Agent
  def init_agent(config) do
    # Compute distance-based order expiry: base + longest reachable travel time
    order_expiry = compute_order_expiry(config.facility_id)

    initial_demand = config[:demand] || %{ore: 20, fuel: 50, food: 100}

    state = %{
      id: config.id,
      facility_id: config.facility_id,
      prices: config[:prices] || default_prices(),
      supply: config[:supply] || %{ore: 500, fuel: 500, food: 500},
      demand: initial_demand,
      # Seed demand carried for the warmup window so cold-start prices don't
      # collapse while the rolling consumption window fills.
      seed_demand: initial_demand,
      production: config[:production] || %{ore: 0, fuel: 0, food: 0},
      consumption: config[:consumption] || %{ore: 0, fuel: 0, food: 0},
      # Rolling list of {tick, qty} entries per commodity — trimmed each tick.
      consumption_window: %{},
      # Per-commodity count of consecutive ticks in shortage.
      shortage_ticks: %{},
      # Tick the agent booted at, used to detect the demand warmup window.
      spawned_at_tick: nil,
      pending_buy_orders: config[:pending_buy_orders] || [],
      pending_sell_orders: config[:pending_sell_orders] || [],
      reserved_goods: %{},
      next_reserve_id: 1,
      price_history: config[:price_history] || %{},
      trade_volume: config[:trade_volume] || %{},
      # Elasticity scales by 1/tps only — price responsiveness is wall-clock, not game-pace
      price_elasticity: (config[:price_elasticity] || 0.05) / Config.ticks_per_second(),
      spread: config[:spread] || 0.10,
      order_expiry_ticks: order_expiry,
      last_tick: 0,
      __db_id__: config[:db_id],
      __agent_type__: :market
    }

    {:ok, state}
  end

  @impl Simulator.Agents.Agent
  def handle_tick(tick, state) do
    state =
      state
      |> Map.put(:last_tick, tick)
      |> Map.update(:spawned_at_tick, tick, &(&1 || tick))
      |> phase_production(tick)
      |> phase_consumption(tick)
      |> phase_emergency_orders(tick)
      |> phase_surplus_orders(tick)
      |> phase_match_orders(tick)
      |> phase_update_demand(tick)
      |> phase_track_shortage()
      |> phase_update_prices()
      |> phase_broadcast(tick)
      |> phase_expire_orders(tick)
      |> phase_expire_reserves(tick)
      |> mark_dirty()

    {:ok, state}
  end

  @impl Simulator.Agents.Agent
  def persist_state(state) do
    if db_id = state[:__db_id__] do
      # Convert atom keys to string keys for JSONB storage
      string_prices = stringify_keys(state.prices)
      string_supply = stringify_keys(state.supply)
      string_demand = stringify_keys(state.demand)
      string_production = stringify_keys(state.production)
      string_consumption = stringify_keys(state.consumption)

      Simulator.Repo.get!(Schemas.Market, db_id)
      |> Schemas.Market.changeset(%{
        prices: string_prices,
        supply: string_supply,
        demand: string_demand,
        production: string_production,
        consumption: string_consumption,
        price_elasticity: state.price_elasticity,
        spread: state.spread,
        state: %{
          "price_history" => stringify_nested_keys(state.price_history),
          "trade_volume" => stringify_keys(state.trade_volume),
          "reserved_goods" => stringify_nested_keys(state.reserved_goods),
          "pending_buy_orders" => serialize_orders(state.pending_buy_orders),
          "pending_sell_orders" => serialize_orders(state.pending_sell_orders),
          "last_tick" => state.last_tick
        }
      })
      |> Simulator.Repo.update!()
    end

    :ok
  end

  # --- GenServer Call Handlers ---

  @impl GenServer
  def handle_call(:query_prices, _from, state) do
    {:reply, state.prices, state}
  end

  def handle_call({:place_order, type, attrs}, _from, state) do
    order =
      Order.new(%{
        agent_id: attrs.agent_id,
        type: type,
        commodity: attrs.commodity,
        quantity: attrs.quantity,
        price: attrs.price,
        placed_at_tick: state.last_tick
      })

    state =
      case type do
        :buy ->
          %{state | pending_buy_orders: [order | state.pending_buy_orders]}

        :sell ->
          %{state | pending_sell_orders: [order | state.pending_sell_orders]}
      end

    {:reply, {:ok, order.id}, state}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  def handle_call(:get_supply, _from, state) do
    {:reply, state.supply, state}
  end

  def handle_call({:reserve_goods, attrs}, _from, state) do
    commodity = attrs.commodity
    quantity = attrs.quantity
    available = Map.get(state.supply, commodity, 0)

    if available >= quantity do
      reserve_id = "reserve-#{state.id}-#{state.next_reserve_id}"

      reserve = %{
        id: reserve_id,
        commodity: commodity,
        quantity: quantity,
        owner_id: attrs.owner_id,
        reserved_at_tick: attrs[:tick] || state.last_tick,
        expiry_tick: (attrs[:tick] || state.last_tick) + @reserve_expiry_ticks
      }

      new_supply = Map.update!(state.supply, commodity, &(&1 - quantity))
      new_reserved = Map.put(state.reserved_goods, reserve_id, reserve)

      state = %{
        state
        | supply: new_supply,
          reserved_goods: new_reserved,
          next_reserve_id: state.next_reserve_id + 1
      }

      {:reply, {:ok, reserve_id}, state}
    else
      {:reply, {:error, :insufficient_supply}, state}
    end
  end

  def handle_call({:pickup_reserved, reserve_id, _ship_id}, _from, state) do
    case Map.pop(state.reserved_goods, reserve_id) do
      {nil, _} ->
        {:reply, {:error, :not_found}, state}

      {reserve, remaining} ->
        state = %{state | reserved_goods: remaining}
        {:reply, {:ok, reserve.commodity, reserve.quantity}, state}
    end
  end

  def handle_call({:release_reserved, reserve_id}, _from, state) do
    case Map.pop(state.reserved_goods, reserve_id) do
      {nil, _} ->
        {:reply, {:error, :not_found}, state}

      {reserve, remaining} ->
        new_supply =
          Map.update(state.supply, reserve.commodity, reserve.quantity, &(&1 + reserve.quantity))

        state = %{state | reserved_goods: remaining, supply: new_supply}
        {:reply, :ok, state}
    end
  end

  def handle_call({:query_reserved, owner_id}, _from, state) do
    reserves =
      state.reserved_goods
      |> Map.values()
      |> Enum.filter(&(&1.owner_id == owner_id))

    {:reply, reserves, state}
  end

  @impl GenServer
  def handle_cast({:add_supply, additions}, state) do
    merged =
      Enum.reduce(additions, state.supply, fn {commodity, delta}, acc ->
        # Floor at 0 so negative deltas (admin removals) can't
        # drive supply below zero, and unfamiliar commodities don't
        # materialize as negative ledgers.
        Map.update(acc, commodity, max(delta, 0), fn current ->
          max(current + delta, 0)
        end)
      end)

    new_prices = ensure_prices_exist(merged, state.prices)
    {:noreply, %{state | supply: merged, prices: new_prices}}
  end

  def handle_cast({:consume_and_produce, consumed, produced}, state) do
    after_consume =
      Enum.reduce(consumed, state.supply, fn {commodity, amount}, supply ->
        Map.update(supply, commodity, 0, &max(&1 - amount, 0))
      end)

    after_produce =
      Map.merge(after_consume, produced, fn _k, old, new -> old + new end)

    new_prices = ensure_prices_exist(after_produce, state.prices)

    state =
      Enum.reduce(consumed, state, fn {commodity, qty}, acc ->
        record_consumption(acc, commodity, qty)
      end)

    {:noreply, %{state | supply: after_produce, prices: new_prices}}
  end

  def handle_cast({:bump_demand, commodity, quantity}, state) do
    {:noreply, record_consumption(state, commodity, quantity)}
  end

  def handle_cast({:update_supply, new_supply}, state) do
    # Legacy: full replacement merge. Prefer add_supply/consume_and_produce
    # for concurrent-safe operations.
    merged =
      Map.merge(state.supply, new_supply, fn _k, _old, new -> new end)

    new_prices = ensure_prices_exist(merged, state.prices)
    {:noreply, %{state | supply: merged, prices: new_prices}}
  end

  # --- Tick Phases ---

  # Production/consumption runs on an interval — amounts are per-cycle, not per-tick
  @prod_cons_interval 5 * Config.tick_multiplier()

  defp phase_production(state, tick) when rem(tick, @prod_cons_interval) == 0 do
    supply =
      Enum.reduce(state.production, state.supply, fn {commodity, amount}, acc ->
        Map.update(acc, commodity, amount, &(&1 + amount))
      end)

    %{state | supply: supply}
  end

  defp phase_production(state, _tick), do: state

  defp phase_consumption(state, tick) when rem(tick, @prod_cons_interval) == 0 do
    supply =
      Enum.reduce(state.consumption, state.supply, fn {commodity, amount}, acc ->
        Map.update(acc, commodity, 0, &max(&1 - amount, 0))
      end)

    # Broadcast shortage alerts for any commodity that hit zero
    Enum.each(supply, fn {commodity, qty} ->
      if qty == 0 and Map.get(state.supply, commodity, 0) > 0 do
        alert = %{facility_id: state.facility_id, commodity: commodity, tick: state.last_tick}
        Simulator.Events.broadcast("market:#{state.facility_id}", :shortage_alert, alert)
        Simulator.Events.log(:shortage_alert, alert)
      end
    end)

    state =
      Enum.reduce(state.consumption, state, fn {commodity, qty}, acc ->
        record_consumption(acc, commodity, qty)
      end)

    %{state | supply: supply}
  end

  defp phase_consumption(state, _tick), do: state

  # Essential commodities that markets will aggressively buy when supply is low.
  # Maps commodity to: {critical_threshold, order_quantity, premium_multiplier}
  @essential_commodities %{
    fuel: {50, 500, 1.5},
    food: {50, 300, 1.5},
    water: {30, 200, 1.3},
    metals: {30, 200, 1.3},
    tools: {20, 100, 1.4},
    ore: {50, 300, 1.2},
    ice: {50, 300, 1.2}
  }

  @emergency_order_interval 10 * Config.tick_multiplier()

  defp phase_emergency_orders(state, tick) when rem(tick, @emergency_order_interval) == 0 do
    Enum.reduce(@essential_commodities, state, fn {commodity, {threshold, qty, premium}}, acc ->
      supply = Map.get(acc.supply, commodity, 0)
      demand = Map.get(acc.demand, commodity, 0)

      if supply < threshold and demand > 0 do
        # Check if we already have an emergency buy order for this commodity
        has_emergency =
          Enum.any?(acc.pending_buy_orders, fn order ->
            order.commodity == commodity and order.agent_id == "market-emergency"
          end)

        if not has_emergency do
          price = Map.get(acc.prices, commodity, 50.0) * premium

          order =
            Order.new(%{
              agent_id: "market-emergency",
              type: :buy,
              commodity: commodity,
              quantity: qty,
              price: price,
              placed_at_tick: tick
            })

          %{acc | pending_buy_orders: [order | acc.pending_buy_orders]}
        else
          acc
        end
      else
        acc
      end
    end)
  end

  defp phase_emergency_orders(state, _tick), do: state

  # Post sell orders when supply exceeds demand significantly.
  # This creates visible price signals so traders know where cheap goods are.
  @surplus_threshold_multiplier 5
  @surplus_discount 0.8

  defp phase_surplus_orders(state, tick) when rem(tick, @emergency_order_interval) == 0 do
    Enum.reduce(Map.keys(state.supply), state, fn commodity, acc ->
      supply = Map.get(acc.supply, commodity, 0)
      demand = Map.get(acc.demand, commodity, 0)
      # Surplus = supply is 5x demand (or > 500 if no demand)
      surplus_threshold = max(demand * @surplus_threshold_multiplier, 500)

      if supply > surplus_threshold do
        has_surplus_order =
          Enum.any?(acc.pending_sell_orders, fn order ->
            order.commodity == commodity and order.agent_id == "market-surplus"
          end)

        if not has_surplus_order do
          price = Map.get(acc.prices, commodity, 10.0) * @surplus_discount
          # Offer up to 20% of excess supply
          excess = supply - div(surplus_threshold, 2)
          qty = min(round(excess * 0.2), 500)

          if qty > 0 do
            order =
              Order.new(%{
                agent_id: "market-surplus",
                type: :sell,
                commodity: commodity,
                quantity: qty,
                price: price,
                placed_at_tick: tick
              })

            %{acc | pending_sell_orders: [order | acc.pending_sell_orders]}
          else
            acc
          end
        else
          acc
        end
      else
        acc
      end
    end)
  end

  defp phase_surplus_orders(state, _tick), do: state

  defp phase_match_orders(state, _tick) do
    commodities = Map.keys(state.prices)

    Enum.reduce(commodities, state, fn commodity, acc ->
      buys = Enum.filter(acc.pending_buy_orders, &(&1.commodity == commodity))
      sells = Enum.filter(acc.pending_sell_orders, &(&1.commodity == commodity))

      {trades, remaining_buys, remaining_sells} =
        OrderBook.match_orders(buys, sells, acc.spread)

      # Update supply based on trades.
      # Normal buyers: goods leave the market (supply decreases)
      # Emergency market buys: goods STAY at the market (supply increases — market restocking)
      {supply_change, consumed_qty} =
        Enum.reduce(trades, {0, 0}, fn trade, {supply_sum, consumed_sum} ->
          if trade.buyer_id == "market-emergency" do
            # Market bought to restock — goods come IN from the seller
            {supply_sum - trade.quantity, consumed_sum}
          else
            # Normal buyer — goods leave the market (real consumption signal)
            {supply_sum + trade.quantity, consumed_sum + trade.quantity}
          end
        end)

      supply =
        Map.update(acc.supply, commodity, 0, &max(&1 - supply_change, 0))

      # Track trade volume
      trade_volume =
        Map.put(acc.trade_volume, commodity, supply_change)

      acc = record_consumption(acc, commodity, consumed_qty)

      # Notify agents and route payments
      spread_revenue =
        Enum.reduce(trades, 0, fn trade, sum ->
          trade_event = %{
            buyer_id: trade.buyer_id,
            seller_id: trade.seller_id,
            commodity: commodity,
            quantity: trade.quantity,
            price: trade.price
          }

          Simulator.Events.broadcast("market:#{acc.facility_id}", :trade_executed, trade_event)
          Simulator.Events.log(:trade_executed, trade_event)

          # Market spread goes to the facility
          sum + round(trade.quantity * trade.price * acc.spread / 2)
        end)

      # Send spread revenue to the facility
      if spread_revenue > 0 do
        case Simulator.Agents.Agent.whereis("facility-#{acc.facility_id}") do
          {:ok, pid} -> GenServer.cast(pid, {:market_revenue, spread_revenue})
          :error -> :ok
        end
      end

      # Replace orders for this commodity with remainders, keep orders for other commodities
      other_buys = Enum.reject(acc.pending_buy_orders, &(&1.commodity == commodity))
      other_sells = Enum.reject(acc.pending_sell_orders, &(&1.commodity == commodity))

      %{
        acc
        | supply: supply,
          trade_volume: trade_volume,
          pending_buy_orders: remaining_buys ++ other_buys,
          pending_sell_orders: remaining_sells ++ other_sells
      }
    end)
  end

  defp phase_update_demand(state, tick) do
    cutoff = tick - @demand_window_ticks

    # Trim entries older than the window, then sum remaining qty per commodity.
    trimmed =
      Map.new(state.consumption_window, fn {commodity, entries} ->
        kept = Enum.reject(entries, fn {entry_tick, _qty} -> entry_tick < cutoff end)
        {commodity, kept}
      end)

    observed =
      Map.new(trimmed, fn {commodity, entries} ->
        {commodity, Enum.reduce(entries, 0, fn {_t, q}, acc -> acc + q end)}
      end)

    warming_up? = tick - (state.spawned_at_tick || tick) < @demand_warmup_ticks

    # Combine commodities from both seed and observed maps so newly-consumed
    # commodities that weren't in the JSON seed still get a demand entry.
    commodities =
      state.seed_demand
      |> Map.keys()
      |> Kernel.++(Map.keys(observed))
      |> Enum.uniq()

    demand =
      Map.new(commodities, fn commodity ->
        observed_qty = Map.get(observed, commodity, 0)
        projected = round(observed_qty * @demand_lookahead_factor)
        seed = Map.get(state.seed_demand, commodity, 0)

        value =
          cond do
            warming_up? -> max(projected, seed)
            projected > 0 -> projected
            true -> seed
          end

        {commodity, value}
      end)

    %{state | consumption_window: trimmed, demand: demand}
  end

  defp phase_track_shortage(state) do
    shortage_ticks =
      Enum.reduce(state.prices, state.shortage_ticks, fn {commodity, _price}, acc ->
        supply = Map.get(state.supply, commodity, 0)
        demand = Map.get(state.demand, commodity, 0)
        threshold = max(demand * @shortage_supply_ratio, @shortage_min_floor)

        if supply < threshold and demand > 0 do
          Map.update(acc, commodity, 1, &(&1 + 1))
        else
          Map.put(acc, commodity, 0)
        end
      end)

    %{state | shortage_ticks: shortage_ticks}
  end

  defp phase_update_prices(state) do
    prices =
      Map.new(state.prices, fn {commodity, current_price} ->
        supply = Map.get(state.supply, commodity, 0)
        demand = Map.get(state.demand, commodity, 1)
        urgency = Map.get(state.shortage_ticks, commodity, 0)

        new_price =
          PriceEngine.recalculate(
            current_price,
            supply,
            demand,
            state.price_elasticity,
            urgency
          )

        {commodity, new_price}
      end)

    # Record price history (keep last 100 entries per commodity)
    price_history =
      Map.new(prices, fn {commodity, price} ->
        history = Map.get(state.price_history, commodity, [])
        {commodity, Enum.take([price | history], 100)}
      end)

    %{state | prices: prices, price_history: price_history}
  end

  defp phase_broadcast(state, tick) do
    Simulator.Events.broadcast("market:#{state.facility_id}", :price_update, %{
      facility_id: state.facility_id,
      prices: state.prices,
      supply: state.supply,
      demand: state.demand,
      shortage_ticks: state.shortage_ticks,
      tick: tick
    })

    state
  end

  defp record_consumption(state, _commodity, qty) when qty <= 0, do: state

  defp record_consumption(state, commodity, qty) when is_atom(commodity) do
    tick = state.last_tick
    entry = {tick, qty}

    window =
      Map.update(state.consumption_window, commodity, [entry], fn entries ->
        [entry | entries]
      end)

    %{state | consumption_window: window}
  end

  defp record_consumption(state, commodity, qty) when is_binary(commodity) do
    record_consumption(state, String.to_existing_atom(commodity), qty)
  rescue
    ArgumentError -> state
  end

  defp record_consumption(state, _commodity, _qty), do: state

  defp phase_expire_orders(state, tick) do
    expiry = state.order_expiry_ticks

    %{
      state
      | pending_buy_orders:
          Enum.reject(state.pending_buy_orders, &order_expired?(&1, tick, expiry)),
        pending_sell_orders:
          Enum.reject(state.pending_sell_orders, &order_expired?(&1, tick, expiry))
    }
  end

  defp order_expired?(order, current_tick, default_expiry) do
    # Use per-order expiry if set, otherwise market default
    expiry = order.expiry_tick || order.placed_at_tick + default_expiry
    current_tick >= expiry
  end

  defp phase_expire_reserves(state, tick) do
    {expired, remaining} =
      Map.split_with(state.reserved_goods, fn {_id, reserve} ->
        tick >= reserve.expiry_tick
      end)

    if map_size(expired) == 0 do
      state
    else
      # Return expired goods to supply
      restored_supply =
        Enum.reduce(expired, state.supply, fn {_id, reserve}, supply ->
          Map.update(supply, reserve.commodity, reserve.quantity, &(&1 + reserve.quantity))
        end)

      # Broadcast expiry events so requestors know
      Enum.each(expired, fn {_id, reserve} ->
        Simulator.Events.broadcast("market:#{state.facility_id}", :reserve_expired, %{
          reserve_id: reserve.id,
          owner_id: reserve.owner_id,
          commodity: reserve.commodity,
          quantity: reserve.quantity,
          tick: tick
        })
      end)

      %{state | reserved_goods: remaining, supply: restored_supply}
    end
  end

  # Compute order expiry based on remoteness: base + max travel time to any reachable location
  defp compute_order_expiry(facility_id) do
    max_travel =
      Simulator.World.Travel.reachable_from(facility_id)
      |> Enum.map(fn dest ->
        case Simulator.World.Travel.travel_time(facility_id, dest) do
          {:ok, t} -> t
          _ -> 0
        end
      end)
      |> Enum.max(fn -> 0 end)

    # Remote markets get more time: base 200 + longest route
    # Earth (~80t max) → 280t, Tau Ceti outpost (~400t max) → 600t
    @base_order_expiry + max_travel
  end

  defp default_prices do
    Map.new(Simulator.Economy.Commodities.all(), fn c ->
      {c, Simulator.Economy.Commodities.base_price(c)}
    end)
  end

  defp ensure_prices_exist(supply, prices) do
    Enum.reduce(supply, prices, fn {commodity, _qty}, acc ->
      if Map.has_key?(acc, commodity) do
        acc
      else
        Map.put(acc, commodity, Simulator.Economy.Commodities.base_price(commodity))
      end
    end)
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  defp stringify_nested_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  defp serialize_orders(orders) do
    Enum.map(orders, fn o ->
      %{
        "agent_id" => o.agent_id,
        "type" => to_string(o.type),
        "commodity" => to_string(o.commodity),
        "quantity" => o.quantity,
        "price" => o.price,
        "placed_at_tick" => o.placed_at_tick,
        "expiry_tick" => o.expiry_tick
      }
    end)
  end

  @doc false
  def deserialize_orders(nil), do: []

  def deserialize_orders(orders) when is_list(orders) do
    Enum.map(orders, fn o ->
      Simulator.Economy.Order.new(%{
        agent_id: o["agent_id"],
        type: String.to_existing_atom(o["type"]),
        commodity: String.to_existing_atom(o["commodity"]),
        quantity: o["quantity"],
        price: o["price"],
        placed_at_tick: o["placed_at_tick"],
        expiry_tick: o["expiry_tick"]
      })
    end)
  end
end
