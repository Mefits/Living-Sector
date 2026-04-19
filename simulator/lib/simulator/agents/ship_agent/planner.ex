defmodule Simulator.Agents.ShipAgent.Planner do
  @moduledoc """
  Pure functional trade route planning for ships.

  Generates candidate plans based on the ship's known prices, current
  cargo, fuel level, and credits. Scores each plan by expected profit
  minus fuel and time costs, and picks the best one.

  Price memory is intentionally stale — ships only know prices from
  the last time they visited a location. This creates natural arbitrage,
  trade risk, and emergent information networks.
  """

  alias Simulator.Agents.ShipAgent.{Plan, PlanStep}
  alias Simulator.World.Travel

  @plan_duration_ticks 150

  @doc """
  Generates the best plan for a ship given its current state.

  Returns a `%Plan{}` — if no profitable plan exists and `:allow_break_even`
  is set, the best break-even plan is returned so idle ships have a low-margin
  fallback instead of oscillating. Without that option, returns an idle plan.

  ## Options

    * `:allow_break_even` — if true, accept plans with `expected_profit >= 0`
      (but > a minimum floor) when no profitable plan exists

  ## Parameters

    * `ship_state` - the ship's full GenServer state
    * `current_tick` - the current simulation tick
    * `opts` - optional keyword list
  """
  @spec best_plan(map(), non_neg_integer(), keyword()) :: Plan.t()
  def best_plan(ship_state, current_tick, opts \\ []) do
    allow_break_even = Keyword.get(opts, :allow_break_even, false)
    candidates = generate_plans(ship_state, current_tick, include_break_even: allow_break_even)

    case Enum.sort_by(candidates, & &1.expected_profit, :desc) do
      [best | _] when best.expected_profit > 0 ->
        best

      [best | _] when allow_break_even and best.expected_profit > -100 ->
        best

      _ ->
        idle_plan(current_tick)
    end
  end

  @doc """
  Generates all candidate trade run plans from the ship's current location.

  For each reachable destination and each commodity, evaluates whether
  buying here and selling there (or vice versa) would be profitable.
  """
  @spec generate_plans(map(), non_neg_integer(), keyword()) :: [Plan.t()]
  def generate_plans(ship_state, current_tick, opts \\ []) do
    location = ship_state.location

    if location == nil do
      []
    else
      ctx =
        ship_state
        |> build_context(current_tick)
        |> Map.put(:include_break_even, Keyword.get(opts, :include_break_even, false))

      generate_for_destinations(ctx)
    end
  end

  defp build_context(ship_state, tick) do
    raw_prices = ship_state.memory.known_prices

    %{
      location: ship_state.location,
      known_prices: raw_prices,
      local_prices: extract_prices(Map.get(raw_prices, ship_state.location, %{})),
      fuel: ship_state.fuel,
      fuel_rate: ship_state.fuel_consumption_rate,
      credits: ship_state.credits,
      cargo_space: ship_state.cargo_capacity - cargo_total(ship_state.cargo),
      safety_weight: get_in(ship_state, [:personality, :safety]) || 0.5,
      tick: tick
    }
  end

  # Extract plain price values from stamped or plain price maps
  defp extract_prices(price_map) do
    Map.new(price_map, fn
      {commodity, %{price: price}} -> {commodity, price}
      {commodity, price} when is_number(price) -> {commodity, price}
    end)
  end

  defp generate_for_destinations(ctx) do
    Travel.reachable_from(ctx.location)
    |> Enum.flat_map(fn dest ->
      case resolve_travel_time(ctx.location, dest) do
        {:ok, distance} ->
          fuel_needed = Travel.fuel_cost(distance, ctx.fuel_rate)

          if fuel_needed > ctx.fuel * 0.9 do
            []
          else
            raw_dest_prices = Map.get(ctx.known_prices, dest, %{})
            dest_ctx = Map.merge(ctx, %{dest: dest, distance: distance})
            dest_ctx = Map.put(dest_ctx, :dest_prices, extract_prices(raw_dest_prices))
            build_trade_plans(dest_ctx)
          end

        {:error, _} ->
          []
      end
    end)
  end

  defp build_trade_plans(ctx) do
    Simulator.Economy.Commodities.all()
    |> Enum.flat_map(fn commodity ->
      buy_here_sell_there(ctx, commodity) ++ buy_there_sell_here(ctx, commodity)
    end)
  end

  defp buy_here_sell_there(ctx, commodity) do
    buy_price = Map.get(ctx.local_prices, commodity)
    sell_price = Map.get(ctx.dest_prices, commodity)

    with true <- buy_price != nil and sell_price != nil and sell_price > buy_price,
         plan <- make_plan(:forward, ctx, commodity, buy_price, sell_price) do
      plan
    else
      _ -> []
    end
  end

  defp buy_there_sell_here(ctx, commodity) do
    buy_price = Map.get(ctx.dest_prices, commodity)
    sell_price = Map.get(ctx.local_prices, commodity)

    with true <- buy_price != nil and sell_price != nil and sell_price > buy_price,
         plan <- make_plan(:reverse, ctx, commodity, buy_price, sell_price) do
      plan
    else
      _ -> []
    end
  end

  defp make_plan(direction, ctx, commodity, buy_price, sell_price) do
    trip_distance = if direction == :forward, do: ctx.distance, else: ctx.distance * 2

    # Reserve credits: operating costs + personality-driven savings
    # Scale down when broke — can't save money you don't have
    fuel_cost = Travel.fuel_cost(trip_distance, ctx.fuel_rate) * 10
    ideal_savings = Simulator.Agents.ShipAgent.ideal_credit_reserve(%{safety: ctx.safety_weight})
    min_savings = min(ideal_savings, round(ctx.credits * 0.5))
    operating_reserve = round(fuel_cost + 200 + min_savings)
    available_for_cargo = max(ctx.credits - operating_reserve, 0)

    quantity = min(ctx.cargo_space, floor(available_for_cargo / max(buy_price, 0.01))) |> max(0)

    fuel_cost_credits = fuel_cost

    raw_profit = quantity * (sell_price - buy_price) - fuel_cost_credits

    # Discount profit by price confidence (stale data = less reliable)
    dest = if direction == :forward, do: ctx.dest, else: ctx.location
    confidence = price_confidence(ctx, dest, commodity)
    profit = raw_profit * confidence

    include_break_even = Map.get(ctx, :include_break_even, false)
    accept? = quantity > 0 and (profit > 0 or (include_break_even and profit > -100))

    if accept? do
      steps = plan_steps(direction, ctx, commodity, quantity)

      [
        %Plan{
          type: :trade_run,
          steps: steps,
          expected_profit: profit,
          created_at_tick: ctx.tick,
          expires_at_tick: ctx.tick + @plan_duration_ticks
        }
      ]
    else
      []
    end
  end

  defp plan_steps(:forward, ctx, commodity, quantity) do
    [
      %PlanStep{action: :dock, at: ctx.location},
      %PlanStep{action: :refuel, at: ctx.location},
      %PlanStep{action: :buy, commodity: commodity, quantity: quantity, at: ctx.location},
      %PlanStep{action: :undock, at: ctx.location},
      %PlanStep{action: :travel, to: ctx.dest},
      %PlanStep{action: :dock, at: ctx.dest},
      %PlanStep{action: :sell, commodity: commodity, quantity: quantity, at: ctx.dest},
      %PlanStep{action: :refuel, at: ctx.dest},
      %PlanStep{action: :undock, at: ctx.dest}
    ]
  end

  defp plan_steps(:reverse, ctx, commodity, quantity) do
    [
      %PlanStep{action: :dock, at: ctx.location},
      %PlanStep{action: :refuel, at: ctx.location},
      %PlanStep{action: :undock, at: ctx.location},
      %PlanStep{action: :travel, to: ctx.dest},
      %PlanStep{action: :dock, at: ctx.dest},
      %PlanStep{action: :buy, commodity: commodity, quantity: quantity, at: ctx.dest},
      %PlanStep{action: :refuel, at: ctx.dest},
      %PlanStep{action: :undock, at: ctx.dest},
      %PlanStep{action: :travel, to: ctx.location},
      %PlanStep{action: :dock, at: ctx.location},
      %PlanStep{action: :sell, commodity: commodity, quantity: quantity, at: ctx.location},
      %PlanStep{action: :undock, at: ctx.location}
    ]
  end

  defp idle_plan(tick) do
    %Plan{
      type: :idle,
      steps: [%PlanStep{action: :idle}],
      expected_profit: 0.0,
      created_at_tick: tick,
      expires_at_tick: tick + 20
    }
  end

  defp price_confidence(ctx, location, commodity) do
    raw_prices = Map.get(ctx.known_prices, location, %{})

    case Map.get(raw_prices, commodity) do
      %{tick: observed_tick} ->
        age = ctx.tick - observed_tick
        max(0.1, 1.0 - age / 200.0)

      _ ->
        0.5
    end
  end

  defp resolve_travel_time(from, to) do
    # Try each known system agent, fall back to static travel map
    systems = Simulator.World.Registry.system_ids()

    Enum.find_value(systems, Travel.travel_time(from, to), fn system_id ->
      case Simulator.Agents.Agent.whereis(system_id) do
        {:ok, pid} ->
          case Simulator.World.System.query_travel_time(pid, from, to) do
            {:ok, _ticks} = result -> result
            {:error, _} -> nil
          end

        :error ->
          nil
      end
    end)
  end

  defp cargo_total(cargo) do
    cargo |> Map.values() |> Enum.sum()
  end
end
