defmodule Simulator.Agents.ShipAgent.Actions do
  @moduledoc """
  BT-compatible action functions for ship behavior trees.

  Each function takes a blackboard (which contains the ship's `:state` and
  `:tick`) and returns `{:success | :failure | :running, updated_blackboard}`.

  These wrap the existing ship operations (dock, undock, buy, sell, travel,
  refuel) into the BehaviorTree action node interface.
  """

  alias Simulator.Agents.{CrewComplement, FacilityAgent, MarketAgent, ShipAgent}
  alias Simulator.Simulation.Config

  @cargo_load_rate 50 * Config.tick_scale()
  @fuel_load_rate 100 * Config.tick_scale()

  @doc """
  Creates a BT action function for docking at a location.
  """
  @spec dock(String.t()) :: (map() -> {atom(), map()})
  def dock(location) do
    fn bb ->
      state = bb.state

      if state.docked_at == "facility-#{location}" do
        {:success, bb}
      else
        case find_facility(location) do
          {:ok, facility_pid} ->
            case FacilityAgent.request_dock(facility_pid, %{ship_id: state.id}) do
              {:ok, info} ->
                fee = Map.get(info, :docking_fee, 0)

                new_state = %{
                  state
                  | docked_at: "facility-#{location}",
                    credits: max(state.credits - fee, 0)
                }

                {:success, %{bb | state: mark_dirty(new_state)}}

              {:error, _} ->
                {:failure, bb}
            end

          :error ->
            {:failure, bb}
        end
      end
    end
  end

  @doc """
  Creates a BT action function for undocking from a location.
  """
  @spec undock(String.t()) :: (map() -> {atom(), map()})
  def undock(location) do
    fn bb ->
      state = bb.state

      case find_facility(location) do
        {:ok, facility_pid} ->
          FacilityAgent.request_undock(facility_pid, state.id)
          {:success, %{bb | state: %{state | docked_at: nil}}}

        :error ->
          {:success, %{bb | state: %{state | docked_at: nil}}}
      end
    end
  end

  @doc """
  Creates a BT action function for beginning transit to a destination.
  Returns `:running` on first call, then `:success` when arrived.
  """
  @spec travel(String.t()) :: (map() -> {atom(), map()})
  def travel(destination) do
    fn bb ->
      state = bb.state

      cond do
        # Already arrived
        state.location == destination ->
          {:success, bb}

        # In transit — check if arrived
        state.transit != nil ->
          if bb.tick >= state.transit.arrival_tick do
            new_state = %{
              state
              | location: state.transit.to,
                transit: nil
            }

            arrival = %{
              ship_id: state.id,
              location: state.transit.to,
              from: state.transit.from,
              tick: bb.tick
            }

            Simulator.Events.broadcast("ship:#{state.id}", :ship_arrived, arrival)
            Simulator.Events.broadcast("ship_events", :ship_arrived, arrival)
            Simulator.Events.log(:ship_arrived, arrival)

            {:success, %{bb | state: mark_dirty(new_state)}}
          else
            # Still in transit — consume fuel
            new_state = consume_fuel(state)
            {:running, %{bb | state: new_state}}
          end

        # Start transit
        state.location != nil ->
          case resolve_travel_time(state.location, destination) do
            {:ok, base_ticks} ->
              # Scale travel time by ticks_per_second only (not world_speed).
              # Travel times are spatial distances — world_speed slows production
              # and consumption rates, not how fast ships physically move.
              ticks = base_ticks * Config.ticks_per_second()
              speed = max(state.efficiency, 0.1) * Map.get(state, :speed_modifier, 1.0)
              adjusted_ticks = max(round(ticks / speed), 1)

              transit = %{
                from: state.location,
                to: destination,
                departure_tick: bb.tick,
                arrival_tick: bb.tick + adjusted_ticks
              }

              departure = %{
                ship_id: state.id,
                from: state.location,
                to: destination,
                tick: bb.tick,
                departure_tick: transit.departure_tick,
                arrival_tick: transit.arrival_tick
              }

              Simulator.Events.broadcast("ship:#{state.id}", :ship_departed, departure)
              Simulator.Events.broadcast("ship_events", :ship_departed, departure)
              Simulator.Events.log(:ship_departed, departure)

              new_state = %{state | location: nil, transit: transit, docked_at: nil}
              {:running, %{bb | state: mark_dirty(new_state)}}

            {:error, _} ->
              {:failure, bb}
          end

        true ->
          {:failure, bb}
      end
    end
  end

  @doc """
  Creates a BT action function for buying a commodity.
  Multi-tick: places buy order and deducts credits immediately,
  then crew loads cargo over several ticks.
  """
  @spec buy(atom(), non_neg_integer()) :: (map() -> {atom(), map()})
  def buy(commodity, quantity) do
    fn bb ->
      state = bb.state

      case state.cargo_op do
        # Loading complete — add cargo to hold
        %{action: :buy, completion_tick: t} when bb.tick >= t ->
          op = state.cargo_op

          new_state =
            state
            |> Map.update!(
              :cargo,
              &Map.update(&1, op.commodity, op.quantity, fn v -> v + op.quantity end)
            )
            |> stamp_cargo_age(op.commodity, bb.tick)
            |> Map.put(:cargo_op, nil)
            |> set_crew_task(primary_task(state.crew.roles))
            |> update_price_memory(state.location, op.commodity, op.price, bb.tick)
            |> mark_dirty()

          {:success, %{bb | state: new_state}}

        # Still loading
        %{action: :buy} ->
          {:running, bb}

        # Another op in progress — wait
        %{} ->
          {:running, bb}

        # Start buy operation
        nil ->
          location = state.location

          case find_market(location) do
            {:ok, market_pid} ->
              prices = MarketAgent.query_prices(market_pid)
              price = Map.get(prices, commodity, 0)

              ideal_reserve = ShipAgent.ideal_credit_reserve(state.personality)
              min_reserve = min(ideal_reserve, round(state.credits * 0.5))
              spendable = max(state.credits - min_reserve, 0)

              if price > 0 and spendable > 0 do
                affordable_qty = min(quantity, floor(spendable / max(price, 0.01)))
                buy_qty = min(affordable_qty, state.cargo_capacity - cargo_total(state.cargo))

                if buy_qty > 0 do
                  MarketAgent.place_buy_order(market_pid, %{
                    agent_id: state.id,
                    commodity: commodity,
                    quantity: buy_qty,
                    price: price * 1.05
                  })

                  cost = min(round(buy_qty * price), state.credits)
                  duration = cargo_op_duration(buy_qty, state)

                  new_state =
                    state
                    |> Map.update!(:credits, &(&1 - cost))
                    |> Map.put(:cargo_op, %{
                      action: :buy,
                      commodity: commodity,
                      quantity: buy_qty,
                      price: price,
                      completion_tick: bb.tick + duration
                    })
                    |> set_crew_task(:loading)
                    |> mark_dirty()

                  {:running, %{bb | state: new_state}}
                else
                  {:failure, bb}
                end
              else
                {:failure, bb}
              end

            :error ->
              {:failure, bb}
          end
      end
    end
  end

  @doc """
  Creates a BT action function for selling a commodity.
  Multi-tick: crew unloads cargo first, then places sell order on completion.
  """
  @spec sell(atom(), non_neg_integer()) :: (map() -> {atom(), map()})
  def sell(commodity, quantity) do
    fn bb ->
      state = bb.state

      case state.cargo_op do
        # Unloading complete — sell on market and collect revenue
        %{action: :sell, completion_tick: t} when bb.tick >= t ->
          op = state.cargo_op
          location = state.location

          case find_market(location) do
            {:ok, market_pid} ->
              prices = MarketAgent.query_prices(market_pid)
              price = Map.get(prices, op.commodity, op.price)

              MarketAgent.place_sell_order(market_pid, %{
                agent_id: state.id,
                commodity: op.commodity,
                quantity: op.quantity,
                price: price * 0.95
              })

              revenue = round(op.quantity * price)

              new_state =
                state
                |> Map.put(:cargo_op, nil)
                |> set_crew_task(primary_task(state.crew.roles))
                |> Map.update!(:credits, &(&1 + revenue))
                |> update_price_memory(location, op.commodity, price, bb.tick)
                |> mark_dirty()

              {:success, %{bb | state: new_state}}

            :error ->
              # Market gone — just clear the op, cargo already removed
              new_state =
                state
                |> Map.put(:cargo_op, nil)
                |> set_crew_task(primary_task(state.crew.roles))

              {:failure, %{bb | state: new_state}}
          end

        # Still unloading
        %{action: :sell} ->
          {:running, bb}

        # Another op in progress — wait
        %{} ->
          {:running, bb}

        # Start sell operation — remove cargo from hold immediately
        nil ->
          available = Map.get(state.cargo, commodity, 0)

          if available > 0 do
            sell_qty = min(quantity, available)

            # Record price at time of decision for fallback
            price =
              case find_market(state.location) do
                {:ok, pid} -> Map.get(MarketAgent.query_prices(pid), commodity, 0)
                :error -> 0
              end

            duration = cargo_op_duration(sell_qty, state)

            new_state =
              state
              |> update_in(
                [:cargo],
                &Map.update(&1, commodity, 0, fn v -> max(v - sell_qty, 0) end)
              )
              |> sync_cargo_age()
              |> Map.put(:cargo_op, %{
                action: :sell,
                commodity: commodity,
                quantity: sell_qty,
                price: price,
                completion_tick: bb.tick + duration
              })
              |> set_crew_task(:loading)
              |> mark_dirty()

            {:running, %{bb | state: new_state}}
          else
            {:failure, bb}
          end
      end
    end
  end

  @doc """
  Creates a BT action function for refueling at a location.
  Multi-tick: fuel is pumped at a faster rate than cargo loading.
  """
  @spec refuel(String.t()) :: (map() -> {atom(), map()})
  def refuel(location) do
    fn bb ->
      state = bb.state

      case state.cargo_op do
        # Fueling complete
        %{action: :refuel, completion_tick: t} when bb.tick >= t ->
          op = state.cargo_op

          new_state =
            state
            |> Map.put(:fuel, min(state.fuel + op.amount, state.fuel_capacity))
            |> Map.put(:credits, state.credits - op.cost)
            |> Map.put(:cargo_op, nil)
            |> set_crew_task(primary_task(state.crew.roles))

          {:success, %{bb | state: new_state}}

        # Still fueling
        %{action: :refuel} ->
          {:running, bb}

        # Another op in progress — wait
        %{} ->
          {:running, bb}

        # Start refueling
        nil ->
          case find_facility(location) do
            {:ok, facility_pid} ->
              needed = state.fuel_capacity - state.fuel

              if needed > 1.0 do
                case FacilityAgent.request_refuel(facility_pid, %{amount: round(needed)}) do
                  {:ok, info} ->
                    duration = fuel_op_duration(info.amount, state)

                    new_state =
                      state
                      |> Map.put(:cargo_op, %{
                        action: :refuel,
                        amount: info.amount,
                        cost: info.cost,
                        completion_tick: bb.tick + duration
                      })
                      |> set_crew_task(:loading)

                    {:running, %{bb | state: new_state}}

                  {:error, _} ->
                    {:success, bb}
                end
              else
                {:success, bb}
              end

            :error ->
              {:success, bb}
          end
      end
    end
  end

  @doc """
  Creates a BT action to accept a contract from the board.
  """
  @spec accept_contract(map()) :: (map() -> {atom(), map()})
  def accept_contract(contract) do
    fn bb ->
      state = bb.state

      case Simulator.Economy.ContractBoard.accept_contract(contract.id, state.id, bb.tick) do
        {:ok, accepted} ->
          Simulator.Events.log(:contract_accepted, %{
            ship_id: state.id,
            contract_id: contract.id,
            commodity: contract[:commodity],
            destination: contract[:destination_location],
            tick: bb.tick
          })

          new_state = Map.put(state, :active_contract, accepted)
          {:success, %{bb | state: new_state}}

        {:error, _} ->
          {:failure, bb}
      end
    end
  end

  @doc """
  Creates a BT action to deliver contract cargo at the destination.
  Multi-tick: crew unloads cargo, then triggers escrow release on completion.
  """
  @spec deliver_contract(map(), non_neg_integer()) :: (map() -> {atom(), map()})
  def deliver_contract(contract, quantity) do
    fn bb ->
      state = bb.state

      case state.cargo_op do
        # Unloading complete — finalize contract delivery
        %{action: :deliver_contract, completion_tick: t} when bb.tick >= t ->
          new_state =
            state
            |> Map.put(:cargo_op, nil)
            |> set_crew_task(primary_task(state.crew.roles))

          with {:ok, _} <- Simulator.Economy.ContractBoard.begin_work(contract.id),
               {:ok, updated} <- Simulator.Economy.ContractBoard.deliver(contract.id, quantity) do
            if updated.status == "fulfilled" do
              case Simulator.Economy.ContractBoard.release_payment(contract.id, bb.tick) do
                {:ok, completed, payout} ->
                  bonus = Map.get(completed, :faction_bonus, 1.0)
                  effective_payout = round(payout * bonus)
                  contract_faction = Map.get(completed, :faction_id)

                  new_rep =
                    if contract_faction do
                      {rep, _change} =
                        Simulator.Economy.Reputation.contract_completed(
                          new_state.faction_reputation,
                          contract_faction,
                          payout
                        )

                      rep
                    else
                      new_state.faction_reputation
                    end

                  final = %{
                    new_state
                    | credits: new_state.credits + effective_payout,
                      faction_reputation: new_rep,
                      active_contract: nil
                  }

                  {:success, %{bb | state: mark_dirty(final)}}

                {:error, _} ->
                  {:success, %{bb | state: %{new_state | active_contract: nil}}}
              end
            else
              {:success, %{bb | state: %{new_state | active_contract: updated}}}
            end
          else
            {:error, _} ->
              {:failure, %{bb | state: new_state}}
          end

        # Still unloading
        %{action: :deliver_contract} ->
          {:running, bb}

        # Another op in progress — wait
        %{} ->
          {:running, bb}

        # Start unloading
        nil ->
          duration = cargo_op_duration(quantity, state)

          new_state =
            state
            |> Map.put(:cargo_op, %{
              action: :deliver_contract,
              quantity: quantity,
              completion_tick: bb.tick + duration
            })
            |> set_crew_task(:loading)

          {:running, %{bb | state: new_state}}
      end
    end
  end

  @doc """
  Creates an idle action that always succeeds.
  """
  @spec idle() :: (map() -> {atom(), map()})
  def idle do
    fn bb -> {:success, bb} end
  end

  @station_job_duration 3 * Config.tick_multiplier()

  @doc """
  Creates a BT action for a short paid station job.

  Broke ships use this as a lifeline: the ship's crew performs manual
  labor at the facility (cargo handling, repairs, maintenance), the
  facility pays a small amount from its treasury, and the ship gets
  enough credits to afford fuel.

  The payout is `100 + skill_bonus` where `skill_bonus` blends the crew's
  engineering and trading skills. Requires the facility to have at least
  `1000` credits on hand; otherwise the action fails and the ship must
  seek work elsewhere.
  """
  @spec station_job(String.t()) :: (map() -> {atom(), map()})
  def station_job(location) do
    fn bb ->
      state = bb.state

      case state.cargo_op do
        %{action: :station_job, completion_tick: t, payout: payout} when bb.tick >= t ->
          new_state =
            state
            |> Map.update!(:credits, &(&1 + payout))
            |> Map.put(:cargo_op, nil)
            |> set_crew_task(primary_task(state.crew.roles))

          {:success, %{bb | state: new_state}}

        %{action: :station_job} ->
          {:running, bb}

        %{} ->
          {:running, bb}

        nil ->
          case find_facility(location) do
            {:ok, facility_pid} ->
              skills = state.crew.skills

              skill_bonus =
                round((Map.get(skills, :engineering, 0) + Map.get(skills, :trading, 0)) / 2)

              request = %{ship_id: state.id, skill_bonus: skill_bonus}

              case GenServer.call(facility_pid, {:request_station_job, request}) do
                {:ok, payout} when payout > 0 ->
                  new_state =
                    state
                    |> Map.put(:cargo_op, %{
                      action: :station_job,
                      payout: payout,
                      completion_tick: bb.tick + @station_job_duration
                    })
                    |> set_crew_task(:engineering)
                    |> mark_dirty()

                  {:running, %{bb | state: new_state}}

                _ ->
                  {:failure, bb}
              end

            :error ->
              {:failure, bb}
          end
      end
    end
  end

  @doc """
  Creates a BT action for a longer crew-led mission at a facility.

  While `station_job/1` is a quick 3-tick broke lifeline, a crew mission
  is a richer, facility-posted job: security detail, heavy maintenance,
  harvest help, etc. The whole crew is engaged (aggregate unit — no
  per-crew agents) for the mission's `duration_ticks`. On completion the
  ship gets the contract payment, faction reputation, and a small bump
  on the mission's `required_skill`.

  Expects the contract map to carry `duration_ticks`, `payment`,
  `required_skill`, and `skill_gain` — all populated by the posting
  facility via `MissionCatalog`.
  """
  @spec do_crew_mission(map()) :: (map() -> {atom(), map()})
  def do_crew_mission(contract) do
    fn bb ->
      state = bb.state

      case state.cargo_op do
        %{action: :crew_mission, completion_tick: t} = op when bb.tick >= t ->
          dest = contract.source_location

          # Finalize the contract through the shared delivery lifecycle
          # (crew missions sit on the ContractBoard like any other
          # contract, so pickup + confirm_delivery ladders apply).
          Simulator.Economy.ContractBoard.pickup_cargo(
            contract.id,
            state.id,
            bb.tick
          )

          payout =
            case Simulator.Economy.ContractBoard.confirm_delivery(contract.id, bb.tick) do
              {:ok, completed, amount} ->
                bonus = Map.get(completed, :faction_bonus, 1.0)
                round(amount * bonus)

              _ ->
                op.payment
            end

          contract_faction = contract[:faction_id]

          new_rep =
            if is_binary(contract_faction) do
              {rep, _change} =
                Simulator.Economy.Reputation.contract_completed(
                  state.faction_reputation,
                  contract_faction,
                  payout
                )

              rep
            else
              state.faction_reputation
            end

          skill_atom = op.skill_atom
          skill_gain = op.skill_gain

          new_crew =
            Simulator.Agents.CrewComplement.grant_skill_xp(
              state.crew,
              skill_atom,
              skill_gain
            )

          Simulator.Events.broadcast("facility:#{dest}", :crew_mission_completed, %{
            ship_id: state.id,
            facility_location: dest,
            category: op.category,
            payment: payout,
            tick: bb.tick
          })

          new_state =
            state
            |> Map.put(:credits, state.credits + payout)
            |> Map.put(:faction_reputation, new_rep)
            |> Map.put(:active_contract, nil)
            |> Map.put(:cargo_op, nil)
            |> Map.put(:crew, new_crew)
            |> set_crew_task(primary_task(state.crew.roles))
            |> mark_dirty()

          {:success, %{bb | state: new_state}}

        %{action: :crew_mission} ->
          {:running, bb}

        %{} ->
          {:running, bb}

        nil ->
          source = contract.source_location

          cond do
            state.location != source ->
              {:failure, bb}

            true ->
              duration =
                (contract[:duration_ticks] || 20) * Config.tick_multiplier()

              category = contract[:mission_category] || :generic

              skill_atom =
                case contract[:required_skill] do
                  a when is_atom(a) -> a
                  s when is_binary(s) -> safe_atom(s, :general)
                  _ -> :general
                end

              skill_gain = contract[:skill_gain] || 1
              payment = contract[:payment] || 0

              new_state =
                state
                |> Map.put(:cargo_op, %{
                  action: :crew_mission,
                  category: category,
                  skill_atom: skill_atom,
                  skill_gain: skill_gain,
                  payment: payment,
                  completion_tick: bb.tick + max(duration, 1)
                })
                |> set_crew_task(:on_mission)
                |> mark_dirty()

              {:running, %{bb | state: new_state}}
          end
      end
    end
  end

  defp safe_atom(s, default) when is_binary(s) do
    try do
      String.to_existing_atom(s)
    rescue
      ArgumentError -> default
    end
  end

  @doc """
  Creates a BT action that keeps the crew resting until morale recovers.
  Returns `:running` while morale is below 100, `:success` when recovered.
  Also sets the crew task to `:resting` for faster recovery.
  """
  @spec rest_until_recovered() :: (map() -> {atom(), map()})
  def rest_until_recovered do
    fn bb ->
      state = bb.state
      crew = state.crew

      if Simulator.Agents.CrewComplement.shore_leave_complete?(crew) do
        {:success, bb}
      else
        # Set crew to resting for faster morale recovery
        crew = %{crew | current_task: :resting}
        {:running, %{bb | state: %{state | crew: crew}}}
      end
    end
  end

  # --- Delivery Contract Actions ---

  @doc """
  Creates a BT action to pick up pre-purchased cargo from a market.
  Multi-tick: reserves are claimed immediately, then crew loads over time.

  The ship pays a cargo deposit (insurance) and loads the goods.
  On successful delivery, the deposit is returned along with the delivery fee.
  """
  @spec pickup_cargo(map()) :: (map() -> {atom(), map()})
  def pickup_cargo(contract) do
    fn bb ->
      state = bb.state

      case state.cargo_op do
        # Loading complete — add cargo to hold
        %{action: :pickup, completion_tick: t} when bb.tick >= t ->
          op = state.cargo_op

          new_state =
            state
            |> Map.update!(:cargo, fn cargo ->
              Map.update(cargo, op.commodity, op.quantity, &(&1 + op.quantity))
            end)
            |> stamp_cargo_age(op.commodity, bb.tick)
            |> Map.put(:cargo_op, nil)
            |> set_crew_task(primary_task(state.crew.roles))
            |> mark_dirty()

          {:success, %{bb | state: new_state}}

        # Still loading
        %{action: :pickup} ->
          {:running, bb}

        # Another op in progress — wait
        %{} ->
          {:running, bb}

        # Start pickup
        nil ->
          source = contract.source_location

          cond do
            state.location != source ->
              {:failure, bb}

            state.credits < (contract.cargo_deposit || 0) ->
              {:failure, bb}

            true ->
              case find_market(source) do
                {:ok, market_pid} ->
                  case MarketAgent.pickup_reserved(market_pid, contract.reserve_id, state.id) do
                    {:ok, commodity, quantity} ->
                      deposit = contract.cargo_deposit || 0
                      duration = cargo_op_duration(quantity, state)

                      # Transition contract to picked_up
                      Simulator.Economy.ContractBoard.pickup_cargo(
                        contract.id,
                        state.id,
                        bb.tick
                      )

                      new_state =
                        state
                        |> Map.update!(:credits, &(&1 - deposit))
                        |> Map.put(:cargo_op, %{
                          action: :pickup,
                          commodity: commodity,
                          quantity: quantity,
                          completion_tick: bb.tick + duration
                        })
                        |> set_crew_task(:loading)
                        |> mark_dirty()

                      {:running, %{bb | state: new_state}}

                    {:error, _} ->
                      {:failure, bb}
                  end

                :error ->
                  {:failure, bb}
              end
          end
      end
    end
  end

  @doc """
  Creates a BT action to deliver cargo for a delivery contract.
  Multi-tick: crew unloads cargo first, then finalizes delivery on completion.

  Removes cargo from the ship, pushes it to the destination facility/market,
  and credits the ship with the deposit refund + delivery fee.
  """
  @spec deliver_cargo(map()) :: (map() -> {atom(), map()})
  def deliver_cargo(contract) do
    fn bb ->
      state = bb.state

      case state.cargo_op do
        # Unloading complete — push to market/facility and collect payout
        %{action: :deliver, completion_tick: t} when bb.tick >= t ->
          op = state.cargo_op
          dest = contract.destination_location
          commodity = op.commodity
          quantity = op.quantity

          # Push goods to the destination market supply
          case find_market(dest) do
            {:ok, market_pid} ->
              current_supply = MarketAgent.get_state(market_pid).supply
              new_supply = Map.update(current_supply, commodity, quantity, &(&1 + quantity))
              GenServer.cast(market_pid, {:update_supply, new_supply})

            :error ->
              :ok
          end

          # Also add to facility reserves
          case find_facility(dest) do
            {:ok, facility_pid} ->
              GenServer.cast(facility_pid, {:receive_delivery, commodity, quantity})

            :error ->
              :ok
          end

          # Complete the delivery and collect payout
          case Simulator.Economy.ContractBoard.confirm_delivery(contract.id, bb.tick) do
            {:ok, completed, payout} ->
              bonus = Map.get(completed, :faction_bonus, 1.0)
              effective_payout = round(payout * bonus)

              contract_faction = Map.get(completed, :faction_id)

              new_rep =
                if contract_faction do
                  {rep, _change} =
                    Simulator.Economy.Reputation.contract_completed(
                      state.faction_reputation,
                      contract_faction,
                      payout
                    )

                  rep
                else
                  state.faction_reputation
                end

              new_state =
                state
                |> Map.put(:credits, state.credits + effective_payout)
                |> Map.put(:faction_reputation, new_rep)
                |> Map.put(:active_contract, nil)
                |> Map.put(:cargo_op, nil)
                |> set_crew_task(primary_task(state.crew.roles))
                |> mark_dirty()

              {:success, %{bb | state: new_state}}

            {:error, _} ->
              new_state =
                state
                |> Map.put(:cargo_op, nil)
                |> set_crew_task(primary_task(state.crew.roles))

              {:failure, %{bb | state: new_state}}
          end

        # Still unloading
        %{action: :deliver} ->
          {:running, bb}

        # Another op in progress — wait
        %{} ->
          {:running, bb}

        # Start unloading
        nil ->
          dest = contract.destination_location
          commodity = String.to_existing_atom(contract.commodity)
          quantity = contract.quantity

          if state.location != dest do
            {:failure, bb}
          else
            duration = cargo_op_duration(quantity, state)

            # Remove cargo from hold immediately (it's being moved to the dock)
            new_state =
              state
              |> Map.update!(:cargo, fn cargo ->
                Map.update(cargo, commodity, 0, &max(&1 - quantity, 0))
              end)
              |> sync_cargo_age()
              |> Map.put(:cargo_op, %{
                action: :deliver,
                commodity: commodity,
                quantity: quantity,
                completion_tick: bb.tick + duration
              })
              |> set_crew_task(:loading)
              |> mark_dirty()

            {:running, %{bb | state: new_state}}
          end
      end
    end
  end

  # --- Passenger Transport Actions ---

  @passenger_load_rate 20 * Config.tick_scale()

  @doc """
  BT action to board passengers onto the ship at the contract source.

  Passengers occupy the `passenger_capacity` dimension, separate from
  cargo. The ship is limited to its remaining capacity; the contract
  records the number actually boarded so deliver_passengers/1 knows
  how many to disembark.
  """
  @spec pickup_passengers(map()) :: (map() -> {atom(), map()})
  def pickup_passengers(contract) do
    fn bb ->
      state = bb.state

      case state.cargo_op do
        %{action: :boarding, completion_tick: t} when bb.tick >= t ->
          op = state.cargo_op

          new_state =
            state
            |> Map.update(:passengers, op.quantity, &(&1 + op.quantity))
            |> Map.put(:cargo_op, nil)
            |> set_crew_task(primary_task(state.crew.roles))
            |> mark_dirty()

          {:success, %{bb | state: new_state}}

        %{action: :boarding} ->
          {:running, bb}

        %{} ->
          {:running, bb}

        nil ->
          source = contract.source_location

          cond do
            state.location != source ->
              {:failure, bb}

            true ->
              capacity = Map.get(state, :passenger_capacity, 0)
              onboard = Map.get(state, :passengers, 0)
              pax_count = contract[:passenger_count] || 0

              available_seats = max(capacity - onboard, 0)
              boarding = min(pax_count, available_seats)

              if boarding <= 0 do
                {:failure, bb}
              else
                # Try to transition the underlying contract to picked_up —
                # reuses the cargo-delivery pickup lifecycle. Doesn't fail
                # the BT if the state machine disagrees; we still want the
                # passengers on the ship.
                Simulator.Economy.ContractBoard.pickup_cargo(
                  contract.id,
                  state.id,
                  bb.tick
                )

                duration =
                  boarding
                  |> div(max(round(@passenger_load_rate), 1))
                  |> max(1)

                new_state =
                  state
                  |> Map.put(:cargo_op, %{
                    action: :boarding,
                    quantity: boarding,
                    completion_tick: bb.tick + duration
                  })
                  |> set_crew_task(:loading)
                  |> mark_dirty()

                {:running, %{bb | state: new_state}}
              end
          end
      end
    end
  end

  @doc """
  BT action to disembark passengers at the destination and collect payment.

  Bumps the destination pop's `population_count` by the delivered count
  (via an async cast) and pays the ship the contract fee plus the standard
  faction-reputation bonus.
  """
  @spec deliver_passengers(map()) :: (map() -> {atom(), map()})
  def deliver_passengers(contract) do
    fn bb ->
      state = bb.state

      case state.cargo_op do
        %{action: :deboarding, completion_tick: t} when bb.tick >= t ->
          op = state.cargo_op
          dest = contract.destination_location

          # Bump destination pops — broadcast to any co-located pop agents.
          # Pops subscribe to their own `facility:<location>` topic, and also
          # accept a direct cast for explicit arrivals.
          Simulator.Events.broadcast("facility:#{dest}", :passengers_arrived, %{
            destination: dest,
            passenger_count: op.quantity,
            tick: bb.tick
          })

          # Finalize the contract — deliver the passengers (quantity in the
          # "remaining" slot) and collect payout. Mirror deliver_cargo's
          # lifecycle calls.
          with {:ok, completed, payout} <-
                 Simulator.Economy.ContractBoard.confirm_delivery(contract.id, bb.tick) do
            bonus = Map.get(completed, :faction_bonus, 1.0)
            effective_payout = round(payout * bonus)
            contract_faction = Map.get(completed, :faction_id)

            new_rep =
              if contract_faction do
                {rep, _change} =
                  Simulator.Economy.Reputation.contract_completed(
                    state.faction_reputation,
                    contract_faction,
                    payout
                  )

                rep
              else
                state.faction_reputation
              end

            new_state =
              state
              |> Map.update(:passengers, 0, &max(&1 - op.quantity, 0))
              |> Map.put(:credits, state.credits + effective_payout)
              |> Map.put(:faction_reputation, new_rep)
              |> Map.put(:active_contract, nil)
              |> Map.put(:cargo_op, nil)
              |> set_crew_task(primary_task(state.crew.roles))
              |> mark_dirty()

            {:success, %{bb | state: new_state}}
          else
            {:error, _} ->
              new_state =
                state
                |> Map.update(:passengers, 0, &max(&1 - op.quantity, 0))
                |> Map.put(:cargo_op, nil)
                |> set_crew_task(primary_task(state.crew.roles))

              {:failure, %{bb | state: new_state}}
          end

        %{action: :deboarding} ->
          {:running, bb}

        %{} ->
          {:running, bb}

        nil ->
          dest = contract.destination_location
          pax_count = min(contract[:passenger_count] || 0, Map.get(state, :passengers, 0))

          cond do
            state.location != dest ->
              {:failure, bb}

            pax_count <= 0 ->
              {:failure, bb}

            true ->
              duration =
                pax_count
                |> div(max(round(@passenger_load_rate), 1))
                |> max(1)

              new_state =
                state
                |> Map.put(:cargo_op, %{
                  action: :deboarding,
                  quantity: pax_count,
                  completion_tick: bb.tick + duration
                })
                |> set_crew_task(:loading)
                |> mark_dirty()

              {:running, %{bb | state: new_state}}
          end
      end
    end
  end

  # --- Helpers ---

  defp find_facility(location) do
    Simulator.Agents.Agent.whereis("facility-#{location}")
  end

  defp find_market(location) do
    Simulator.Agents.Agent.whereis("market-#{location}")
  end

  defp resolve_travel_time(from, to) do
    systems = Simulator.World.Registry.system_ids()

    Enum.find_value(systems, Simulator.World.Travel.travel_time(from, to), fn system_id ->
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

  defp consume_fuel(state) do
    adjusted_rate = state.fuel_consumption_rate / max(state.efficiency, 0.1)
    new_fuel = max(state.fuel - adjusted_rate, 0.0)
    %{state | fuel: new_fuel}
  end

  defp cargo_total(cargo) do
    cargo |> Map.values() |> Enum.sum()
  end

  defp mark_dirty(state) do
    # Delegate to the Agent base mark_dirty which properly queues
    # the persist function with PersistenceManager
    Simulator.Agents.ShipAgent.mark_dirty(state)
  end

  defp update_price_memory(state, location, commodity, price, tick) do
    current = get_in(state, [:memory, :known_prices, location]) || %{}
    updated = Map.put(current, commodity, %{price: price, tick: tick})
    put_in(state, [:memory, :known_prices, location], updated)
  end

  # Stamps the tick a commodity was first received, without overwriting an
  # existing stamp (keep the earliest age so a partial resupply doesn't
  # reset the hoarding timer).
  defp stamp_cargo_age(state, commodity, tick) do
    ages = Map.get(state, :cargo_age, %{})

    if Map.has_key?(ages, commodity) do
      state
    else
      Map.put(state, :cargo_age, Map.put(ages, commodity, tick))
    end
  end

  # Prunes age entries for commodities the ship no longer holds. Called
  # after any cargo decrement so the hoarding detector sees the real set.
  defp sync_cargo_age(state) do
    ages = Map.get(state, :cargo_age, %{})

    pruned =
      Map.filter(ages, fn {commodity, _tick} ->
        Map.get(state.cargo, commodity, 0) > 0
      end)

    Map.put(state, :cargo_age, pruned)
  end

  # --- Cargo Operation Duration ---

  defp cargo_op_duration(quantity, state) do
    efficiency = CrewComplement.efficiency(state.crew)
    base_ticks = ceil(quantity / @cargo_load_rate)
    max(ceil(base_ticks / efficiency), 1)
  end

  defp fuel_op_duration(amount, state) do
    efficiency = CrewComplement.efficiency(state.crew)
    base_ticks = ceil(amount / @fuel_load_rate)
    max(ceil(base_ticks / efficiency), 1)
  end

  defp set_crew_task(state, task) do
    %{state | crew: %{state.crew | current_task: task}}
  end

  defp primary_task(roles) do
    cond do
      :pilot in roles -> :piloting
      :engineer in roles -> :engineering
      :trader in roles -> :trading
      true -> :idle
    end
  end
end
