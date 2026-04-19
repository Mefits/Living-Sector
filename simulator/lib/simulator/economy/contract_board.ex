defmodule Simulator.Economy.ContractBoard do
  @moduledoc """
  Central contract discovery and management service.

  Uses two ETS tables for scalable access:
  - Primary table (`:set`): `{contract_id, contract_map}` for O(1) by-id lookups
  - Index table (`:bag`): `{{status, destination}, contract_id}` for O(1) by-location queries

  Ships query the index table to find contracts at reachable destinations
  without scanning all contracts. With thousands of contracts, this keeps
  queries proportional to the number of reachable destinations (~2-5),
  not the total contract count.
  """

  use GenServer

  require Logger

  alias Simulator.Economy.ContractLifecycle
  alias Simulator.Repo
  alias Simulator.Schemas.Contract

  @ets_contracts :contract_board
  @ets_index :contract_board_index
  @max_contracts_per_requestor 5

  # --- Public API (no GenServer call needed for reads) ---

  @doc """
  Starts the ContractBoard.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Posts a new contract to the board.
  """
  @spec post_contract(map()) :: {:ok, map()} | {:error, atom()}
  def post_contract(attrs) do
    GenServer.call(__MODULE__, {:post, attrs})
  end

  @doc """
  A ship accepts a contract by ID.
  """
  @spec accept_contract(String.t(), String.t(), non_neg_integer()) ::
          {:ok, map()} | {:error, atom()}
  def accept_contract(contract_id, fulfiller_id, tick) do
    GenServer.call(__MODULE__, {:accept, contract_id, fulfiller_id, tick})
  end

  @doc """
  Marks a contract as in_progress.
  """
  @spec begin_work(String.t()) :: {:ok, map()} | {:error, atom()}
  def begin_work(contract_id) do
    GenServer.call(__MODULE__, {:begin_work, contract_id})
  end

  @doc """
  Records a delivery against a contract. Supports partial fills.
  """
  @spec deliver(String.t(), non_neg_integer()) :: {:ok, map()} | {:error, atom()}
  def deliver(contract_id, delivered_quantity) do
    GenServer.call(__MODULE__, {:deliver, contract_id, delivered_quantity})
  end

  @doc """
  Releases escrow payment. Returns `{:ok, contract, payout}`.
  """
  @spec release_payment(String.t(), non_neg_integer()) ::
          {:ok, map(), non_neg_integer()} | {:error, atom()}
  def release_payment(contract_id, tick) do
    GenServer.call(__MODULE__, {:release_payment, contract_id, tick})
  end

  # --- Delivery Contract API ---

  @doc """
  Ship picks up cargo for a delivery contract. Transitions accepted → picked_up.
  """
  @spec pickup_cargo(String.t(), String.t(), non_neg_integer()) ::
          {:ok, map()} | {:error, atom()}
  def pickup_cargo(contract_id, ship_id, tick) do
    GenServer.call(__MODULE__, {:pickup_cargo, contract_id, ship_id, tick})
  end

  @doc """
  Ship has departed with cargo. Transitions picked_up → in_transit.
  """
  @spec begin_transit(String.t()) :: {:ok, map()} | {:error, atom()}
  def begin_transit(contract_id) do
    GenServer.call(__MODULE__, {:begin_transit, contract_id})
  end

  @doc """
  Ship delivers cargo at destination. Transitions in_transit → delivered → completed.
  Returns `{:ok, contract, payout}` where payout = delivery_fee + cargo_deposit.
  """
  @spec confirm_delivery(String.t(), non_neg_integer()) ::
          {:ok, map(), non_neg_integer()} | {:error, atom()}
  def confirm_delivery(contract_id, tick) do
    GenServer.call(__MODULE__, {:confirm_delivery, contract_id, tick})
  end

  @doc """
  Returns all contracts in the board, sorted by posted_at_tick (oldest first).
  Used by the dashboard to display the full contract board.
  """
  @spec all_contracts() :: [map()]
  def all_contracts do
    :ets.tab2list(@ets_contracts)
    |> Enum.map(&elem(&1, 1))
    |> Enum.sort_by(& &1.posted_at_tick)
  end

  @doc """
  Queries available contracts efficiently using the index.

  Options:
    * `:from` — querier's location (enables distance sort/filter, uses index)
    * `:min_distance` / `:max_distance` — filter by travel ticks
    * `:destination` — specific destination (indexed O(1) lookup)
    * `:commodity` — filter by commodity
    * `:status` — default "posted"
    * `:sort` — `:distance` (default w/ `:from`), `:payment`, `:value`
    * `:limit` — max results (default 20)

  Reads from ETS directly — no GenServer call.
  """
  @spec query_contracts(keyword()) :: [map()]
  def query_contracts(opts \\ []) do
    status = Keyword.get(opts, :status, "posted")
    from = Keyword.get(opts, :from)
    destination = Keyword.get(opts, :destination)
    source = Keyword.get(opts, :source)
    limit = Keyword.get(opts, :limit, 20)

    contract_ids =
      cond do
        # Specific source location — find delivery contracts to pick up nearby
        source != nil ->
          lookup_index(status, source)

        # Specific destination — single index lookup
        destination != nil ->
          lookup_index(status, destination)

        # From a location — lookup all reachable destinations (and sources)
        from != nil ->
          Simulator.World.Travel.reachable_from(from)
          |> Enum.flat_map(&lookup_index(status, &1))

        # No location context — scan (fallback, avoid at scale)
        true ->
          :ets.tab2list(@ets_contracts)
          |> Enum.map(&elem(&1, 0))
      end

    # Fetch full contracts and apply filters
    contracts =
      contract_ids
      |> Enum.uniq()
      |> Enum.flat_map(fn id ->
        case :ets.lookup(@ets_contracts, id) do
          [{_, c}] when c.status == status -> [c]
          _ -> []
        end
      end)
      |> maybe_filter(:commodity, Keyword.get(opts, :commodity))
      |> filter_by_reputation(Keyword.get(opts, :faction_reputation))

    # Add distance and filter by distance range
    contracts =
      if from do
        contracts
        |> Enum.map(fn c ->
          Map.put(c, :distance, resolve_distance(from, c.destination_location))
        end)
        |> Enum.reject(&(&1.distance == 999_999))
        |> maybe_filter_distance(:min, Keyword.get(opts, :min_distance))
        |> maybe_filter_distance(:max, Keyword.get(opts, :max_distance))
      else
        contracts
      end

    sort = Keyword.get(opts, :sort, if(from, do: :distance, else: :payment))

    contracts
    |> sort_contracts(sort)
    |> Enum.take(limit)
  end

  @doc """
  Returns all contracts for a specific requestor.
  """
  @spec contracts_for(String.t()) :: [map()]
  def contracts_for(requestor_id) do
    # Use match spec for efficient filtering without full scan
    :ets.tab2list(@ets_contracts)
    |> Enum.map(&elem(&1, 1))
    |> Enum.filter(&(&1.requestor_id == requestor_id))
  end

  @doc """
  Returns active contract count for a requestor.
  """
  @spec active_count_for(String.t()) :: non_neg_integer()
  def active_count_for(requestor_id) do
    contracts_for(requestor_id)
    |> Enum.count(&(&1.status in ["posted", "accepted", "in_progress"]))
  end

  @doc """
  Looks up a single contract by ID.
  """
  @spec get_contract(String.t()) :: map() | nil
  def get_contract(contract_id) do
    case :ets.lookup(@ets_contracts, contract_id) do
      [{_, contract}] -> contract
      [] -> nil
    end
  end

  @doc """
  Resets the board. Used in tests.
  """
  @spec reset() :: :ok
  def reset, do: GenServer.call(__MODULE__, :reset)

  @doc """
  Deletes a contract from the board (ETS authoritative). DB row is
  cleaned up the next time `snapshot/0` runs.
  """
  @spec delete_contract(String.t()) :: :ok
  def delete_contract(contract_id) when is_binary(contract_id) do
    GenServer.call(__MODULE__, {:delete_contract, contract_id})
  end

  @doc """
  Dumps the current ETS board to the `contracts` table atomically
  (DELETE all + INSERT all in one transaction). Called by
  `/api/admin/save` — the only DB-persist path for contracts now.

  Returns `{:ok, row_count}`.

  The 30-second call timeout accommodates very large boards (~20K+
  rows) since the transaction is a single blocking write.
  """
  @spec snapshot() :: {:ok, non_neg_integer()}
  def snapshot do
    GenServer.call(__MODULE__, :snapshot, 30_000)
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(_opts) do
    contracts =
      if :ets.whereis(@ets_contracts) == :undefined do
        :ets.new(@ets_contracts, [
          :named_table,
          :set,
          :public,
          read_concurrency: true,
          write_concurrency: true
        ])
      else
        @ets_contracts
      end

    index =
      if :ets.whereis(@ets_index) == :undefined do
        :ets.new(@ets_index, [
          :named_table,
          :bag,
          :public,
          read_concurrency: true,
          write_concurrency: true
        ])
      else
        @ets_index
      end

    Simulator.Events.subscribe("tick")

    # Rebuild ETS from any contracts persisted on disk so a restart
    # preserves in-flight delivery/supply state. `next_id` advances
    # past the max id found on disk so new contracts don't clash.
    next_id = load_from_db(contracts, index)

    {:ok, %{contracts: contracts, index: index, next_id: next_id}}
  end

  defp load_from_db(contracts_table, index_table) do
    try do
      rows = Repo.all(Contract)

      Enum.each(rows, fn row ->
        contract = contract_from_row(row)
        :ets.insert(contracts_table, {contract.id, contract})
        insert_into_index(index_table, contract)
      end)

      Logger.info("ContractBoard: restored #{length(rows)} contracts from DB")

      max_next_id(rows)
    rescue
      # If contracts table is absent (first boot, migration pending),
      # we just start empty.
      e ->
        Logger.warning("ContractBoard: skipped DB load (#{inspect(e)})")
        1
    end
  end

  defp insert_into_index(index_table, contract) do
    :ets.insert(
      index_table,
      {{contract.status, contract.destination_location}, contract.id}
    )

    if contract[:source_location] do
      :ets.insert(
        index_table,
        {{contract.status, contract.source_location}, contract.id}
      )
    end
  end

  defp max_next_id([]), do: 1

  defp max_next_id(rows) do
    rows
    |> Enum.map(&parse_contract_seq/1)
    |> Enum.max(fn -> 0 end)
    |> Kernel.+(1)
  end

  defp parse_contract_seq(%{contract_id: "contract-" <> rest}) do
    case Integer.parse(rest) do
      {n, _} -> n
      _ -> 0
    end
  end

  defp parse_contract_seq(_), do: 0

  @impl true
  def handle_call({:post, attrs}, _from, state) do
    requestor_id = attrs[:requestor_id]

    if active_count_for(requestor_id) >= @max_contracts_per_requestor do
      {:reply, {:error, :too_many_contracts}, state}
    else
      case ContractLifecycle.post(attrs) do
        {:ok, contract} ->
          contract_id = "contract-#{state.next_id}"
          contract = Map.put(contract, :id, contract_id)

          insert_contract(contract)

          Simulator.Events.broadcast("contracts", :contract_posted, %{
            id: contract_id,
            contract_type: Map.get(contract, :contract_type),
            commodity: Map.get(contract, :commodity),
            quantity: Map.get(contract, :quantity),
            passenger_count: Map.get(contract, :passenger_count),
            destination: contract.destination_location,
            payment: contract.payment
          })

          {:reply, {:ok, contract}, %{state | next_id: state.next_id + 1}}
      end
    end
  end

  def handle_call({:accept, contract_id, fulfiller_id, tick}, _from, state) do
    case :ets.lookup(@ets_contracts, contract_id) do
      [{_, contract}] ->
        case ContractLifecycle.accept(contract, fulfiller_id, tick) do
          {:ok, updated} ->
            update_contract(contract, updated)
            {:reply, {:ok, updated}, state}

          error ->
            {:reply, error, state}
        end

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:begin_work, contract_id}, _from, state) do
    with_contract(contract_id, state, &ContractLifecycle.begin_work/1)
  end

  def handle_call({:deliver, contract_id, quantity}, _from, state) do
    with_contract(contract_id, state, &ContractLifecycle.fulfill(&1, quantity))
  end

  def handle_call({:release_payment, contract_id, tick}, _from, state) do
    case :ets.lookup(@ets_contracts, contract_id) do
      [{_, contract}] ->
        with {:ok, paid_contract, payout} <- ContractLifecycle.pay(contract),
             {:ok, completed} <- ContractLifecycle.complete(paid_contract, tick) do
          update_contract(contract, completed)
          {:reply, {:ok, completed, payout}, state}
        else
          error -> {:reply, error, state}
        end

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:pickup_cargo, contract_id, ship_id, tick}, _from, state) do
    case :ets.lookup(@ets_contracts, contract_id) do
      [{_, contract}] ->
        if contract.fulfiller_id == ship_id do
          case ContractLifecycle.pickup(contract, tick) do
            {:ok, updated} ->
              update_contract(contract, updated)
              {:reply, {:ok, updated}, state}

            error ->
              {:reply, error, state}
          end
        else
          {:reply, {:error, :wrong_fulfiller}, state}
        end

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:begin_transit, contract_id}, _from, state) do
    with_contract(contract_id, state, &ContractLifecycle.begin_transit/1)
  end

  def handle_call({:confirm_delivery, contract_id, tick}, _from, state) do
    case :ets.lookup(@ets_contracts, contract_id) do
      [{_, contract}] ->
        with {:ok, delivered, payout} <- ContractLifecycle.confirm_delivery(contract, tick),
             {:ok, completed} <- ContractLifecycle.complete_delivery(delivered, tick) do
          update_contract(contract, completed)
          {:reply, {:ok, completed, payout}, state}
        else
          error -> {:reply, error, state}
        end

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call(:reset, _from, state) do
    :ets.delete_all_objects(@ets_contracts)
    :ets.delete_all_objects(@ets_index)
    # Intentionally leave the DB alone: reset/0 is test-only, and
    # DataCase rolls back its own Repo transactions. Hitting Repo
    # from a non-sandboxed process raises noisy ownership errors.
    {:reply, :ok, %{state | next_id: 1}}
  end

  def handle_call({:delete_contract, id}, _from, state) do
    case :ets.lookup(@ets_contracts, id) do
      [{_, contract}] ->
        :ets.delete(@ets_contracts, id)
        :ets.delete_object(@ets_index, {{contract.status, contract.destination_location}, id})

        if contract[:source_location] do
          :ets.delete_object(@ets_index, {{contract.status, contract.source_location}, id})
        end

      # DB row goes away on the next snapshot — ETS is
      # authoritative between saves.

      [] ->
        :ok
    end

    {:reply, :ok, state}
  end

  def handle_call(:snapshot, _from, state) do
    count = do_snapshot()
    {:reply, {:ok, count}, state}
  end

  @impl true
  def handle_info({:tick, %{tick: tick}}, state) do
    # Escalate and expire — only scan posted/active contracts via index
    posted_ids = lookup_index_by_status("posted")

    active_ids =
      lookup_index_by_status("accepted") ++ lookup_index_by_status("in_progress")

    delivery_ids =
      lookup_index_by_status("picked_up") ++ lookup_index_by_status("in_transit")

    for id <- posted_ids do
      case :ets.lookup(@ets_contracts, id) do
        [{_, contract}] ->
          if contract.deadline_tick && tick > contract.deadline_tick do
            case ContractLifecycle.expire(contract) do
              {:ok, expired, _refund} -> update_contract(contract, expired)
              _ -> :ok
            end
          else
            # Escalate price AND open access based on age
            contract = ContractLifecycle.escalate(contract)
            contract = age_contract_access(contract, tick)
            :ets.insert(@ets_contracts, {id, contract})
            # Route a small per-tick demand signal to the destination market so
            # stuck contracts pressure local prices upward, not just the
            # contract's own escrow.
            route_demand_pressure(contract)
          end

        _ ->
          :ok
      end
    end

    for id <- active_ids do
      case :ets.lookup(@ets_contracts, id) do
        [{_, contract}] ->
          if contract.deadline_tick && tick > contract.deadline_tick do
            case ContractLifecycle.expire(contract) do
              {:ok, expired, _refund} -> update_contract(contract, expired)
              _ -> :ok
            end
          end

        _ ->
          :ok
      end
    end

    # Delivery contracts in transit past deadline — forfeit deposit
    for id <- delivery_ids do
      case :ets.lookup(@ets_contracts, id) do
        [{_, contract}] ->
          if contract.deadline_tick && tick > contract.deadline_tick do
            case ContractLifecycle.forfeit_deposit(contract) do
              {:ok, expired, _forfeited} -> update_contract(contract, expired)
              _ -> :ok
            end
          end

        _ ->
          :ok
      end
    end

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # --- Private: ETS Operations ---

  defp insert_contract(contract) do
    :ets.insert(@ets_contracts, {contract.id, contract})
    :ets.insert(@ets_index, {{contract.status, contract.destination_location}, contract.id})

    # Also index by source_location for delivery contracts
    if contract[:source_location] do
      :ets.insert(@ets_index, {{contract.status, contract.source_location}, contract.id})
    end
  end

  defp update_contract(old, new) do
    :ets.insert(@ets_contracts, {new.id, new})

    # Update index if status or destination changed
    if old.status != new.status or old.destination_location != new.destination_location do
      :ets.delete_object(@ets_index, {{old.status, old.destination_location}, old.id})
      :ets.insert(@ets_index, {{new.status, new.destination_location}, new.id})

      # Update source_location index for delivery contracts
      if old[:source_location] do
        :ets.delete_object(@ets_index, {{old.status, old.source_location}, old.id})
      end

      if new[:source_location] do
        :ets.insert(@ets_index, {{new.status, new.source_location}, new.id})
      end
    end
  end

  # --- Private: DB persistence ---

  # The board is ETS-authoritative during normal run. Persistence to
  # DB happens only via `snapshot/0`, which the save endpoint invokes.
  # This keeps the hot mutation path (per-tick escalation across ~20K
  # contracts) free of per-call mark_dirty / SQL round-trips — they'd
  # be wasted work since the save endpoint will capture the board
  # atomically anyway.
  defp do_snapshot do
    rows =
      :ets.tab2list(@ets_contracts)
      |> Enum.map(fn {_id, contract} -> contract_to_row(contract) end)

    {:ok, count} =
      Repo.transaction(fn ->
        Repo.delete_all(Contract)

        # Chunk to stay under SQLite's variable limit (~32K).
        # At ~30 fields per row → 1000 rows per chunk is safe.
        Enum.chunk_every(rows, 500)
        |> Enum.each(fn chunk ->
          Repo.insert_all(Contract, chunk, returning: false)
        end)

        length(rows)
      end)

    count
  end

  # insert_all bypasses changeset — timestamps are supplied manually
  # so Ecto doesn't complain.
  defp contract_to_row(contract) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    contract
    |> contract_to_attrs()
    |> Map.put(:inserted_at, now)
    |> Map.put(:updated_at, now)
  end

  # ETS contract map → changeset attrs map. Only persists what the
  # schema knows about — anything else (like `:distance` added by
  # query_contracts) is dropped.
  defp contract_to_attrs(contract) do
    %{
      contract_id: contract.id,
      contract_type: to_str(contract[:contract_type]),
      status: contract.status,
      requestor_type: contract[:requestor_type],
      requestor_id: contract[:requestor_id],
      fulfiller_type: contract[:fulfiller_type],
      fulfiller_id: contract[:fulfiller_id],
      commodity: to_str(contract[:commodity]),
      quantity: contract[:quantity] || 0,
      quantity_remaining: contract[:quantity_remaining] || 0,
      source_location: contract[:source_location],
      destination_location: contract[:destination_location],
      payment: contract[:payment],
      escrow_amount: contract[:escrow_amount] || 0,
      urgency: contract[:urgency] || 0.0,
      escalation_rate: contract[:escalation_rate] || 0.0,
      posted_at_tick: contract[:posted_at_tick],
      accepted_at_tick: contract[:accepted_at_tick],
      deadline_tick: contract[:deadline_tick],
      completed_at_tick: contract[:completed_at_tick],
      faction_id: contract[:faction_id],
      min_reputation: contract[:min_reputation],
      faction_bonus: contract[:faction_bonus],
      delivery_fee: contract[:delivery_fee],
      cargo_deposit: contract[:cargo_deposit],
      cargo_value: contract[:cargo_value],
      reserve_id: contract[:reserve_id],
      picked_up_at_tick: contract[:picked_up_at_tick],
      delivered_at_tick: contract[:delivered_at_tick],
      passenger_count: contract[:passenger_count]
    }
  end

  # DB row → ETS contract map. Mirror of contract_to_attrs so the
  # round-trip is lossless. `commodity` is kept as a binary in ETS
  # since the ETS struct already handles both atoms and binaries
  # throughout the codebase.
  defp contract_from_row(%Contract{} = row) do
    %{
      id: row.contract_id,
      contract_type: row.contract_type,
      status: row.status,
      requestor_type: row.requestor_type,
      requestor_id: row.requestor_id,
      fulfiller_type: row.fulfiller_type,
      fulfiller_id: row.fulfiller_id,
      commodity: row.commodity,
      quantity: row.quantity,
      quantity_remaining: row.quantity_remaining,
      source_location: row.source_location,
      destination_location: row.destination_location,
      payment: row.payment,
      escrow_amount: row.escrow_amount,
      urgency: row.urgency,
      escalation_rate: row.escalation_rate,
      posted_at_tick: row.posted_at_tick,
      accepted_at_tick: row.accepted_at_tick,
      deadline_tick: row.deadline_tick,
      completed_at_tick: row.completed_at_tick,
      faction_id: row.faction_id,
      min_reputation: row.min_reputation,
      faction_bonus: row.faction_bonus,
      delivery_fee: row.delivery_fee,
      cargo_deposit: row.cargo_deposit,
      cargo_value: row.cargo_value,
      reserve_id: row.reserve_id,
      picked_up_at_tick: row.picked_up_at_tick,
      delivered_at_tick: row.delivered_at_tick,
      passenger_count: row.passenger_count
    }
  end

  defp to_str(nil), do: nil
  defp to_str(s) when is_binary(s), do: s
  defp to_str(a) when is_atom(a), do: Atom.to_string(a)
  defp to_str(other), do: to_string(other)

  defp lookup_index(status, destination) do
    :ets.lookup(@ets_index, {status, destination})
    |> Enum.map(&elem(&1, 1))
  end

  defp lookup_index_by_status(status) do
    # Match all destinations for a given status
    :ets.match(@ets_index, {{status, :_}, :"$1"})
    |> Enum.map(&hd/1)
  end

  defp with_contract(contract_id, state, fun) do
    case :ets.lookup(@ets_contracts, contract_id) do
      [{_, contract}] ->
        case fun.(contract) do
          {:ok, updated} ->
            update_contract(contract, updated)
            {:reply, {:ok, updated}, state}

          error ->
            {:reply, error, state}
        end

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  # --- Private: Filtering & Sorting ---

  # Contracts gradually open to wider audiences as they age
  @tm Simulator.Simulation.Config.tick_multiplier()

  # Amortize the contract's quantity across the market's demand window (100
  # ticks) so a single stuck contract contributes ~quantity units of pent-up
  # demand to the rolling window total while it remains posted.
  @demand_bump_window 100

  defp route_demand_pressure(contract) do
    with dest when is_binary(dest) <- contract[:destination_location],
         commodity when is_binary(commodity) or is_atom(commodity) <- contract[:commodity],
         qty when is_number(qty) and qty > 0 <-
           contract[:quantity] || contract[:quantity_remaining],
         {:ok, pid} <- Simulator.Agents.Agent.whereis("market-#{dest}"),
         commodity_atom when is_atom(commodity_atom) <- to_commodity_atom(commodity) do
      bump = max(round(qty / @demand_bump_window), 1)
      Simulator.Agents.MarketAgent.bump_demand(pid, commodity_atom, bump)
    else
      _ -> :ok
    end
  end

  defp to_commodity_atom(commodity) when is_atom(commodity), do: commodity

  defp to_commodity_atom(commodity) when is_binary(commodity) do
    String.to_existing_atom(commodity)
  rescue
    ArgumentError -> nil
  end

  defp to_commodity_atom(_), do: nil

  defp age_contract_access(contract, current_tick) do
    age = current_tick - (contract.posted_at_tick || 0)

    new_min_rep =
      cond do
        age < 50 * @tm -> 30
        age < 150 * @tm -> 20
        age < 300 * @tm -> 10
        true -> 0
      end

    # Only decrease reputation requirement, never increase
    if new_min_rep < (contract.min_reputation || 60) do
      %{contract | min_reputation: new_min_rep}
    else
      contract
    end
  end

  defp filter_by_reputation(contracts, nil), do: contracts

  defp filter_by_reputation(contracts, rep_map) do
    Enum.filter(contracts, fn contract ->
      faction_id = contract[:faction_id]
      min_rep = contract[:min_reputation] || 0

      if faction_id && min_rep > 0 do
        Simulator.Economy.Reputation.meets_requirement?(rep_map, faction_id, min_rep)
      else
        true
      end
    end)
  end

  defp maybe_filter(contracts, _field, nil), do: contracts

  defp maybe_filter(contracts, field, value) do
    value_str = to_string(value)
    Enum.filter(contracts, &(to_string(Map.get(&1, field)) == value_str))
  end

  defp maybe_filter_distance(contracts, _dir, nil), do: contracts

  defp maybe_filter_distance(contracts, :min, d),
    do: Enum.filter(contracts, &((&1[:distance] || 0) >= d))

  defp maybe_filter_distance(contracts, :max, d),
    do: Enum.filter(contracts, &((&1[:distance] || 999_999) <= d))

  defp resolve_distance(from, to) do
    case Simulator.World.Travel.travel_time(from, to) do
      {:ok, ticks} -> ticks
      {:error, _} -> 999_999
    end
  end

  defp sort_contracts(contracts, :distance),
    do: Enum.sort_by(contracts, &(&1[:distance] || 999_999), :asc)

  defp sort_contracts(contracts, :payment), do: Enum.sort_by(contracts, & &1.payment, :desc)

  defp sort_contracts(contracts, :value) do
    Enum.sort_by(contracts, fn c -> c.payment / max(c[:distance] || 1, 1) end, :desc)
  end

  defp sort_contracts(contracts, _), do: contracts
end
