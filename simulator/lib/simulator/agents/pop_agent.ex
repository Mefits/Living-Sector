defmodule Simulator.Agents.PopAgent do
  @moduledoc """
  Represents a demographic bloc — thousands or millions of people abstracted
  into a single process.

  Populations consume goods from the local market, produce labor, track
  sentiment and unrest, and generate dynamic demand that makes the economy
  self-regulating. When a food shortage hits, satisfaction drops, unrest
  rises, demand spikes, and prices attract ships to deliver supplies.

  ## Tick Cycle

  1. **Consume** — attempt to buy needs from local market
  2. **Produce** — feed labor output into local supply
  3. **Sentiment** — update satisfaction and unrest
  4. **Growth** — population grows/shrinks based on conditions
  """

  use Simulator.Agents.Agent

  # Sentiment inertia scaled for 4x tick rate — base: 0.9
  # At 4 ticks/sec: 0.9^4 ≈ 0.656 per second, vs 0.9^1 = 0.9 per second
  # We use 0.9^(1/4) ≈ 0.974 so that 4 ticks compounds to ~0.9
  # Sentiment smoothing: base 0.9 per old-tick, raised to tick_scale power
  # so N consecutive ticks compound to the same effect
  @sentiment_inertia :math.pow(0.9, Simulator.Simulation.Config.tick_scale())

  # --- Public API ---

  @doc """
  Returns the full population state.
  """
  @spec get_state(pid()) :: map()
  def get_state(pid), do: GenServer.call(pid, :get_state)

  # --- Agent Callbacks ---

  @defaults %{
    demographic: :workers,
    population_count: 10_000,
    growth_rate: 0.0005,
    food_satisfaction: 70,
    safety_satisfaction: 80,
    entertainment_satisfaction: 50,
    total_wealth: 500_000,
    spending_rate: 0.02,
    labor_output: 0,
    employed_fraction: 0.85,
    overall_sentiment: 65,
    unrest: 10,
    migration_pressure: 0.0,
    body_food_multiplier: 1.0,
    consumption: %{food: 50, fuel: 0},
    production_commodity: nil,
    production_amount: 0
  }

  @impl Simulator.Agents.Agent
  def agent_type, do: :population

  @impl Simulator.Agents.Agent
  def init_agent(config) do
    c = Map.merge(@defaults, config)

    # Subscribe to the body-level food multiplier feed so phase_growth/2 can
    # read a cached value instead of synchronously calling into BodyAgent
    # every growth tick — that sync fanout would deadlock under load.
    if is_binary(c[:facility_id]) do
      case Simulator.World.Registry.body_id_for_location(c.facility_id) do
        body_id when is_binary(body_id) ->
          Simulator.Events.subscribe("body:#{body_id}")

        _ ->
          :ok
      end

      # Subscribe to the pop's own facility topic so we receive
      # :passengers_arrived events from delivering couriers.
      Simulator.Events.subscribe("facility:#{c.facility_id}")
    end

    state = %{
      id: c.id,
      label: c[:label] || c.id,
      location: c[:location],
      facility_id: c[:facility_id],
      demographic: c.demographic,
      population_count: c.population_count,
      growth_rate: c.growth_rate,
      food_satisfaction: c.food_satisfaction,
      safety_satisfaction: c.safety_satisfaction,
      entertainment_satisfaction: c.entertainment_satisfaction,
      total_wealth: c.total_wealth,
      spending_rate: c.spending_rate,
      labor_output: c.labor_output,
      employed_fraction: c.employed_fraction,
      overall_sentiment: c.overall_sentiment,
      unrest: c.unrest,
      migration_pressure: c.migration_pressure,
      consumption: c.consumption,
      production_commodity: c.production_commodity,
      production_amount: c.production_amount,
      # Cached value from the latest :food_availability broadcast on the
      # pop's body. 1.0 is neutral until the first broadcast arrives.
      body_food_multiplier: c.body_food_multiplier,
      __db_id__: c[:db_id],
      __agent_type__: :population
    }

    {:ok, state}
  end

  @impl Simulator.Agents.Agent
  def handle_tick(tick, state) do
    state =
      state
      |> phase_consume(tick)
      |> phase_produce(tick)
      |> phase_sentiment()
      |> phase_post_contracts(tick)
      |> phase_post_passenger_contracts(tick)
      |> phase_growth(tick)
      |> phase_broadcast(tick)
      |> mark_dirty()

    {:ok, state}
  end

  # Arrival of passengers delivered by a ship: bump population. Broadcast
  # comes from the delivering ship's `deliver_passengers` BT action via
  # `"facility:<location>"`. Sub to that topic in init so we receive it.
  @impl Simulator.Agents.Agent
  def handle_event({:passengers_arrived, %{passenger_count: count}}, state) when count > 0 do
    {:ok, %{state | population_count: state.population_count + count}}
  end

  def handle_event({:food_availability, %{multiplier: mult}}, state) when is_number(mult) do
    clamped = mult |> max(0.5) |> min(2.0)
    {:ok, %{state | body_food_multiplier: clamped}}
  end

  def handle_event(_event, state), do: {:ok, state}

  @impl Simulator.Agents.Agent
  def persist_state(state) do
    if db_id = state[:__db_id__] do
      Simulator.Repo.get!(Simulator.Schemas.Population, db_id)
      |> Simulator.Schemas.Population.changeset(%{
        population_count: state.population_count,
        overall_sentiment: round(state.overall_sentiment),
        unrest: round(state.unrest),
        total_wealth: state.total_wealth,
        food_satisfaction: round(state.food_satisfaction),
        state: %{
          "migration_pressure" => state.migration_pressure,
          "body_food_multiplier" => state.body_food_multiplier,
          "safety_satisfaction" => state.safety_satisfaction,
          "entertainment_satisfaction" => state.entertainment_satisfaction,
          "labor_output" => state.labor_output
        }
      })
      |> Simulator.Repo.update!()
    end

    :ok
  end

  @impl GenServer
  def handle_call(:get_state, _from, state), do: {:reply, state, state}

  # --- Tick Phases ---

  @consume_interval 5 * Simulator.Simulation.Config.tick_multiplier()

  defp phase_consume(state, tick) when rem(tick, @consume_interval) == 0 do
    case find_market(state.facility_id) do
      {:ok, market_pid} -> buy_food(state, market_pid)
      :error -> Map.update!(state, :food_satisfaction, &clamp(&1 - 3, 0, 100))
    end
  end

  defp phase_consume(state, _tick), do: state

  defp buy_food(state, market_pid) do
    food_needed = Map.get(state.consumption, :food, 0)

    prices =
      try do
        Simulator.Agents.MarketAgent.query_prices(market_pid)
      catch
        :exit, _ -> %{}
      end

    food_price = Map.get(prices, :food, 15.0)

    affordable =
      min(food_needed, floor(state.total_wealth * state.spending_rate / max(food_price, 0.01)))

    buy_qty = max(affordable, 0)

    if buy_qty <= 0 do
      Map.update!(state, :food_satisfaction, &clamp(&1 - 8, 0, 100))
    else
      # Urgency-scaled premium: starving populations bid much higher
      urgency = 1.0 - state.food_satisfaction / 100.0
      premium = 1.1 + urgency
      bid_price = food_price * premium

      Simulator.Agents.MarketAgent.place_buy_order(market_pid, %{
        agent_id: state.id,
        commodity: :food,
        quantity: buy_qty,
        price: bid_price
      })

      # When desperate, also bid for water (farms need water to grow food)
      if state.food_satisfaction < 30 do
        water_price = Map.get(prices, :water, 10.0)

        Simulator.Agents.MarketAgent.place_buy_order(market_pid, %{
          agent_id: state.id,
          commodity: :water,
          quantity: round(food_needed * 0.5),
          price: water_price * (1.0 + urgency)
        })
      end

      cost = round(buy_qty * food_price)
      satisfaction_change = if buy_qty >= food_needed, do: 2, else: -5

      state
      |> Map.update!(:total_wealth, &max(&1 - cost, 0))
      |> Map.update!(:food_satisfaction, &clamp(&1 + satisfaction_change, 0, 100))
    end
  end

  @produce_interval 5 * Simulator.Simulation.Config.tick_multiplier()

  defp phase_produce(state, tick) when rem(tick, @produce_interval) == 0 do
    labor = round(state.population_count * state.employed_fraction * 0.001)
    state = %{state | labor_output: labor}

    case {state.production_commodity, find_market(state.facility_id)} do
      {nil, _} ->
        state

      {commodity, {:ok, market_pid}} ->
        if state.production_amount > 0 do
          # Push production directly into market supply — this represents
          # infrastructure output (workers operating refineries, farms, etc.)
          Simulator.Agents.MarketAgent.add_supply(market_pid, %{
            commodity => state.production_amount
          })

          # Track revenue for population wealth at market price
          prices = Simulator.Agents.MarketAgent.query_prices(market_pid)

          market_price =
            Map.get(prices, commodity, Simulator.Economy.Commodities.base_price(commodity))

          revenue = round(state.production_amount * market_price)
          %{state | total_wealth: state.total_wealth + revenue}
        else
          state
        end

      _ ->
        state
    end
  end

  defp phase_produce(state, _tick), do: state

  defp phase_sentiment(state) do
    food_w = 0.5
    safety_w = 0.3
    entertainment_w = 0.2

    target_sentiment =
      round(
        state.food_satisfaction * food_w +
          state.safety_satisfaction * safety_w +
          state.entertainment_satisfaction * entertainment_w
      )

    # Sentiment moves toward target with inertia (no rounding — preserves fractional drift)
    new_sentiment =
      state.overall_sentiment * @sentiment_inertia + target_sentiment * (1 - @sentiment_inertia)

    # Unrest has momentum — even if conditions improve, unrest lingers
    target_unrest = max(100 - new_sentiment, 0)

    # Unrest inertia scaled like sentiment (0.95^tick_scale compounds correctly)
    unrest_inertia = :math.pow(0.95, Simulator.Simulation.Config.tick_scale())

    new_unrest =
      state.unrest * unrest_inertia + target_unrest * (1 - unrest_inertia)

    # Migration pressure scaled by tick_scale
    ts = Simulator.Simulation.Config.tick_scale()
    migration = if new_sentiment < 30, do: 0.01 * ts, else: -0.005 * ts
    new_migration = clamp(state.migration_pressure + migration, -1.0, 1.0)

    %{
      state
      | overall_sentiment: clamp(new_sentiment, 0, 100),
        unrest: clamp(new_unrest, 0, 100),
        migration_pressure: new_migration
    }
  end

  @contract_check_interval 30 * Simulator.Simulation.Config.tick_multiplier()

  defp phase_post_contracts(state, tick) when rem(tick, @contract_check_interval) == 0 do
    if state.food_satisfaction < 50 and state.total_wealth > 1000 do
      # Desperate populations pay more
      urgency = 1.0 - state.food_satisfaction / 100.0
      food_needed = round(Map.get(state.consumption, :food, 10) * 50)
      base_price = get_food_price(state)
      payment = round(food_needed * base_price * (1 + urgency * 2))
      payment = min(payment, round(state.total_wealth * 0.2))

      case Simulator.Economy.ContractBoard.post_contract(%{
             contract_type: "delivery",
             requestor_type: "population",
             requestor_id: state.id,
             commodity: "food",
             quantity: food_needed,
             destination_location: state.facility_id,
             payment: payment,
             urgency: urgency,
             escalation_rate: 0.005 + urgency * 0.015,
             posted_at_tick: tick,
             deadline_tick: tick + pop_contract_deadline(state.facility_id)
           }) do
        {:ok, _contract} ->
          %{state | total_wealth: state.total_wealth - payment}

        {:error, _} ->
          state
      end
    else
      state
    end
  end

  defp phase_post_contracts(state, _tick), do: state

  # How often pops evaluate whether to post passenger contracts. Same
  # cadence as the supply contracts, just offset in phase_order.
  @passenger_check_interval 60 * Simulator.Simulation.Config.tick_multiplier()

  # Population threshold below which pops don't generate outbound travelers
  # (a small outpost of a few hundred doesn't feed a courier economy).
  @passenger_min_population 5_000

  # Maximum travelers on a single posted contract.
  @passenger_contract_max 20

  defp phase_post_passenger_contracts(state, tick)
       when rem(tick, @passenger_check_interval) == 0 do
    cond do
      not is_binary(state.facility_id) -> state
      state.population_count < @passenger_min_population -> state
      state.overall_sentiment < 50 -> state
      state.total_wealth < 1000 -> state
      true -> try_post_passenger_contract(state, tick)
    end
  end

  defp phase_post_passenger_contracts(state, _tick), do: state

  defp try_post_passenger_contract(state, tick) do
    case pick_passenger_destination(state) do
      nil ->
        state

      dest ->
        # Traveler count scales sublinearly with population so a 50K pop
        # doesn't flood the contract board.
        base = round(:math.sqrt(state.population_count / 1000.0) * 4)
        travelers = base |> max(2) |> min(@passenger_contract_max)
        distance = resolve_passenger_distance(state.facility_id, dest)
        payment = round(200 + distance * 4 + travelers * 10)
        payment = min(payment, round(state.total_wealth * 0.1))

        attrs = %{
          contract_type: "passenger_transport",
          requestor_type: "population",
          requestor_id: state.id,
          faction_id: state[:faction_id],
          source_location: state.facility_id,
          destination_location: dest,
          passenger_count: travelers,
          quantity: travelers,
          payment: payment,
          urgency: 0.3,
          escalation_rate: 0.002,
          min_reputation: 20,
          posted_at_tick: tick,
          deadline_tick: tick + pop_contract_deadline(state.facility_id) * 2
        }

        case Simulator.Economy.ContractBoard.post_contract(attrs) do
          {:ok, _contract} ->
            %{state | total_wealth: state.total_wealth - payment}

          {:error, _} ->
            state
        end
    end
  end

  # Picks a reachable destination weighted toward other populated
  # facilities. Falls back to uniform random across reachable
  # destinations when no pop data is handy.
  defp pick_passenger_destination(state) do
    destinations = Simulator.World.Travel.reachable_from(state.facility_id)

    case destinations do
      [] -> nil
      _ -> Enum.random(destinations)
    end
  end

  defp resolve_passenger_distance(from, to) do
    case Simulator.World.Travel.travel_time(from, to) do
      {:ok, ticks} -> ticks
      _ -> 100
    end
  end

  defp get_food_price(state) do
    case find_market(state.facility_id) do
      {:ok, pid} ->
        prices = Simulator.Agents.MarketAgent.query_prices(pid)
        Map.get(prices, :food, Simulator.Economy.Commodities.base_price(:food))

      :error ->
        Simulator.Economy.Commodities.base_price(:food)
    end
  end

  @growth_interval 10 * Simulator.Simulation.Config.tick_multiplier()

  defp phase_growth(state, tick) when rem(tick, @growth_interval) == 0 do
    sentiment_mod = if state.overall_sentiment > 60, do: 1.0, else: 0.5
    # Combined multiplier clamped to the conservative band so a single
    # good/bad tick can't induce boom/bust cycles on its own.
    growth_modifier =
      (sentiment_mod * state.body_food_multiplier)
      |> max(0.5)
      |> min(1.5)

    change = round(state.population_count * state.growth_rate * growth_modifier)
    %{state | population_count: max(state.population_count + change, 0)}
  end

  defp phase_growth(state, _tick), do: state

  defp phase_broadcast(state, tick) do
    Simulator.Events.broadcast("facility:#{state.facility_id}", :population_update, %{
      pop_id: state.id,
      demographic: state.demographic,
      population: state.population_count,
      sentiment: state.overall_sentiment,
      unrest: state.unrest,
      tick: tick
    })

    state
  end

  # --- Helpers ---

  # Deadline: base + max travel from any reachable location (food could come from anywhere)
  defp pop_contract_deadline(facility_id) do
    max_travel =
      Simulator.World.Travel.reachable_from(facility_id)
      |> Enum.map(fn loc ->
        case Simulator.World.Travel.travel_time(facility_id, loc) do
          {:ok, t} -> t
          _ -> 0
        end
      end)
      |> Enum.max(fn -> 200 end)

    (200 + max_travel * 3) * Simulator.Simulation.Config.tick_multiplier()
  end

  defp find_market(facility_id) do
    Simulator.Agents.Agent.whereis("market-#{facility_id}")
  end

  defp clamp(value, min_val, max_val) do
    value |> max(min_val) |> min(max_val)
  end
end
