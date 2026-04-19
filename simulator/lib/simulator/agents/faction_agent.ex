defmodule Simulator.Agents.FactionAgent do
  @moduledoc """
  Macro-economic agent that represents a faction as an active policy layer.

  A FactionAgent watches all of its member facilities, aggregates their
  shortage signals into faction-wide deficits, and posts "subsidy
  contracts" — high-paying public delivery contracts — when a commodity
  is chronically scarce across multiple members. Think of it as a
  government stimulus or corporate relief program: when your own
  facilities aren't getting supplied by normal trade, pay a premium to
  lure ships in.

  ## Treasury & Tax

  Each faction holds a treasury. Every `@tax_interval` ticks, the agent
  sweeps its member facilities and skims `@tax_rate` of each facility's
  credit balance into the treasury. Subsidy contracts are funded from
  the treasury, so a faction with hungry facilities that refuses to tax
  its wealthy ones will quickly run out of stimulus power.

  ## Shortage Detection

  The agent subscribes to `"market:<facility_id>"` for each member on
  init and caches the `shortage_ticks` maps from incoming `:price_update`
  events. On each subsidy-evaluation tick it scans the cache and posts
  subsidy contracts for commodities where at least
  `@min_facilities_short` members have been in shortage longer than
  `@subsidy_trigger_ticks`.

  ## Dynamic Subsidy Payouts

  The payout multiplier scales with how chronic the shortage is:

      multiplier = 1.25 + min((max_shortage_ticks - trigger) / 100, 1.75)

  So a freshly triggered subsidy pays 1.25× the base delivery fee, and
  the multiplier ramps up toward a 3.0× cap as the shortage drags on —
  giving the economy strong reason to resolve the crisis.
  """

  use Simulator.Agents.Agent

  require Logger

  alias Simulator.Economy.ContractBoard
  alias Simulator.Simulation.Config

  @tax_interval 200 * Config.tick_multiplier()
  @tax_rate 0.005
  @subsidy_check_interval 30 * Config.tick_multiplier()

  # A commodity triggers subsidy consideration only after its shortage
  # has been sustained for this many ticks at ≥ @min_facilities_short
  # member facilities. Set above the PriceEngine urgency-onset threshold
  # (20) so subsidies only fire after normal price pressure has had a
  # chance to pull trade in.
  @subsidy_trigger_ticks 30
  @min_facilities_short 2

  # Caps how many subsidy contracts a faction can have live at once.
  # ContractBoard also enforces a max-per-requestor, but we keep a
  # tighter cap so a single faction can't dominate the board.
  @max_active_subsidies 3

  # Base payout for a subsidy contract before the dynamic multiplier.
  @subsidy_base_payment 2_000
  # Floor quantity — subsidies always move meaningful volume.
  @subsidy_quantity 200

  # Dynamic multiplier bounds, per the Phase 4 plan.
  @subsidy_min_multiplier 1.25
  @subsidy_max_multiplier 3.0

  # --- Public API ---

  @doc """
  Returns the full faction state. Used by the dashboard inspector.
  """
  @spec get_state(pid()) :: map()
  def get_state(pid), do: GenServer.call(pid, :get_state)

  @doc """
  Records a tax receipt from a member facility. Called asynchronously
  after a `:collect_tax` sync call to the facility.
  """
  @spec credit_tax(pid(), non_neg_integer()) :: :ok
  def credit_tax(pid, amount) when is_integer(amount) and amount > 0 do
    GenServer.cast(pid, {:credit_tax, amount})
  end

  def credit_tax(_pid, _amount), do: :ok

  # --- Agent Callbacks ---

  @impl Simulator.Agents.Agent
  def agent_type, do: :faction

  @impl Simulator.Agents.Agent
  def init_agent(config) do
    faction_id = config.faction_id
    member_facilities = config[:member_facilities] || []

    # Subscribe to each member facility's market events so price_update
    # broadcasts populate our shortage cache. Events.subscribe/1 is
    # idempotent per process so duplicate calls are safe.
    for facility_id <- member_facilities do
      Simulator.Events.subscribe("market:#{facility_id}")
    end

    state = %{
      id: config.id,
      faction_id: faction_id,
      name: config[:name] || faction_id,
      personality: config[:personality] || %{},
      treasury: config[:treasury] || 0,
      member_facilities: member_facilities,
      # %{facility_id => %{commodity => shortage_ticks}} — cached from
      # :price_update broadcasts, read during subsidy evaluation.
      shortage_cache: %{},
      # IDs of subsidy contracts we've posted; cleared when completed
      # or expired via their own lifecycle. Rebuilt from ContractBoard
      # on init so restarts don't let a faction double-post against
      # still-outstanding contracts.
      active_subsidies: rebuild_active_subsidies(faction_id),
      last_tick: 0,
      __db_id__: config[:db_id],
      __agent_type__: :faction
    }

    {:ok, state}
  end

  @impl Simulator.Agents.Agent
  def handle_tick(tick, state) do
    state =
      state
      |> Map.put(:last_tick, tick)
      |> phase_tax(tick)
      |> phase_subsidies(tick)

    {:ok, state}
  end

  @impl Simulator.Agents.Agent
  def persist_state(state) do
    if db_id = state[:__db_id__] do
      Simulator.Repo.get!(Simulator.Schemas.Faction, db_id)
      |> Simulator.Schemas.Faction.changeset(%{treasury: state.treasury})
      |> Simulator.Repo.update!()
    end

    :ok
  end

  # --- GenServer Handlers ---

  @impl GenServer
  def handle_call(:get_state, _from, state), do: {:reply, state, state}

  @impl GenServer
  def handle_cast({:credit_tax, amount}, state) do
    {:noreply, %{state | treasury: state.treasury + amount} |> mark_dirty()}
  end

  # Relay from PubSub subscriptions to member facility markets. The
  # common case per tick is a :price_update carrying the shortage_ticks
  # map — cache it so phase_subsidies/2 can aggregate without making
  # any sync calls.
  #
  # We override `handle_event/2` (not `handle_info/2`) because the Agent
  # behaviour's __using__ macro installs a catch-all handle_info that
  # forwards atom-tagged events here.
  @impl Simulator.Agents.Agent
  def handle_event({:price_update, %{facility_id: fid, shortage_ticks: ticks}}, state) do
    cache = Map.put(state.shortage_cache, fid, ticks || %{})
    {:ok, %{state | shortage_cache: cache}}
  end

  def handle_event(_event, state), do: {:ok, state}

  # --- Tick Phases ---

  defp phase_tax(state, tick) when rem(tick, @tax_interval) == 0 do
    collected =
      Enum.reduce(state.member_facilities, 0, fn facility_id, acc ->
        acc + collect_tax_from_facility(facility_id)
      end)

    if collected > 0 do
      %{state | treasury: state.treasury + collected} |> mark_dirty()
    else
      state
    end
  end

  defp phase_tax(state, _tick), do: state

  # Synchronous collection with a short timeout so a slow facility can't
  # stall the faction. The facility handler does the actual deduction.
  defp collect_tax_from_facility(facility_id) do
    case Simulator.Agents.Agent.whereis("facility-#{facility_id}") do
      {:ok, pid} ->
        try do
          GenServer.call(pid, {:collect_tax, @tax_rate}, 250)
        catch
          :exit, _ -> 0
        end

      :error ->
        0
    end
  end

  defp phase_subsidies(state, tick) when rem(tick, @subsidy_check_interval) == 0 do
    # Drop any subsidies that are no longer live (completed, expired,
    # cancelled) so the max-active cap reflects reality.
    active_subsidies = prune_inactive_subsidies(state.active_subsidies)
    state = %{state | active_subsidies: active_subsidies}

    if MapSet.size(active_subsidies) >= @max_active_subsidies do
      state
    else
      candidate_commodities = find_subsidy_candidates(state.shortage_cache)

      Enum.reduce(candidate_commodities, state, fn {commodity, dest_facility, max_ticks}, acc ->
        if MapSet.size(acc.active_subsidies) >= @max_active_subsidies do
          acc
        else
          maybe_post_subsidy(acc, commodity, dest_facility, max_ticks, tick)
        end
      end)
    end
  end

  defp phase_subsidies(state, _tick), do: state

  defp prune_inactive_subsidies(ids) do
    Enum.reduce(ids, MapSet.new(), fn id, acc ->
      case ContractBoard.get_contract(id) do
        %{status: status}
        when status in ["posted", "accepted", "in_progress", "picked_up", "in_transit"] ->
          MapSet.put(acc, id)

        _ ->
          acc
      end
    end)
  end

  # Returns [{commodity, most_starved_facility_id, max_shortage_ticks}]
  # for each commodity that passes the trigger gate.
  defp find_subsidy_candidates(cache) do
    # Invert cache: commodity -> [{facility, ticks}, ...]
    by_commodity =
      Enum.reduce(cache, %{}, fn {facility, ticks_map}, outer ->
        Enum.reduce(ticks_map, outer, fn {commodity, ticks}, inner ->
          if ticks > @subsidy_trigger_ticks do
            Map.update(inner, commodity, [{facility, ticks}], &[{facility, ticks} | &1])
          else
            inner
          end
        end)
      end)

    by_commodity
    |> Enum.filter(fn {_commodity, entries} -> length(entries) >= @min_facilities_short end)
    |> Enum.map(fn {commodity, entries} ->
      {dest_facility, max_ticks} = Enum.max_by(entries, fn {_f, t} -> t end)
      {commodity, dest_facility, max_ticks}
    end)
  end

  defp maybe_post_subsidy(state, commodity, dest_facility, max_ticks, tick) do
    multiplier = dynamic_multiplier(max_ticks)
    payment = round(@subsidy_base_payment * multiplier)

    if state.treasury < payment do
      state
    else
      attrs = %{
        contract_type: "supply",
        requestor_type: "faction",
        requestor_id: state.faction_id,
        faction_id: state.faction_id,
        commodity: to_string(commodity),
        quantity: @subsidy_quantity,
        destination_location: dest_facility,
        payment: payment,
        # Public subsidies — open to any neutral-or-better ship.
        min_reputation: 20,
        faction_bonus: 1.2,
        urgency: multiplier / @subsidy_max_multiplier,
        escalation_rate: 0.0,
        posted_at_tick: tick,
        deadline_tick: tick + 300 * Config.tick_multiplier()
      }

      case ContractBoard.post_contract(attrs) do
        {:ok, contract} ->
          Logger.info(
            "FactionAgent #{state.faction_id}: subsidy posted — #{commodity} → " <>
              "#{dest_facility}, #{payment} cr (#{Float.round(multiplier, 2)}×)"
          )

          Simulator.Events.broadcast("faction:#{state.faction_id}", :subsidy_posted, %{
            faction_id: state.faction_id,
            contract_id: contract.id,
            commodity: commodity,
            destination: dest_facility,
            payment: payment,
            multiplier: multiplier,
            tick: tick
          })

          %{
            state
            | treasury: state.treasury - payment,
              active_subsidies: MapSet.put(state.active_subsidies, contract.id)
          }
          |> mark_dirty()

        {:error, reason} ->
          Logger.debug(
            "FactionAgent #{state.faction_id}: subsidy post failed (#{inspect(reason)})"
          )

          state
      end
    end
  end

  @active_contract_statuses ~w(posted accepted in_progress picked_up in_transit)

  defp rebuild_active_subsidies(faction_id) do
    try do
      ContractBoard.contracts_for(faction_id)
      |> Enum.filter(&(&1.status in @active_contract_statuses))
      |> Enum.map(& &1.id)
      |> MapSet.new()
    rescue
      # If ContractBoard isn't up yet (startup order edge) or the
      # ETS table doesn't exist (some tests), start empty and let
      # the next subsidy-eval tick repopulate naturally.
      _ -> MapSet.new()
    catch
      :exit, _ -> MapSet.new()
    end
  end

  defp dynamic_multiplier(max_ticks) do
    excess = max(max_ticks - @subsidy_trigger_ticks, 0)

    raw =
      @subsidy_min_multiplier +
        excess / 100.0 * (@subsidy_max_multiplier - @subsidy_min_multiplier)

    min(raw, @subsidy_max_multiplier)
  end
end
