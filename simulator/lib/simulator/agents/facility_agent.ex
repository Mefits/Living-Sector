defmodule Simulator.Agents.FacilityAgent do
  @moduledoc """
  A station, port, colony, or habitat in the simulation.

  Facilities are the nodes of the economy — ships dock here to trade,
  refuel, and repair. Each facility manages docking slots, provides
  services, and maintains its own reserves and condition.

  ## Docking Protocol

      ShipAgent → :request_dock  → FacilityAgent
      FacilityAgent → {:ok, info} | {:error, reason} → ShipAgent
      ShipAgent → :request_undock → FacilityAgent

  ## Services

  Facilities can provide: `:refuel`, `:repair`, `:medical`, `:market`,
  `:passenger_terminal`. Services may go offline if condition degrades.
  """

  use Simulator.Agents.Agent

  require Logger

  alias Simulator.Simulation.Config

  @condition_decay_per_tick 0.0005 * Config.tick_scale()

  # --- Public API ---

  @doc """
  Requests docking permission. Returns `{:ok, dock_info}` or `{:error, reason}`.
  """
  @spec request_dock(pid(), map()) :: {:ok, map()} | {:error, atom()}
  def request_dock(pid, ship_info) do
    GenServer.call(pid, {:request_dock, ship_info})
  end

  @doc """
  Requests undocking. Frees the docking slot.
  """
  @spec request_undock(pid(), String.t()) :: :ok
  def request_undock(pid, ship_id) do
    GenServer.call(pid, {:request_undock, ship_id})
  end

  @doc """
  Requests refueling. Returns `{:ok, refuel_info}` or `{:error, reason}`.
  """
  @spec request_refuel(pid(), map()) :: {:ok, map()} | {:error, atom()}
  def request_refuel(pid, request) do
    GenServer.call(pid, {:request_refuel, request})
  end

  @doc """
  Returns the full facility state.
  """
  @spec get_state(pid()) :: map()
  def get_state(pid) do
    GenServer.call(pid, :get_state)
  end

  # --- Agent Callbacks ---

  @defaults %{
    type: :station,
    docking_capacity: 10,
    services: [:refuel, :market],
    condition: 1.0,
    reputation: 50,
    credits: 10_000,
    reserves: %{fuel: 5000, food: 2000},
    wage_rate: 10,
    crew_roles: [],
    body_id: nil,
    faction_id: "independent"
  }

  @impl Simulator.Agents.Agent
  def agent_type, do: :facility

  @impl Simulator.Agents.Agent
  def init_agent(config) do
    c = Map.merge(@defaults, config)

    state = %{
      id: c.id,
      name: c[:name] || c.id,
      location: c[:location],
      type: c.type,
      docking_capacity: c.docking_capacity,
      docked_ships: [],
      services: c.services,
      condition: c.condition,
      reputation: c.reputation,
      credits: c.credits,
      reserves: c.reserves,
      initial_reserves: c.reserves,
      pending_deliveries: [],
      wage_rate: c.wage_rate,
      # Restore persisted crew when the spawner passed a serialized
      # blob (from the facility's state JSONB), otherwise spin up a
      # fresh complement from roles.
      crew: restore_crew(c),
      body_id: c[:body],
      position: {0.0, 0.0},
      level: c[:level] || 1,
      xp: 0,
      faction_id: c[:faction_id] || "independent",
      __db_id__: c[:db_id],
      __agent_type__: :facility
    }

    {:ok, state}
  end

  defp restore_crew(config) do
    case config[:crew] do
      %Simulator.Agents.CrewComplement{} = crew ->
        crew

      %{} = serialized when map_size(serialized) > 0 ->
        Simulator.Agents.CrewComplement.deserialize(serialized, config.crew_roles)

      _ ->
        Simulator.Agents.CrewComplement.new(config.crew_roles)
    end
  end

  @impl Simulator.Agents.Agent
  def handle_tick(tick, state) do
    # Abandoned facilities are dormant — skip all processing
    if Map.get(state, :abandoned, false) do
      {:ok, state}
    else
      state =
        state
        |> tick_crew(tick)
        |> report_position()
        |> degrade_condition()
        |> check_abandonment(tick)
        |> maybe_restock_reserves(tick)
        |> maybe_mine(tick)
        |> execute_recipes(tick)
        |> maybe_purchase_remotely(tick)
        |> maybe_post_delivery_contracts(tick)
        |> maybe_post_courier_contracts(tick)
        |> maybe_post_crew_missions(tick)
        |> mark_dirty()

      {:ok, state}
    end
  end

  @impl Simulator.Agents.Agent
  def persist_state(state) do
    if db_id = state[:__db_id__] do
      # Reserves live in the state JSONB rather than a top-level
      # column — Facility schema only exposes `initial_reserves` at
      # the relational layer.
      jsonb_state = %{
        "reserves" => stringify_keys(state.reserves),
        "docked_ships" => state.docked_ships,
        "pending_deliveries" => stringify_deliveries(state.pending_deliveries),
        "level" => state.level,
        "xp" => state.xp,
        "crew" => Simulator.Agents.CrewComplement.serialize(state.crew)
      }

      Simulator.Repo.get!(Simulator.Schemas.Facility, db_id)
      |> Ecto.Changeset.change(%{
        credits: round(state.credits),
        condition: state.condition,
        reputation: state.reputation,
        state: jsonb_state
      })
      |> Simulator.Repo.update!()
    end

    :ok
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  defp stringify_keys(other), do: other

  defp stringify_deliveries(deliveries) when is_list(deliveries) do
    Enum.map(deliveries, fn d ->
      Map.new(d, fn {k, v} ->
        {to_string(k), if(is_atom(v) and v != nil, do: to_string(v), else: v)}
      end)
    end)
  end

  defp stringify_deliveries(_), do: []

  # --- Mining Extraction ---

  @mining_interval 5 * Config.tick_multiplier()
  # Extraction rate NOT scaled — fires at same wall-clock frequency via interval scaling
  @base_extraction_rate 15

  defp maybe_mine(%{type: :mining_rig} = state, tick) when rem(tick, @mining_interval) == 0 do
    body_resources = get_body_resources(state.body_id)

    if body_resources == %{} do
      state
    else
      efficiency = state.condition * crew_efficiency(state)

      # For each commodity in the body's resource map, calculate the target
      # extraction from richness × rate, then ask the BodyAgent to actually
      # extract it — this depletes the body's live richness. If no BodyAgent
      # is registered, fall back to the legacy static-richness behaviour.
      body_pid =
        case Simulator.Agents.Agent.whereis("body-#{state.body_id}") do
          {:ok, pid} -> pid
          :error -> nil
        end

      extracted =
        body_resources
        |> Enum.map(fn {commodity, richness} ->
          target = @base_extraction_rate * richness * efficiency

          actual =
            if body_pid && target > 0 do
              Simulator.Agents.BodyAgent.extract(body_pid, commodity, target)
            else
              target
            end

          {commodity, round(actual)}
        end)
        |> Enum.reject(fn {_, amount} -> amount <= 0 end)
        |> Map.new()

      if extracted != %{} do
        # Push extracted resources to local market atomically
        case Simulator.Agents.Agent.whereis("market-#{state.location}") do
          {:ok, market_pid} ->
            Simulator.Agents.MarketAgent.add_supply(market_pid, extracted)

            Simulator.Events.broadcast("facility:#{state.id}", :mining_output, %{
              facility_id: state.id,
              extracted: extracted
            })

          :error ->
            Logger.warning(
              "Facility #{state.id}: mined resources dropped, no market at #{state.location}"
            )
        end
      end

      state
    end
  end

  defp maybe_mine(state, _tick), do: state

  defp get_body_resources(nil), do: %{}

  defp get_body_resources(body_id) do
    # Query each SystemAgent for body resource data via proper API
    for system_id <- Simulator.World.Registry.system_ids(),
        {:ok, pid} <- [Simulator.Agents.Agent.whereis(system_id)],
        reduce: %{} do
      acc ->
        try do
          case Simulator.World.System.get_body_resources(pid, body_id) do
            resources when resources != %{} -> resources
            _ -> acc
          end
        catch
          :exit, reason ->
            Logger.debug(
              "Facility: body resource lookup failed for #{system_id}: #{inspect(reason)}"
            )

            acc
        end
    end
  end

  # --- Recipe Execution ---

  @recipe_interval 5 * Config.tick_multiplier()

  defp execute_recipes(state, tick) when rem(tick, @recipe_interval) == 0 do
    recipes = Simulator.Economy.Recipes.for_facility_type(state.type)

    if recipes == [] do
      state
    else
      case Simulator.Agents.Agent.whereis("market-#{state.location}") do
        {:ok, market_pid} ->
          state = maybe_feed_reserves_to_market(state, market_pid, recipes)
          run_recipes(state, market_pid, recipes)

        :error ->
          state
      end
    end
  end

  defp execute_recipes(state, _tick), do: state

  defp maybe_post_input_orders(state, market_pid, recipes) do
    if state.credits < 1000 do
      state
    else
      supply = Simulator.Agents.MarketAgent.get_supply(market_pid)
      prices = Simulator.Agents.MarketAgent.query_prices(market_pid)

      # Collect all unique recipe inputs
      needed_inputs =
        recipes
        |> Enum.flat_map(fn recipe ->
          Enum.map(recipe.inputs, fn {commodity, amount} -> {commodity, amount} end)
        end)
        |> Enum.uniq_by(&elem(&1, 0))

      Enum.reduce(needed_inputs, state, fn {commodity, recipe_amount}, s ->
        available = Map.get(supply, commodity, 0)

        if available < recipe_amount * 2 and s.credits > 1000 do
          price = Map.get(prices, commodity, 50.0) * 1.5
          order_qty = recipe_amount * 10

          Simulator.Agents.MarketAgent.place_buy_order(market_pid, %{
            agent_id: s.id,
            commodity: commodity,
            quantity: order_qty,
            price: price
          })

          if available == 0 do
            Simulator.Events.log(:input_shortage, %{
              facility_id: s.id,
              facility_name: s.name,
              commodity: commodity,
              location: s.location
            })
          end

          s
        else
          s
        end
      end)
    end
  end

  defp maybe_feed_reserves_to_market(state, market_pid, recipes) do
    needed =
      recipes
      |> Enum.flat_map(&Map.keys(&1.inputs))
      |> Enum.uniq()

    supply = Simulator.Agents.MarketAgent.get_supply(market_pid)

    Enum.reduce(needed, state, fn commodity, s ->
      market_qty = Map.get(supply, commodity, 0)
      reserve_qty = Map.get(s.reserves, commodity, 0)

      if market_qty < 100 and reserve_qty > 0 do
        transfer = min(reserve_qty, 50)
        Simulator.Agents.MarketAgent.add_supply(market_pid, %{commodity => transfer})
        %{s | reserves: Map.update(s.reserves, commodity, 0, &max(&1 - transfer, 0))}
      else
        s
      end
    end)
  end

  defp run_recipes(state, market_pid, recipes) do
    # Post buy orders for missing recipe inputs at premium prices
    state = maybe_post_input_orders(state, market_pid, recipes)

    # Get a snapshot of market supply to compute recipe deltas
    supply = Simulator.Agents.MarketAgent.get_supply(market_pid)

    # Execute each recipe against the snapshot — level controls max batches
    max_batches = state.level * 10

    {final_supply, all_produced} =
      Enum.reduce(recipes, {supply, %{}}, fn recipe, {sup, produced} ->
        efficiency = state.condition * crew_efficiency(state)

        {new_sup, recipe_produced} =
          Simulator.Economy.Recipes.execute(recipe, sup, efficiency, max_batches)

        merged_produced =
          Map.merge(produced, recipe_produced, fn _k, v1, v2 -> v1 + v2 end)

        {new_sup, merged_produced}
      end)

    # Compute the net consumed (supply that decreased) and send atomically
    if final_supply != supply do
      consumed =
        Enum.reduce(supply, %{}, fn {commodity, old_amount}, acc ->
          new_amount = Map.get(final_supply, commodity, 0)
          diff = old_amount - new_amount

          if diff > 0 do
            Map.put(acc, commodity, diff)
          else
            acc
          end
        end)

      Simulator.Agents.MarketAgent.consume_and_produce(market_pid, consumed, all_produced)
    end

    # Broadcast production events and gain XP
    state =
      if all_produced != %{} do
        Simulator.Events.broadcast("facility:#{state.id}", :production, %{
          facility_id: state.id,
          produced: all_produced
        })

        gain_production_xp(state, map_size(all_produced))
      else
        state
      end

    state
  end

  defp tick_crew(state, tick) do
    food_available = Map.get(state.reserves, :food, 0)

    case Simulator.Agents.CrewComplement.tick(state.crew, tick,
           docked: true,
           food_available: food_available
         ) do
      {crew, food_consumed} ->
        reserves = Map.update(state.reserves, :food, 0, &max(&1 - food_consumed, 0))
        %{state | crew: crew, reserves: reserves}

      crew ->
        %{state | crew: crew}
    end
  end

  # --- Position Tracking ---

  defp report_position(%{body_id: nil} = state), do: state

  defp report_position(state) do
    case find_body_position(state.body_id) do
      {bx, by, ox, oy} ->
        # Offset from body so co-located facilities don't stack
        angle = :erlang.phash2(state.id, 360) * (:math.pi() / 180.0)
        radius = 0.15
        px = ox + bx + radius * :math.cos(angle)
        py = oy + by + radius * :math.sin(angle)

        Simulator.Spatial.ChunkManager.update_position(state.id, px, py)
        %{state | position: {px, py}}

      nil ->
        state
    end
  end

  defp find_body_position(body_id) do
    Enum.find_value(Simulator.World.Registry.system_ids(), fn system_id ->
      case Simulator.Agents.Agent.whereis(system_id) do
        {:ok, pid} ->
          positions = Simulator.World.System.get_body_positions(pid)

          case Map.get(positions, body_id) do
            %{x: x, y: y} ->
              {ox, oy} = Simulator.World.Registry.universe_offset(system_id)
              {x, y, ox, oy}

            nil ->
              nil
          end

        :error ->
          nil
      end
    end)
  end

  # --- Leveling ---

  @max_level 10

  defp gain_production_xp(state, recipe_count) do
    new_xp = state.xp + recipe_count
    level_up_threshold = state.level * 100

    if new_xp >= level_up_threshold and state.level < @max_level do
      new_level = state.level + 1

      Simulator.Events.log(:facility_level_up, %{
        facility_id: state.id,
        name: state.name,
        new_level: new_level
      })

      %{state | level: new_level, xp: 0}
    else
      %{state | xp: new_xp}
    end
  end

  # Contract deadline: base 800 ticks + 3x travel time (gives ship time to find, accept, travel, load, deliver)
  defp contract_deadline(source, destination) do
    travel =
      case Simulator.World.Travel.travel_time(source, destination) do
        {:ok, t} -> t
        _ -> 200
      end

    # Base 200 ticks + 3x travel, scaled to current tick rate
    (200 + travel * 3) * Config.tick_multiplier()
  end

  defp crew_efficiency(%{crew: crew}) do
    Simulator.Agents.CrewComplement.efficiency(crew)
  end

  defp crew_efficiency(_), do: 0.5

  # --- GenServer Call Handlers ---

  @impl GenServer
  def handle_call({:request_dock, ship_info}, _from, state) do
    ship_id = ship_info.ship_id

    cond do
      ship_id in state.docked_ships ->
        {:reply, {:ok, dock_info(state)}, state}

      length(state.docked_ships) >= state.docking_capacity ->
        {:reply, {:error, :full}, state}

      true ->
        fee = compute_docking_fee(state)

        new_state = %{
          state
          | docked_ships: [ship_id | state.docked_ships],
            credits: state.credits + fee
        }

        event = %{ship_id: ship_id, type: :docked, facility_id: state.id}
        Simulator.Events.broadcast("facility:#{state.id}", :docking_event, event)
        Simulator.Events.broadcast("ship_events", :docked, event)

        {:reply, {:ok, dock_info(new_state)}, new_state}
    end
  end

  def handle_call({:request_undock, ship_id}, _from, state) do
    new_state = %{state | docked_ships: List.delete(state.docked_ships, ship_id)}

    event = %{ship_id: ship_id, type: :undocked, facility_id: state.id}
    Simulator.Events.broadcast("facility:#{state.id}", :docking_event, event)
    Simulator.Events.broadcast("ship_events", :undocked, event)

    {:reply, :ok, new_state}
  end

  def handle_call({:request_refuel, request}, _from, state) do
    amount = request.amount
    fuel_available = Map.get(state.reserves, :fuel, 0)
    actual = min(amount, fuel_available)
    price_per_unit = compute_refuel_price(state)

    if actual > 0 do
      cost = round(actual * price_per_unit)

      new_reserves = Map.update!(state.reserves, :fuel, &(&1 - actual))
      new_state = %{state | reserves: new_reserves, credits: state.credits + cost}

      {:reply, {:ok, %{amount: actual, cost: cost}}, new_state}
    else
      {:reply, {:error, :no_fuel}, state}
    end
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  # Faction tax sweep: deduct `rate` of current credits (capped at a small
  # floor when credits are low so we don't extract from nearly-broke
  # facilities) and return the actual amount deducted.
  def handle_call({:collect_tax, rate}, _from, state)
      when is_number(rate) and rate >= 0 and rate <= 1 do
    # Only tax facilities with a comfortable buffer — leave enough to
    # operate without forcing an artificial bankruptcy event.
    minimum_buffer = 1_000
    taxable = max(state.credits - minimum_buffer, 0)
    amount = round(taxable * rate)

    if amount > 0 do
      {:reply, amount, %{state | credits: state.credits - amount}}
    else
      {:reply, 0, state}
    end
  end

  # Broke ships can take a short paid task at the facility. The facility pays
  # a small amount from its treasury (only if well-funded) in exchange for
  # crew labor — enough to afford a tank of fuel and get back to trading.
  def handle_call({:request_station_job, request}, _from, state) do
    min_treasury = 1_000

    if state.credits >= min_treasury do
      payout = 100 + div(request.skill_bonus || 0, 2)
      payout = min(payout, 250)
      new_state = %{state | credits: state.credits - payout}
      {:reply, {:ok, payout}, new_state}
    else
      {:reply, {:error, :insufficient_treasury}, state}
    end
  end

  @impl GenServer
  def handle_cast({:market_revenue, amount}, state) do
    {:noreply, %{state | credits: state.credits + amount}}
  end

  def handle_cast({:consume_reserve, commodity, quantity}, state) do
    new_reserves =
      Map.update(state.reserves, commodity, 0, &max(&1 - quantity, 0))

    {:noreply, %{state | reserves: new_reserves}}
  end

  def handle_cast({:receive_delivery, commodity, quantity}, state) do
    new_reserves = Map.update(state.reserves, commodity, quantity, &(&1 + quantity))

    # Remove matching pending delivery entry
    pending =
      Enum.reject(state.pending_deliveries, fn pd ->
        pd.commodity == commodity and pd.contract_id != nil
      end)

    {:noreply, %{state | reserves: new_reserves, pending_deliveries: pending}}
  end

  # --- Private ---

  defp degrade_condition(state) do
    new_condition = max(state.condition - @condition_decay_per_tick, 0.0)
    state = %{state | condition: new_condition}

    # Self-repair: consume tools from reserves if condition < 0.8
    if state.condition < 0.8 do
      tools = Map.get(state.reserves, :tools, 0)

      state =
        if tools <= 0 do
          # No tools in reserves — buy from local market
          buy_tools_from_market(state)
        else
          state
        end

      tools = Map.get(state.reserves, :tools, 0)

      if tools > 0 do
        repair_amount = min(0.01, 1.0 - state.condition)

        %{
          state
          | condition: min(state.condition + repair_amount, 1.0),
            reserves: Map.update(state.reserves, :tools, 0, &max(&1 - 1, 0))
        }
      else
        state
      end
    else
      state
    end
  end

  # --- Abandonment ---

  @abandonment_threshold 200 * Config.tick_multiplier()

  defp check_abandonment(state, tick) do
    tools = Map.get(state.reserves, :tools, 0)

    if state.condition < 0.1 and tools == 0 and state.credits < 100 do
      failing_since = Map.get(state, :failing_since_tick, tick)
      state = Map.put_new(state, :failing_since_tick, failing_since)

      if tick - failing_since >= @abandonment_threshold do
        Logger.info(
          "Facility #{state.name} at #{state.location} abandoned (condition: #{Float.round(state.condition, 2)})"
        )

        Simulator.Events.log(:facility_abandoned, %{
          facility_id: state.id,
          name: state.name,
          location: state.location,
          condition: state.condition,
          tick: tick
        })

        %{state | abandoned: true}
      else
        state
      end
    else
      # Condition recovered — reset failing tracker
      Map.delete(state, :failing_since_tick)
    end
  end

  # --- Reserve Restocking ---

  @restock_interval 25 * Config.tick_multiplier()

  defp maybe_restock_reserves(state, tick) when rem(tick, @restock_interval) == 0 do
    case Simulator.Agents.Agent.whereis("market-#{state.location}") do
      {:ok, market_pid} ->
        state
        |> restock_commodity(market_pid, :fuel, 500, 100)
        |> restock_commodity(market_pid, :food, 200, 50)

      :error ->
        state
    end
  end

  defp maybe_restock_reserves(state, _tick), do: state

  defp restock_commodity(state, market_pid, commodity, target, buy_amount) do
    current = Map.get(state.reserves, commodity, 0)

    if current < target and state.credits > 1000 do
      market_supply = Simulator.Agents.MarketAgent.get_supply(market_pid)
      available = Map.get(market_supply, commodity, 0)
      prices = Simulator.Agents.MarketAgent.query_prices(market_pid)
      price = Map.get(prices, commodity, 50)

      qty = min(buy_amount, available)
      cost = round(qty * price)

      if qty > 0 and state.credits >= cost do
        Simulator.Agents.MarketAgent.consume_and_produce(market_pid, %{commodity => qty}, %{})

        %{
          state
          | reserves: Map.update(state.reserves, commodity, qty, &(&1 + qty)),
            credits: state.credits - cost
        }
      else
        state
      end
    else
      state
    end
  end

  @tools_buy_amount 20

  defp buy_tools_from_market(state) do
    case Simulator.Agents.Agent.whereis("market-#{state.location}") do
      {:ok, market_pid} ->
        supply = Simulator.Agents.MarketAgent.get_supply(market_pid)
        available = Map.get(supply, :tools, 0)
        prices = Simulator.Agents.MarketAgent.query_prices(market_pid)
        price = Map.get(prices, :tools, 100)

        buy_qty = min(@tools_buy_amount, available)
        cost = round(buy_qty * price)

        if buy_qty > 0 and state.credits >= cost do
          # Consume tools from market supply, add to facility reserves
          Simulator.Agents.MarketAgent.consume_and_produce(
            market_pid,
            %{tools: buy_qty},
            %{}
          )

          %{
            state
            | reserves: Map.update(state.reserves, :tools, buy_qty, &(&1 + buy_qty)),
              credits: state.credits - cost
          }
        else
          state
        end

      :error ->
        state
    end
  end

  defp dock_info(state) do
    %{
      facility_id: state.id,
      services: active_services(state),
      docking_fee: compute_docking_fee(state)
    }
  end

  defp active_services(%{condition: c}) when c < 0.3, do: []
  defp active_services(state), do: state.services

  # --- Remote Purchasing & Delivery Contracts ---

  @contract_check_interval 15 * Config.tick_multiplier()

  @doc false
  defp maybe_purchase_remotely(state, tick) when rem(tick, @contract_check_interval) == 0 do
    state
    |> check_and_purchase(:fuel, tick)
    |> check_and_purchase(:food, tick)
    |> check_and_purchase(:tools, tick)
  end

  defp maybe_purchase_remotely(state, _tick), do: state

  defp check_and_purchase(state, commodity, tick) do
    current = Map.get(state.reserves, commodity, 0)
    initial = Map.get(state.initial_reserves, commodity, 1)
    threshold = initial * 0.3

    # Already have enough or already have a pending delivery for this commodity
    has_pending =
      Enum.any?(state.pending_deliveries, fn pd ->
        pd.commodity == commodity and pd.contract_id == nil
      end)

    if current < threshold and not has_pending do
      needed = round(initial * 0.5)
      buy_from = find_cheapest_remote_market(state, commodity, needed)

      case buy_from do
        {market_pid, market_location, price} ->
          cargo_cost = round(needed * price)

          if state.credits >= cargo_cost do
            case Simulator.Agents.MarketAgent.reserve_goods(market_pid, %{
                   commodity: commodity,
                   quantity: needed,
                   owner_id: state.id,
                   tick: tick
                 }) do
              {:ok, reserve_id} ->
                urgency = 1.0 - current / max(initial, 1)

                pending = %{
                  reserve_id: reserve_id,
                  market_location: market_location,
                  commodity: commodity,
                  quantity: needed,
                  cargo_value: cargo_cost,
                  urgency: urgency,
                  contract_id: nil,
                  purchased_at_tick: tick
                }

                %{
                  state
                  | credits: state.credits - cargo_cost,
                    pending_deliveries: [pending | state.pending_deliveries]
                }

              {:error, _} ->
                state
            end
          else
            state
          end

        nil ->
          state
      end
    else
      state
    end
  end

  defp maybe_post_delivery_contracts(state, tick) do
    {to_post, already_posted} =
      Enum.split_with(state.pending_deliveries, &(&1.contract_id == nil))

    {posted_state, posted_deliveries} =
      Enum.reduce(to_post, {state, []}, fn pending, {s, posted_list} ->
        distance = resolve_distance(pending.market_location, s.location)

        # Delivery fee scales with distance AND volume — bulk long-haul pays well,
        # making it economical for tankers/haulers but not worth a courier's time
        base_fee = 200
        distance_fee = distance * 3
        volume_fee = pending.quantity * 0.5
        urgency_fee = round(pending.urgency * 1000)
        delivery_fee = round(base_fee + distance_fee + volume_fee + urgency_fee)
        total_payment = delivery_fee + pending.cargo_value

        if s.credits >= delivery_fee do
          case Simulator.Economy.ContractBoard.post_contract(%{
                 contract_type: "delivery",
                 requestor_type: "facility",
                 requestor_id: s.id,
                 faction_id: s.faction_id,
                 commodity: to_string(pending.commodity),
                 quantity: pending.quantity,
                 source_location: pending.market_location,
                 destination_location: s.location,
                 payment: total_payment,
                 delivery_fee: delivery_fee,
                 cargo_deposit: pending.cargo_value,
                 cargo_value: pending.cargo_value,
                 reserve_id: pending.reserve_id,
                 urgency: pending.urgency,
                 escalation_rate: 0.005 + pending.urgency * 0.01,
                 posted_at_tick: tick,
                 deadline_tick: tick + contract_deadline(pending.market_location, s.location)
               }) do
            {:ok, contract} ->
              updated = %{pending | contract_id: contract.id}
              {%{s | credits: s.credits - delivery_fee}, [updated | posted_list]}

            {:error, _} ->
              {s, [pending | posted_list]}
          end
        else
          {s, [pending | posted_list]}
        end
      end)

    # Clean up old pending deliveries (contract completed or expired > 600 ticks ago)
    all_pending =
      (posted_deliveries ++ already_posted)
      |> Enum.reject(fn pd ->
        pd.contract_id != nil and tick - pd.purchased_at_tick > 600 * Config.tick_multiplier()
      end)

    %{posted_state | pending_deliveries: all_pending}
  end

  defp find_cheapest_remote_market(state, commodity, min_quantity) do
    local_market_id = "market-#{state.location}"

    reachable =
      Simulator.World.Travel.reachable_from(state.location)
      |> Enum.flat_map(fn loc ->
        market_id = "market-#{loc}"

        if market_id != local_market_id do
          case Simulator.Agents.Agent.whereis(market_id) do
            {:ok, pid} -> [{pid, loc}]
            :error -> []
          end
        else
          []
        end
      end)

    # Query each market for price and supply
    candidates =
      Enum.flat_map(reachable, fn {pid, location} ->
        try do
          market_state = Simulator.Agents.MarketAgent.get_state(pid)
          price = Map.get(market_state.prices, commodity)
          supply = Map.get(market_state.supply, commodity, 0)

          if price && supply >= min_quantity do
            [{pid, location, price}]
          else
            []
          end
        catch
          :exit, _ -> []
        end
      end)

    # Pick cheapest
    case Enum.sort_by(candidates, &elem(&1, 2)) do
      [{pid, location, price} | _] -> {pid, location, price}
      [] -> nil
    end
  end

  # --- Courier Contracts (zero-deposit, for broke ships) ---

  defp maybe_post_courier_contracts(state, tick) when rem(tick, @contract_check_interval) == 0 do
    # Only post if we have contract slots available
    active = Simulator.Economy.ContractBoard.active_count_for(state.id)

    if active < 4 do
      post_courier_contract(state, tick)
    else
      state
    end
  end

  defp maybe_post_courier_contracts(state, _tick), do: state

  # --- Crew Missions ---
  #
  # Facilities periodically post themed missions (security detail, heavy
  # maintenance, harvest help, etc.) for ships whose whole crew takes
  # the job. The mission templates live in MissionCatalog; the facility
  # picks one that matches its type, escrows the payment from its own
  # treasury, and the winning ship earns payout + faction rep + a small
  # skill-growth bump for the crew on completion.

  @crew_mission_interval 200 * Config.tick_multiplier()
  @crew_mission_post_chance 0.25
  @crew_mission_treasury_buffer 1_000
  @crew_mission_deadline 300 * Config.tick_multiplier()

  defp maybe_post_crew_missions(state, tick) when rem(tick, @crew_mission_interval) == 0 do
    if should_post_crew_mission?(state) and :rand.uniform() <= @crew_mission_post_chance do
      post_crew_mission(state, tick)
    else
      state
    end
  end

  defp maybe_post_crew_missions(state, _tick), do: state

  # Only post if we have an unshared template pool and the treasury is
  # healthy enough to escrow one. We also cap at 1 active crew mission
  # per facility so the ContractBoard isn't dominated by stale crew
  # missions and delivery contracts stay visible.
  defp should_post_crew_mission?(state) do
    templates = Simulator.Economy.MissionCatalog.for_facility_type(state.type)

    templates != [] and
      state.credits > default_mission_payment(templates) + @crew_mission_treasury_buffer and
      active_crew_missions_for(state.id) == 0
  end

  defp default_mission_payment(templates) do
    templates |> Enum.map(& &1.base_payment) |> Enum.max(fn -> 0 end)
  end

  defp active_crew_missions_for(facility_id) do
    Simulator.Economy.ContractBoard.contracts_for(facility_id)
    |> Enum.count(fn c ->
      c.contract_type == "crew_mission" and
        c.status in ["posted", "accepted", "in_progress", "picked_up", "in_transit"]
    end)
  end

  defp post_crew_mission(state, tick) do
    templates = Simulator.Economy.MissionCatalog.for_facility_type(state.type)
    template = Enum.random(templates)

    attrs = %{
      contract_type: "crew_mission",
      requestor_type: "facility",
      requestor_id: state.id,
      faction_id: state.faction_id,
      source_location: state.location,
      destination_location: state.location,
      mission_category: to_string(template.category),
      display_name: template.display_name,
      required_skill: to_string(template.required_skill),
      duration_ticks: template.duration_ticks,
      skill_gain: template.skill_gain,
      payment: template.base_payment,
      min_reputation: 20,
      faction_bonus: 1.2,
      urgency: 0.0,
      escalation_rate: 0.0,
      posted_at_tick: tick,
      deadline_tick: tick + @crew_mission_deadline
    }

    case Simulator.Economy.ContractBoard.post_contract(attrs) do
      {:ok, _contract} ->
        # Escrow the payment out of the facility treasury. We debit now so
        # the facility can't accidentally double-post beyond its means;
        # the shared contract-completion path credits the ship directly.
        %{state | credits: state.credits - template.base_payment}

      {:error, _} ->
        state
    end
  end

  defp post_courier_contract(state, tick) do
    # Find a nearby market with excess supply of something
    reachable = Simulator.World.Travel.reachable_from(state.location)
    nearby = Enum.take(Enum.shuffle(reachable), 3)

    source =
      Enum.find_value(nearby, fn loc ->
        case Simulator.Agents.Agent.whereis("market-#{loc}") do
          {:ok, pid} ->
            supply = Simulator.Agents.MarketAgent.get_supply(pid)

            # Find a commodity with excess supply (> 100)
            excess =
              Enum.find(supply, fn {_commodity, qty} ->
                is_number(qty) and qty > 100
              end)

            if excess do
              {commodity, _qty} = excess
              distance = resolve_distance(loc, state.location)
              {loc, pid, commodity, distance}
            end

          :error ->
            nil
        end
      end)

    case source do
      {source_loc, market_pid, commodity, distance} ->
        quantity = Enum.random(10..30)
        delivery_fee = round(200 + distance * 2)

        # Reserve the goods at the source market (small amount, from supply)
        case Simulator.Agents.MarketAgent.reserve_goods(market_pid, %{
               commodity: commodity,
               quantity: quantity,
               owner_id: state.id,
               tick: tick
             }) do
          {:ok, reserve_id} ->
            case Simulator.Economy.ContractBoard.post_contract(%{
                   contract_type: "courier",
                   requestor_type: "facility",
                   requestor_id: state.id,
                   faction_id: state.faction_id,
                   commodity: to_string(commodity),
                   quantity: quantity,
                   source_location: source_loc,
                   destination_location: state.location,
                   payment: delivery_fee,
                   delivery_fee: delivery_fee,
                   cargo_deposit: 0,
                   cargo_value: 0,
                   reserve_id: reserve_id,
                   urgency: 0.2,
                   escalation_rate: 0.002,
                   posted_at_tick: tick,
                   deadline_tick: tick + contract_deadline(source_loc, state.location)
                 }) do
              {:ok, _contract} ->
                state

              {:error, _} ->
                # Release the reservation if contract posting failed
                Simulator.Agents.MarketAgent.release_reserved(market_pid, reserve_id)
                state
            end

          {:error, _} ->
            state
        end

      nil ->
        state
    end
  end

  defp resolve_distance(from, to) do
    case Simulator.World.Travel.travel_time(from, to) do
      {:ok, ticks} -> ticks
      {:error, _} -> 100
    end
  end

  # --- Dynamic Pricing ---

  @base_docking_fee 30

  defp compute_docking_fee(state) do
    occupancy = length(state.docked_ships) / max(state.docking_capacity, 1)
    condition_factor = max(state.condition, 0.3)
    reputation_factor = state.reputation / 50.0

    round(@base_docking_fee * (1 + occupancy) * condition_factor * reputation_factor)
  end

  @base_fuel_markup 1.05

  defp compute_refuel_price(state) do
    initial_fuel = Map.get(state.initial_reserves, :fuel, 5000)
    current_fuel = Map.get(state.reserves, :fuel, 0)
    reserves_ratio = current_fuel / max(initial_fuel, 1)

    # Use commodity BASE price, not volatile market price.
    # Facility fuel is from reserves, priced at cost + markup.
    base_price = Simulator.Economy.Commodities.base_price(:fuel)

    # Scarcity: up to 1.5x when reserves are low
    scarcity_factor = 1.0 + max(1.0 - reserves_ratio, 0.0) * 0.5

    max(round(base_price * scarcity_factor * @base_fuel_markup), 1)
  end
end
