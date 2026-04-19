defmodule Simulator.Agents.ShipAgent do
  @moduledoc """
  A vessel that moves between locations, carries cargo, and makes
  autonomous trade decisions.

  Ships are the circulatory system of the economy. Each tick, a ship
  follows this decision tree:

  1. **In transit?** → consume fuel, wait for arrival
  2. **Just arrived?** → update location, query local market prices
  3. **Has a plan?** → execute next step (buy, sell, travel)
  4. **No plan?** → generate candidates, pick best, commit

  Ships use multi-step plans (see `Simulator.Agents.ShipAgent.Plan`) to
  avoid jittery single-tick reactions. Price memory is intentionally
  stale — ships only know prices from locations they've visited.
  """

  use Simulator.Agents.Agent

  require Logger

  alias Simulator.Agents.CrewComplement

  # --- Public API ---

  @doc """
  Returns the full ship state. Used by the dashboard inspector.
  """
  @spec get_state(pid()) :: map()
  def get_state(pid) do
    GenServer.call(pid, :get_state)
  end

  @doc """
  Returns the ship's current location, or nil if in transit.
  """
  @spec get_location(pid()) :: String.t() | nil
  def get_location(pid) do
    GenServer.call(pid, :get_location)
  end

  @doc """
  Calculates personality-driven credit reserve.

  Base 500 + up to 1500 scaled by safety personality trait.
  A cautious ship (safety=1.0) reserves 2000; a reckless one (safety=0.0) reserves 500.
  """
  @spec ideal_credit_reserve(map()) :: non_neg_integer()
  def ideal_credit_reserve(personality) do
    safety_weight = get_in(personality, [:safety]) || 0.5
    round(500 + safety_weight * 1500)
  end

  # --- Agent Callbacks ---

  @impl Simulator.Agents.Agent
  def agent_type, do: :ship

  @impl Simulator.Agents.Agent
  def init_agent(config) do
    {:ok, build_initial_state(config)}
  end

  alias Simulator.AI.{BehaviorTree, Utility}
  alias Simulator.Agents.ShipAgent.Goals

  @defaults %{
    name: nil,
    class: :freighter,
    location: nil,
    cargo: %{},
    cargo_capacity: 500,
    passenger_capacity: 10,
    fuel: 100.0,
    fuel_capacity: 100.0,
    fuel_consumption_rate: 0.5,
    credits: 5_000,
    efficiency: 1.0,
    known_prices: %{},
    crew_roles: [:pilot, :engineer, :trader, :medic, :general],
    system_id: "system-sol",
    universe_offset: {0.0, 0.0},
    speed_modifier: 1.0,
    faction_id: "independent",
    faction_reputation: %{},
    personality: nil
  }

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

  defp build_initial_state(config) do
    c = Map.merge(@defaults, config)
    personality = c.personality || Simulator.AI.Personality.random_ship_personality()

    %{
      id: c.id,
      name: c.name || c.id,
      class: c.class,
      system_id: c.system_id,
      universe_offset: c.universe_offset,
      location: c.location,
      transit: nil,
      cargo: c.cargo,
      cargo_capacity: c.cargo_capacity,
      passenger_capacity: c.passenger_capacity,
      # Live count of passengers aboard (at most passenger_capacity).
      # Parallel dimension to cargo — passengers don't occupy cargo space.
      passengers: c[:passengers] || 0,
      fuel: c.fuel,
      fuel_capacity: c.fuel_capacity,
      fuel_consumption_rate: c.fuel_consumption_rate,
      credits: c.credits,
      efficiency: c.efficiency,
      speed_modifier: c.speed_modifier,
      faction_id: c.faction_id,
      faction_reputation: c.faction_reputation,
      personality: personality,
      docked_at: nil,
      current_goal: nil,
      current_bt: nil,
      available_contracts: [],
      active_contract: nil,
      memory: %{known_prices: c.known_prices, visited: [], blacklist: []},
      # Restore persisted crew when present (skills accumulated from
      # crew missions, morale/hunger/fatigue drift, etc.); otherwise
      # spin up a fresh complement from roles.
      crew: restore_crew(c),
      cargo_op: nil,
      position: c[:position] || {0.0, 0.0},
      broke_strikes: c[:broke_strikes] || 0,
      # Tick when each commodity in cargo was first received. Used to detect
      # hoarding (stacks that never move) and force-sell after a threshold.
      cargo_age: c[:cargo_age] || %{},
      # Consecutive ticks the ship's selected goal has been :idle. Drives the
      # cascade to :explore or :station_job after the ship oscillates.
      idle_ticks: c[:idle_ticks] || 0,
      # Counter analogous to broke_strikes but tripped by stuck cargo; 3
      # strikes → decommission with a fresh personality.
      hoard_strikes: c[:hoard_strikes] || 0,
      __db_id__: c[:db_id],
      __agent_type__: :ship
    }
  end

  @impl Simulator.Agents.Agent
  alias Simulator.Simulation.Config

  @max_broke_strikes 3
  @max_hoard_strikes 3
  @broke_check_interval 100 * Config.tick_multiplier()
  # How old a cargo stack must be before we force_sell / count a hoard strike.
  # At ~7 tps, 50 game ticks ≈ 7 real seconds; scale keeps this in wall-clock.
  @cargo_age_force_sell 50 * Config.tick_multiplier()
  @cargo_age_hoard_strike 150 * Config.tick_multiplier()
  # Financial-pressure threshold (credits) that triggers the broke lifeline.
  # Must be generous enough that a ship needing fuel gets help before it hits
  # the broke_strikes decommission path.
  @broke_lifeline_credits 500

  def handle_tick(tick, state) do
    # --- Broke check: ships that can't recover get recycled ---
    state = check_broke_status(state, tick)

    # --- Hoard check: ships sitting on stale cargo get recycled too ---
    state = check_hoard_status(state, tick)

    # --- Crew tick: needs, morale, efficiency ---
    docked = state.docked_at != nil
    crew = CrewComplement.tick(state.crew, tick, docked: docked)
    state = %{state | crew: crew, efficiency: CrewComplement.efficiency(crew)}

    # --- Price observation: learn local market prices when at a location ---
    state = observe_local_prices(state, tick)

    # --- Contract Discovery: see what's available when at a location ---
    state =
      if state.location && state.current_bt == nil do
        # Minimum search distance ensures ships with low fuel still find
        # contracts at nearby locations (or at their own location)
        search_distance = max(round(state.fuel * 2), 50)

        contracts =
          Simulator.Economy.ContractBoard.query_contracts(
            from: state.location,
            max_distance: search_distance,
            faction_reputation: state.faction_reputation,
            limit: 10
          )

        %{state | available_contracts: contracts}
      else
        state
      end

    # --- Stale cargo op cleanup: clear ops that completed 2+ ticks ago ---
    # The owning action should clear on completion, but if BT advanced
    # past it (sequence moved to next node), the op gets orphaned.
    # Grace period of 2 ticks avoids clearing an op the same tick it completes.
    state =
      case state.cargo_op do
        %{completion_tick: t} when tick > t + 2 ->
          %{state | cargo_op: nil}

        _ ->
          state
      end

    # --- Morale gate: low morale forces shore leave ---
    state =
      cond do
        # Crew morale critically low — force rest, override any current goal
        CrewComplement.needs_shore_leave?(state.crew) and state.current_goal != :rest_crew ->
          event = %{
            ship_id: state.id,
            name: state.name,
            from_goal: state.current_goal,
            to_goal: :rest_crew,
            tick: tick
          }

          Simulator.Events.log(:goal_changed, event)
          Simulator.Events.broadcast("ship_events", :goal_changed, event)

          bt = Goals.build_tree(:rest_crew, state, tick)
          %{state | current_goal: :rest_crew, current_bt: bt}

        # Currently on shore leave — stay until morale fully recovered
        state.current_goal == :rest_crew and
            not CrewComplement.shore_leave_complete?(state.crew) ->
          state

        true ->
          state
      end

    # --- Utility AI: select best goal ---
    state =
      if state.current_bt == nil or not in_transit?(state) do
        # Skip goal re-evaluation while on mandatory shore leave
        if state.current_goal == :rest_crew and
             not CrewComplement.shore_leave_complete?(state.crew) do
          state
        else
          considerations = Goals.evaluate_considerations(state)

          {utility_goal, _score} =
            Utility.best_action(Goals.available_actions(), considerations, state.personality)

          # Reflex overrides for hoarding and broke lifeline — these force a
          # recovery goal without waiting for utility scoring to surface it.
          best_goal = apply_goal_overrides(utility_goal, state, tick)

          state =
            if best_goal == :idle do
              Map.update(state, :idle_ticks, 1, &(&1 + 1))
            else
              Map.put(state, :idle_ticks, 0)
            end

          if best_goal != state.current_goal or state.current_bt == nil do
            if best_goal != nil and best_goal != :idle and best_goal != state.current_goal do
              event = %{
                ship_id: state.id,
                name: state.name,
                from_goal: state.current_goal,
                to_goal: best_goal,
                tick: tick
              }

              Simulator.Events.log(:goal_changed, event)
              Simulator.Events.broadcast("ship_events", :goal_changed, event)
            end

            bt = Goals.build_tree(best_goal, state, tick)
            %{state | current_goal: best_goal, current_bt: bt}
          else
            state
          end
        end
      else
        state
      end

    # --- Behavior Tree: execute current step ---
    state =
      case state.current_bt do
        nil ->
          state

        bt ->
          bb = %{state: state, tick: tick}

          case BehaviorTree.tick(bt, bb) do
            {:running, new_bt, %{state: new_state}} ->
              %{new_state | current_bt: new_bt}

            {:success, _bt, %{state: new_state}} ->
              %{new_state | current_bt: nil, current_goal: nil, cargo_op: nil}

            {:failure, _bt, %{state: new_state}} ->
              # Release any accepted contract back to the board
              new_state = release_active_contract(new_state)
              %{new_state | current_bt: nil, current_goal: nil, cargo_op: nil}
          end
      end

    state = deduct_operating_costs(state)
    state = report_position(state, tick)
    update_metadata(state)

    {:ok, state}
  end

  # Push ship metadata to ETS for the simulation:ship_states delta broadcast.
  # Game clients read these via channel and don't need to poll /api/report.
  # Includes everything the inspector/HUD needs to stay fresh.
  defp update_metadata(state) do
    bt_action =
      case state.current_bt do
        nil -> nil
        bt -> bt |> Simulator.AI.BehaviorTree.current_action() |> to_string()
      end

    Simulator.Spatial.ShipMetadata.put(state.id, %{
      name: state.name,
      class: state.class,
      faction_id: state.faction_id,
      location: state.location,
      docked_at: state.docked_at,
      transit: state.transit,
      goal: state.current_goal,
      bt: bt_action,
      cargo: state.cargo,
      cargo_capacity: state.cargo_capacity,
      passengers: Map.get(state, :passengers, 0),
      passenger_capacity: Map.get(state, :passenger_capacity, 0),
      fuel: Float.round(state.fuel, 1),
      fuel_capacity: state.fuel_capacity,
      credits: state.credits,
      broke_strikes: Map.get(state, :broke_strikes, 0),
      hoard_strikes: Map.get(state, :hoard_strikes, 0),
      idle_ticks: Map.get(state, :idle_ticks, 0),
      cargo_age: Map.get(state, :cargo_age, %{}),
      crew: %{
        size: state.crew.size,
        morale: round(state.crew.morale),
        health: round(state.crew.health),
        hunger: round(state.crew.hunger),
        fatigue: round(state.crew.fatigue),
        current_task: state.crew.current_task
      }
    })
  end

  # --- Persistence ---

  @impl Simulator.Agents.Agent
  def persist_state(state) do
    if db_id = state[:__db_id__] do
      location_id =
        if state.location do
          case Simulator.Repo.get_by(Simulator.Schemas.Location, name: state.location) do
            %{id: id} -> id
            nil -> nil
          end
        end

      {px, py} = state[:position] || {0.0, 0.0}

      Simulator.Repo.get!(Simulator.Schemas.Ship, db_id)
      |> Simulator.Schemas.Ship.changeset(%{
        credits: round(state.credits),
        fuel: state.fuel,
        cargo: stringify_keys(state.cargo),
        efficiency: state.efficiency,
        location_id: location_id,
        position_x: px,
        position_y: py,
        state: %{
          "transit" => state.transit,
          "personality" => state.personality,
          "faction_reputation" => state.faction_reputation,
          "memory" => %{
            "known_prices" => stringify_nested_prices(state.memory.known_prices),
            "visited" => state.memory.visited,
            "blacklist" => state.memory.blacklist
          },
          "current_goal" => state.current_goal,
          "docked_at" => state.docked_at,
          "broke_strikes" => state.broke_strikes,
          "passengers" => Map.get(state, :passengers, 0),
          "crew" => Simulator.Agents.CrewComplement.serialize(state.crew),
          "cargo_age" => stringify_keys(state.cargo_age),
          "idle_ticks" => state.idle_ticks,
          "hoard_strikes" => state.hoard_strikes,
          # Store just the contract ID — the ContractBoard (ETS-backed)
          # rebuilds empty on boot today, so a restored ship with an
          # active_contract_id whose contract is no longer on the board
          # drops the reference and re-plans. Becomes load-bearing once
          # ContractBoard persistence lands.
          "active_contract_id" =>
            case state.active_contract do
              %{id: id} -> id
              _ -> nil
            end
        }
      })
      |> Simulator.Repo.update!()
    end

    :ok
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  defp stringify_keys(other), do: other

  defp stringify_nested_prices(prices) when is_map(prices) do
    Map.new(prices, fn {location, commodities} ->
      string_commodities =
        Map.new(commodities, fn
          {commodity, %{price: p, tick: t}} ->
            {to_string(commodity), %{"price" => p, "tick" => t}}

          {commodity, price} ->
            {to_string(commodity), price}
        end)

      {to_string(location), string_commodities}
    end)
  end

  defp stringify_nested_prices(other), do: other

  # --- GenServer Call Handlers ---

  @impl GenServer
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  def handle_call(:get_location, _from, state) do
    {:reply, state.location, state}
  end

  @impl GenServer
  def handle_cast(:force_undock, state) do
    # Called when the facility a ship is docked at gets destroyed via
    # the admin API. Keep the ship's location intact so it can sail
    # somewhere else, but clear docked_at and abort any in-flight
    # cargo/op + BT so it re-plans cleanly next tick.
    new_state =
      state
      |> Map.put(:docked_at, nil)
      |> Map.put(:cargo_op, nil)
      |> Map.put(:current_bt, nil)
      |> Map.put(:current_goal, nil)

    {:noreply, new_state}
  end

  # --- Broke / Decommission ---

  defp check_broke_status(state, tick) when rem(tick, @broke_check_interval) == 0 do
    broke_strikes = Map.get(state, :broke_strikes, 0)

    cond do
      # Ship has credits — reset strikes
      state.credits > 500 ->
        Map.put(state, :broke_strikes, 0)

      # Ship is broke — increment strikes
      state.credits <= 0 ->
        new_strikes = broke_strikes + 1

        if new_strikes >= @max_broke_strikes do
          decommission(state, tick)
        else
          Logger.warning("Ship #{state.name} broke strike #{new_strikes}/#{@max_broke_strikes}")

          Map.put(state, :broke_strikes, new_strikes)
        end

      # Low credits but not zero — no strike but warn
      true ->
        state
    end
  end

  defp check_broke_status(state, _tick), do: state

  # --- Hoarding: retire ships sitting on stale cargo ---

  defp check_hoard_status(state, tick) when rem(tick, @broke_check_interval) == 0 do
    strikes = Map.get(state, :hoard_strikes, 0)

    cond do
      # No cargo or cargo is fresh — reset the counter.
      not has_cargo?(state) or cargo_max_age(state, tick) < @cargo_age_hoard_strike ->
        Map.put(state, :hoard_strikes, 0)

      # Cargo is old — strike the ship, and recycle at max strikes.
      true ->
        new_strikes = strikes + 1

        if new_strikes >= @max_hoard_strikes do
          decommission(state, tick, :hoarding)
        else
          Logger.warning(
            "Ship #{state.name} hoard strike #{new_strikes}/#{@max_hoard_strikes} — " <>
              "cargo #{inspect(Map.keys(state.cargo))} aging"
          )

          Map.put(state, :hoard_strikes, new_strikes)
        end
    end
  end

  defp check_hoard_status(state, _tick), do: state

  defp has_cargo?(state) do
    Enum.any?(state.cargo, fn {_c, qty} -> qty > 0 end)
  end

  # Returns the age (in ticks) of the oldest cargo stack. 0 when hold is empty.
  defp cargo_max_age(state, tick) do
    ages = Map.get(state, :cargo_age, %{})

    case Map.values(ages) do
      [] -> 0
      stamps -> tick - Enum.min(stamps)
    end
  end

  # --- Goal Overrides ---

  # Injects reflex goals that bypass utility scoring when the ship is in
  # distress. Returns the final goal atom to commit to this tick.
  defp apply_goal_overrides(utility_goal, state, tick) do
    cond do
      # In transit — overrides shouldn't interrupt travel.
      in_transit?(state) ->
        utility_goal

      # Hoarder: cargo stack aged past the force-sell threshold. Dump it.
      has_cargo?(state) and cargo_max_age(state, tick) > @cargo_age_force_sell ->
        :sell_cargo

      # Broke with cargo: liquidate to get liquid credits.
      state.credits < @broke_lifeline_credits and has_cargo?(state) ->
        :sell_cargo

      # Broke, no cargo, docked somewhere — take a station job for fuel money.
      state.credits < @broke_lifeline_credits and is_binary(state.docked_at) ->
        :station_job

      # Ship has been oscillating on idle for too long — kick to exploration.
      utility_goal == :idle and Map.get(state, :idle_ticks, 0) >= 10 ->
        :explore

      true ->
        utility_goal
    end
  end

  defp decommission(state, tick, reason \\ :bankruptcy) do
    Logger.info(
      "Ship #{state.name} decommissioned (#{reason}). " <>
        "Recycling with new personality at #{state.location || "current location"}."
    )

    # Sell any remaining cargo at current location
    cargo_value =
      Enum.reduce(state.cargo, 0, fn {commodity, qty}, acc ->
        price = Simulator.Economy.Commodities.base_price(commodity)
        acc + round(qty * price)
      end)

    # Send salvage value to the local facility
    if state.location do
      case Simulator.Agents.Agent.whereis("facility-#{state.location}") do
        {:ok, pid} ->
          GenServer.cast(pid, {:market_revenue, cargo_value + 1000})

        :error ->
          Logger.warning(
            "Ship #{state.name}: salvage payment dropped, facility-#{state.location} not found"
          )
      end
    end

    # Pick a random hub location to respawn at (fresh start somewhere new)
    all_locations =
      Simulator.World.Travel.reachable_from(state.location || "earth-station")
      |> Kernel.++([state.location || "earth-station"])

    new_location = Enum.random(all_locations)

    # Respawn with new personality and fresh credits
    new_personality = Simulator.AI.Personality.random_ship_personality()

    class_stats =
      Map.get(
        Simulator.Simulation.Config.ship_classes(),
        state.class,
        Simulator.Simulation.Config.ship_classes().freighter
      )

    Logger.info("Ship #{state.name} recycled → new personality, relocating to #{new_location}")

    # Record in retirement ledger for dashboard
    Simulator.Simulation.RetirementLedger.record(%{
      ship_id: state.id,
      name: state.name,
      class: state.class,
      faction_id: state.faction_id,
      personality: state.personality,
      final_location: state.location,
      new_location: new_location,
      final_credits: state.credits,
      cargo_value: cargo_value,
      crew_size: state.crew.size,
      crew_morale: round(state.crew.morale),
      tick: tick,
      reason: reason
    })

    decommission_event = %{
      ship_id: state.id,
      name: state.name,
      tick: tick,
      reason: reason,
      new_location: new_location
    }

    Simulator.Events.broadcast("ship:#{state.id}", :ship_decommissioned, decommission_event)
    Simulator.Events.broadcast("ship_events", :ship_decommissioned, decommission_event)
    Simulator.Events.log(:ship_decommissioned, decommission_event)

    # Bootstrap price knowledge at the new location so the ship can
    # immediately plan trades instead of idling with empty memory
    bootstrap_prices = bootstrap_local_prices(new_location, tick)

    %{
      state
      | credits: class_stats.cargo_capacity * 10,
        cargo: %{},
        cargo_age: %{},
        fuel: state.fuel_capacity,
        location: new_location,
        transit: nil,
        docked_at: nil,
        personality: new_personality,
        current_goal: nil,
        current_bt: nil,
        available_contracts: [],
        active_contract: nil,
        broke_strikes: 0,
        hoard_strikes: 0,
        idle_ticks: 0,
        efficiency: 1.0,
        cargo_op: nil,
        crew: CrewComplement.new(class_stats.crew_roles),
        memory: %{known_prices: bootstrap_prices, visited: [], blacklist: []}
    }
  end

  defp bootstrap_local_prices(location, tick) do
    case Simulator.Agents.Agent.whereis("market-#{location}") do
      {:ok, pid} ->
        prices = Simulator.Agents.MarketAgent.query_prices(pid)

        stamped =
          Map.new(prices, fn {commodity, price} ->
            {commodity, %{price: price, tick: tick}}
          end)

        %{location => stamped}

      :error ->
        %{}
    end
  end

  # --- Contract Cleanup ---

  defp release_active_contract(%{active_contract: nil} = state), do: state

  defp release_active_contract(%{active_contract: contract} = state) do
    # Try to expire/cancel the contract so it returns to the board
    if contract[:id] do
      Simulator.Economy.ContractBoard.deliver(contract.id, 0)
    end

    %{state | active_contract: nil}
  end

  # --- Price Observation ---

  @price_refresh_interval 20 * Config.tick_multiplier()

  defp observe_local_prices(state, tick) do
    location = state.location

    if location do
      # Always refresh local market prices (they change every tick)
      state = update_price_at(state, location, tick)

      # When idle, also scan nearby markets to find opportunities
      # This prevents ships from being stuck with stale price data
      if state.current_goal == nil and rem(tick, @price_refresh_interval) == 0 do
        nearby = Simulator.World.Travel.reachable_from(location)

        Enum.reduce(Enum.take(nearby, 5), state, fn loc, s ->
          update_price_at(s, loc, tick)
        end)
      else
        state
      end
    else
      state
    end
  end

  defp update_price_at(state, location, tick) do
    case Simulator.Agents.Agent.whereis("market-#{location}") do
      {:ok, pid} ->
        prices = Simulator.Agents.MarketAgent.query_prices(pid)

        updated_prices =
          Map.new(prices, fn {commodity, price} ->
            {commodity, %{price: price, tick: tick}}
          end)

        put_in(state, [:memory, :known_prices, location], updated_prices)

      :error ->
        state
    end
  end

  # --- Transit ---

  defp in_transit?(%{transit: nil}), do: false
  defp in_transit?(_state), do: true

  # --- Operating Costs ---

  @base_crew_wage 3 * Config.tick_scale()

  # Goals where the crew is on the facility's payroll, not the ship's —
  # skip the ship-side wage deduction so a hauler with 8 crew doesn't
  # bleed away its :station_job earnings mid-job.
  @facility_payroll_goals [:station_job, :do_crew_mission]

  defp deduct_operating_costs(state) do
    # Wages only paid when docked — crew signed up for the voyage.
    # Unless the ship is taking facility-paid work, in which case the
    # station is covering the crew for the duration.
    facility_covering? = state.current_goal in @facility_payroll_goals

    if state.docked_at != nil and not facility_covering? do
      wage_per_crew = compute_local_wage(state)
      total_wage = state.crew.size * wage_per_crew

      crew = CrewComplement.pay_wages(state.crew, wage_per_crew)
      %{state | crew: crew, credits: max(round(state.credits - total_wage), 0)}
    else
      state
    end
  end

  defp compute_local_wage(_state) do
    # TODO: query local population for labor market conditions
    # For now: base wage (will fluctuate with local economy later)
    @base_crew_wage
  end

  # --- Position Reporting ---

  defp report_position(state, tick) do
    cond do
      # Docked or at a location — snap to facility position (universe coords)
      # This ensures ships render at the dock, not the body center.
      state.location != nil ->
        case facility_position_for_location(state.location) do
          {x, y} ->
            Simulator.Spatial.ChunkManager.update_position(state.id, x, y)
            %{state | position: {x, y}}

          nil ->
            # No facility position yet (early boot) — fall back to body center
            compute_from_body(state, tick)
        end

      # In transit — interpolate between facility positions when possible
      state.transit != nil ->
        compute_transit_position(state, tick)

      true ->
        keep_last_position(state)
    end
  end

  defp facility_position_for_location(location) do
    # Find a facility at this location and use its (offset) position
    case Simulator.Agents.Agent.whereis("facility-#{location}") do
      {:ok, _pid} ->
        Simulator.Spatial.ChunkManager.get_position("facility-#{location}")

      :error ->
        nil
    end
  end

  defp compute_transit_position(state, tick) do
    # Use facility positions for transit endpoints so ships leave from the dock
    from_pos = facility_position_for_location(state.transit.from)
    to_pos = facility_position_for_location(state.transit.to)

    cond do
      from_pos && to_pos ->
        {x, y} =
          Simulator.Spatial.PositionTracker.interpolate(
            from_pos,
            to_pos,
            state.transit.departure_tick,
            state.transit.arrival_tick,
            tick
          )

        Simulator.Spatial.ChunkManager.update_position(state.id, x, y)
        %{state | position: {x, y}}

      true ->
        # Fall back to body-position interpolation
        body_positions = get_all_body_positions()

        case Simulator.Spatial.PositionTracker.ship_position(state, body_positions, tick) do
          {x, y} ->
            Simulator.Spatial.ChunkManager.update_position(state.id, x, y)
            %{state | position: {x, y}}

          nil ->
            keep_last_position(state)
        end
    end
  end

  defp compute_from_body(state, tick) do
    body_positions = get_system_body_positions(state.system_id, state.universe_offset)

    case Simulator.Spatial.PositionTracker.ship_position(state, body_positions, tick) do
      {x, y} ->
        {ox, oy} = state.universe_offset
        px = ox + x
        py = oy + y
        Simulator.Spatial.ChunkManager.update_position(state.id, px, py)
        %{state | position: {px, py}}

      nil ->
        keep_last_position(state)
    end
  end

  defp keep_last_position(state) do
    {px, py} = state.position
    Simulator.Spatial.ChunkManager.update_position(state.id, px, py)
    state
  end

  # Body positions for a single system (local coordinates)
  defp get_system_body_positions(system_id, _offset) do
    case Simulator.Agents.Agent.whereis(system_id) do
      {:ok, pid} ->
        Simulator.World.System.get_body_positions(pid)
        |> Map.new(fn {body_id, %{x: x, y: y}} -> {body_id, {x, y}} end)

      :error ->
        %{}
    end
  end

  # Body positions from ALL systems in universe coordinates (for inter-system transit)
  defp get_all_body_positions do
    Simulator.World.Registry.system_ids()
    |> Enum.reduce(%{}, fn system_id, acc ->
      {ox, oy} = Simulator.World.Registry.universe_offset(system_id)

      case Simulator.Agents.Agent.whereis(system_id) do
        {:ok, pid} ->
          Simulator.World.System.get_body_positions(pid)
          |> Enum.reduce(acc, fn {body_id, %{x: x, y: y}}, inner ->
            Map.put(inner, body_id, {ox + x, oy + y})
          end)

        :error ->
          acc
      end
    end)
  end
end
