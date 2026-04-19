defmodule Simulator.Agents.ShipAgent.Goals do
  @moduledoc """
  Defines available goals for ships and builds behavior trees to execute them.

  This is the bridge between the Utility AI (which selects the best goal)
  and the Behavior Tree engine (which executes the steps). Each goal function
  returns a `{action_spec, bt_builder}` tuple:

  - `action_spec` — the utility scoring specification (which considerations matter)
  - `bt_builder` — a function that builds the BT given the ship's current state

  ## Available Goals

    * `:trade_run` — buy at current location, sell at destination (or reverse)
    * `:fulfill_delivery` — trucker: pick up pre-purchased cargo, deliver for fee + deposit
    * `:fulfill_contract` — legacy: buy goods and deliver for payment
    * `:fulfill_passenger_transport` — courier: pick up passengers at one pop, deliver to another
    * `:refuel` — dock and refuel at current location
    * `:rest_crew` — dock and idle to let crew recover
    * `:explore` — visit new locations
    * `:sell_cargo` — sell current cargo when broke
    * `:station_job` — short paid task at the docked facility (broke lifeline)
    * `:do_crew_mission` — richer facility-posted mission (security, maintenance, etc.) with skill growth
    * `:idle` — do nothing for a while
  """

  alias Simulator.AI.{BehaviorTree, Considerations, Utility}
  alias Simulator.Agents.ShipAgent.{Actions, Planner}

  @doc """
  Returns all available goal action specs for utility scoring.
  """
  @spec available_actions() :: [Utility.action_spec()]
  def available_actions do
    [
      {:trade_run,
       [
         {:trade_opportunity, :positive},
         {:cargo_opportunity, :positive},
         {:fuel_urgency, :negative},
         {:financial_pressure, :negative}
       ]},
      {:fulfill_delivery,
       [
         {:delivery_opportunity, :positive},
         {:deposit_affordability, :positive},
         {:faction_affinity, :positive},
         {:contract_distance_concern, :negative},
         {:fuel_urgency, :negative}
       ]},
      {:refuel,
       [
         {:fuel_urgency, :positive}
       ]},
      {:rest_crew,
       [
         {:crew_morale_concern, :positive}
       ]},
      {:fulfill_contract,
       [
         {:contract_opportunity, :positive},
         {:faction_affinity, :positive},
         {:contract_distance_concern, :negative},
         {:fuel_urgency, :negative},
         {:financial_pressure, :positive}
       ]},
      {:fulfill_passenger_transport,
       [
         {:passenger_opportunity, :positive},
         {:passenger_capacity_remaining, :positive},
         {:faction_affinity, :positive},
         {:contract_distance_concern, :negative},
         {:fuel_urgency, :negative}
       ]},
      {:station_job,
       [
         {:financial_pressure, :positive},
         {:docked_at_facility, :positive}
       ]},
      {:do_crew_mission,
       [
         {:crew_mission_opportunity, :positive},
         {:crew_mission_fit, :positive},
         {:faction_affinity, :positive},
         {:fuel_urgency, :negative},
         {:financial_pressure, :positive}
       ]},
      {:sell_cargo,
       [
         {:cargo_to_sell, :positive},
         {:financial_pressure, :positive}
       ]},
      {:explore,
       [
         {:exploration_desire, :positive},
         {:fuel_urgency, :negative},
         {:financial_pressure, :negative}
       ]},
      {:idle, []}
    ]
  end

  @doc """
  Evaluates all considerations for a ship and returns the consideration map.
  """
  @spec evaluate_considerations(map()) :: Utility.consideration_map()
  def evaluate_considerations(state) do
    %{
      fuel_urgency: Considerations.fuel_urgency(state),
      trade_opportunity: Considerations.trade_opportunity(state),
      contract_opportunity: Considerations.contract_opportunity(state),
      contract_distance_concern: Considerations.contract_distance_concern(state),
      delivery_opportunity: Considerations.delivery_opportunity(state),
      deposit_affordability: Considerations.deposit_affordability(state),
      passenger_opportunity: Considerations.passenger_opportunity(state),
      passenger_capacity_remaining: Considerations.passenger_capacity_remaining(state),
      crew_mission_opportunity: Considerations.crew_mission_opportunity(state),
      crew_mission_fit: Considerations.crew_mission_fit(state),
      faction_affinity: Considerations.faction_affinity(state),
      crew_morale_concern: Considerations.crew_morale_concern(state),
      cargo_opportunity: Considerations.cargo_opportunity(state),
      cargo_to_sell: Considerations.cargo_to_sell(state),
      exploration_desire: Considerations.exploration_desire(state),
      financial_pressure: Considerations.financial_pressure(state),
      docked_at_facility: docked_at_facility(state)
    }
  end

  # Lightweight consideration for station_job: only scored when docked.
  defp docked_at_facility(%{docked_at: docked}) when is_binary(docked), do: {1.0, :safety}
  defp docked_at_facility(_), do: {0.0, :safety}

  @doc """
  Builds a behavior tree for the selected goal.

  Uses the existing Planner for trade route evaluation, but wraps
  the result in a BT sequence instead of a Plan struct.
  """
  @spec build_tree(atom(), map(), non_neg_integer()) :: BehaviorTree.bt_node()
  def build_tree(:trade_run, state, tick) do
    # First try for a profitable plan, then fall back to break-even so idle
    # ships have a chance to make tiny margins instead of oscillating.
    plan =
      case Planner.best_plan(state, tick) do
        %{type: :trade_run} = p -> p
        _ -> Planner.best_plan(state, tick, allow_break_even: true)
      end

    case plan do
      %{type: :trade_run, steps: steps} ->
        bt_actions = Enum.map(steps, &step_to_bt_action/1)
        BehaviorTree.sequence(bt_actions)

      _ ->
        # Still nothing — try to explore somewhere new, else idle.
        build_tree(:explore, state, tick)
    end
  end

  def build_tree(:fulfill_delivery, state, _tick) do
    contracts = Map.get(state, :available_contracts, [])
    cargo_capacity = state.cargo_capacity

    # Filter to delivery contracts (have source_location and reserve_id)
    delivery_contracts =
      Enum.filter(contracts, fn c ->
        c[:source_location] != nil and c[:reserve_id] != nil and c[:delivery_fee] != nil
      end)

    # Pick best by value to THIS ship — factors in how much we can carry
    best =
      Enum.max_by(
        delivery_contracts,
        fn c ->
          fee = c.delivery_fee || 0
          dist = Map.get(c, :distance, 100)
          quantity = c.quantity || 0
          carryable = min(quantity, cargo_capacity)
          fill_ratio = carryable / max(quantity, 1)
          fee * fill_ratio / max(dist, 1)
        end,
        fn -> nil end
      )

    case best do
      nil ->
        build_tree(:idle, state, 0)

      contract ->
        source = contract.source_location
        dest = contract.destination_location

        BehaviorTree.sequence([
          BehaviorTree.action(:accept_contract, Actions.accept_contract(contract)),
          BehaviorTree.action(:travel_to_source, Actions.travel(source)),
          BehaviorTree.action(:dock_source, Actions.dock(source)),
          BehaviorTree.action(:refuel_source, Actions.refuel(source)),
          BehaviorTree.action(:pickup_cargo, Actions.pickup_cargo(contract)),
          BehaviorTree.action(:undock_source, Actions.undock(source)),
          BehaviorTree.action(:travel_to_dest, Actions.travel(dest)),
          BehaviorTree.action(:dock_dest, Actions.dock(dest)),
          BehaviorTree.action(:deliver_cargo, Actions.deliver_cargo(contract)),
          BehaviorTree.action(:refuel_dest, Actions.refuel(dest)),
          BehaviorTree.action(:undock_dest, Actions.undock(dest))
        ])
    end
  end

  def build_tree(:fulfill_passenger_transport, state, tick) do
    contracts = Map.get(state, :available_contracts, [])
    capacity = Map.get(state, :passenger_capacity, 0)

    passenger_contracts =
      Enum.filter(contracts, fn c ->
        c[:contract_type] == "passenger_transport" and
          c[:source_location] != nil and
          c[:passenger_count] != nil
      end)

    best =
      Enum.max_by(
        passenger_contracts,
        fn c ->
          pax = c[:passenger_count] || 0
          dist = Map.get(c, :distance, 100)
          carryable = min(pax, capacity)
          fill = carryable / max(pax, 1)
          (c[:payment] || 0) * fill / max(dist, 1)
        end,
        fn -> nil end
      )

    case best do
      nil ->
        # No passenger contracts right now — fall through to a trade run
        # rather than idling, so couriers don't freeze on a dry tick.
        build_tree(:trade_run, state, tick)

      contract ->
        source = contract.source_location
        dest = contract.destination_location

        BehaviorTree.sequence([
          BehaviorTree.action(:accept_contract, Actions.accept_contract(contract)),
          BehaviorTree.action(:travel_to_source, Actions.travel(source)),
          BehaviorTree.action(:dock_source, Actions.dock(source)),
          BehaviorTree.action(:refuel_source, Actions.refuel(source)),
          BehaviorTree.action(:pickup_passengers, Actions.pickup_passengers(contract)),
          BehaviorTree.action(:undock_source, Actions.undock(source)),
          BehaviorTree.action(:travel_to_dest, Actions.travel(dest)),
          BehaviorTree.action(:dock_dest, Actions.dock(dest)),
          BehaviorTree.action(:deliver_passengers, Actions.deliver_passengers(contract)),
          BehaviorTree.action(:refuel_dest, Actions.refuel(dest)),
          BehaviorTree.action(:undock_dest, Actions.undock(dest))
        ])
    end
  end

  def build_tree(:fulfill_contract, state, _tick) do
    # Only supply-shape contracts have the `:commodity`/`:quantity_remaining`
    # fields the BT below needs. Filtering here (and mirroring in
    # Considerations.contract_opportunity) keeps the goal from crashing
    # when passenger/crew-mission contracts happen to sit on the board.
    contracts =
      state
      |> Map.get(:available_contracts, [])
      |> Enum.filter(&Considerations.supply_contract?/1)

    case Enum.max_by(contracts, & &1.payment, fn -> nil end) do
      nil ->
        build_tree(:idle, state, 0)

      contract ->
        location = state.location
        dest = contract.destination_location
        commodity = String.to_existing_atom(contract.commodity)
        quantity = min(contract.quantity_remaining, state.cargo_capacity)

        BehaviorTree.sequence([
          BehaviorTree.action(:accept_contract, Actions.accept_contract(contract)),
          BehaviorTree.action(:dock, Actions.dock(location)),
          BehaviorTree.action(:refuel, Actions.refuel(location)),
          BehaviorTree.action(:buy, Actions.buy(commodity, quantity)),
          BehaviorTree.action(:undock, Actions.undock(location)),
          BehaviorTree.action(:travel, Actions.travel(dest)),
          BehaviorTree.action(:dock, Actions.dock(dest)),
          BehaviorTree.action(:deliver_contract, Actions.deliver_contract(contract, quantity)),
          BehaviorTree.action(:refuel, Actions.refuel(dest)),
          BehaviorTree.action(:undock, Actions.undock(dest))
        ])
    end
  end

  def build_tree(:sell_cargo, state, _tick) do
    location = state.location

    if location do
      # Sell everything we're carrying at the current location
      sell_steps =
        state.cargo
        |> Enum.filter(fn {_commodity, qty} -> qty > 0 end)
        |> Enum.map(fn {commodity, qty} ->
          BehaviorTree.action(:sell, Actions.sell(commodity, qty))
        end)

      if sell_steps != [] do
        BehaviorTree.sequence(
          [BehaviorTree.action(:dock, Actions.dock(location))] ++
            sell_steps ++
            [BehaviorTree.action(:undock, Actions.undock(location))]
        )
      else
        BehaviorTree.action(:idle, Actions.idle())
      end
    else
      BehaviorTree.action(:idle, Actions.idle())
    end
  end

  def build_tree(:refuel, state, _tick) do
    location = state.location

    if location do
      BehaviorTree.sequence([
        BehaviorTree.action(:dock, Actions.dock(location)),
        BehaviorTree.action(:refuel, Actions.refuel(location)),
        BehaviorTree.action(:undock, Actions.undock(location))
      ])
    else
      # In transit — wait until arrival, then refuel
      BehaviorTree.action(:wait, Actions.idle())
    end
  end

  def build_tree(:rest_crew, state, _tick) do
    location = state.location

    if location do
      BehaviorTree.sequence([
        BehaviorTree.action(:dock, Actions.dock(location)),
        BehaviorTree.action(:refuel, Actions.refuel(location)),
        BehaviorTree.action(:rest, Actions.rest_until_recovered()),
        BehaviorTree.action(:undock, Actions.undock(location))
      ])
    else
      BehaviorTree.action(:wait, Actions.idle())
    end
  end

  def build_tree(:explore, state, tick) do
    # Pick a destination the ship hasn't visited recently
    visited = get_in(state, [:memory, :visited]) || []

    destinations =
      Simulator.World.Travel.reachable_from(state.location || "")
      |> Enum.reject(&(&1 in visited))

    case destinations do
      [dest | _] ->
        location = state.location

        BehaviorTree.sequence([
          BehaviorTree.action(:dock, Actions.dock(location)),
          BehaviorTree.action(:refuel, Actions.refuel(location)),
          BehaviorTree.action(:undock, Actions.undock(location)),
          BehaviorTree.action(:travel, Actions.travel(dest)),
          BehaviorTree.action(:dock, Actions.dock(dest)),
          BehaviorTree.action(:refuel, Actions.refuel(dest)),
          BehaviorTree.action(:undock, Actions.undock(dest))
        ])

      [] ->
        build_tree(:trade_run, state, tick)
    end
  end

  def build_tree(:station_job, state, _tick) do
    location = state.docked_at || state.location

    if is_binary(location) do
      # Strip the "facility-" prefix if present (docked_at format)
      location = String.replace_prefix(location, "facility-", "")

      BehaviorTree.sequence([
        BehaviorTree.action(:dock, Actions.dock(location)),
        BehaviorTree.action(:station_job, Actions.station_job(location)),
        BehaviorTree.action(:undock, Actions.undock(location))
      ])
    else
      BehaviorTree.action(:idle, Actions.idle())
    end
  end

  def build_tree(:do_crew_mission, state, tick) do
    contracts = Map.get(state, :available_contracts, [])

    mission_contracts =
      Enum.filter(contracts, fn c -> c[:contract_type] == "crew_mission" end)

    best =
      Enum.max_by(
        mission_contracts,
        fn c -> (c[:payment] || 0) / max(c[:duration_ticks] || 1, 1) end,
        fn -> nil end
      )

    case best do
      nil ->
        # No missions to take — cascade to idle so the next tick
        # re-evaluates against a fresh contract scan.
        build_tree(:idle, state, tick)

      contract ->
        source = contract.source_location

        BehaviorTree.sequence([
          BehaviorTree.action(:accept_contract, Actions.accept_contract(contract)),
          BehaviorTree.action(:travel_to_source, Actions.travel(source)),
          BehaviorTree.action(:dock_source, Actions.dock(source)),
          BehaviorTree.action(:refuel_source, Actions.refuel(source)),
          BehaviorTree.action(:do_crew_mission, Actions.do_crew_mission(contract)),
          BehaviorTree.action(:undock_source, Actions.undock(source))
        ])
    end
  end

  def build_tree(:idle, _state, _tick) do
    BehaviorTree.action(:idle, Actions.idle())
  end

  # --- Private: Convert PlanStep to BT Action ---

  defp step_to_bt_action(%{action: :dock, at: location}) do
    BehaviorTree.action(:dock, Actions.dock(location))
  end

  defp step_to_bt_action(%{action: :undock, at: location}) do
    BehaviorTree.action(:undock, Actions.undock(location))
  end

  defp step_to_bt_action(%{action: :travel, to: destination}) do
    BehaviorTree.action(:travel, Actions.travel(destination))
  end

  defp step_to_bt_action(%{action: :buy, commodity: commodity, quantity: qty}) do
    BehaviorTree.action(:buy, Actions.buy(commodity, qty))
  end

  defp step_to_bt_action(%{action: :sell, commodity: commodity, quantity: qty}) do
    BehaviorTree.action(:sell, Actions.sell(commodity, qty))
  end

  defp step_to_bt_action(%{action: :refuel, at: location}) do
    BehaviorTree.action(:refuel, Actions.refuel(location))
  end

  defp step_to_bt_action(%{action: :idle}) do
    BehaviorTree.action(:idle, Actions.idle())
  end
end
