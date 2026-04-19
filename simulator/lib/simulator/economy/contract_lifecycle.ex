defmodule Simulator.Economy.ContractLifecycle do
  @moduledoc """
  Pure functional state machine for contract transitions.

  All functions take a contract map and return `{:ok, updated_contract}`
  or `{:error, reason}`. No side effects — credit transfers, event
  broadcasting, and persistence happen in the calling agent code.

  ## Valid Transitions (legacy supply contracts)

      posted     → accepted, expired, cancelled
      accepted   → in_progress, expired, cancelled
      in_progress → fulfilled, expired
      fulfilled  → paid
      paid       → completed

  ## Valid Transitions (delivery contracts with deposit)

      posted     → accepted, expired, cancelled
      accepted   → picked_up, expired, cancelled
      picked_up  → in_transit, expired
      in_transit → delivered, expired
      delivered  → completed
  """

  @doc """
  Creates a new contract in `:posted` status.
  """
  @spec post(map()) :: {:ok, map()}
  def post(attrs) do
    defaults = %{
      status: "posted",
      fulfiller_type: nil,
      fulfiller_id: nil,
      source_location: nil,
      faction_id: nil,
      min_reputation: 30,
      faction_bonus: 1.1,
      quantity_remaining: attrs[:quantity],
      escrow_amount: attrs[:payment],
      urgency: 0.0,
      escalation_rate: 0.01,
      accepted_at_tick: nil,
      deadline_tick: nil,
      completed_at_tick: nil,
      # Delivery contract fields
      delivery_fee: nil,
      cargo_deposit: nil,
      cargo_value: nil,
      reserve_id: nil,
      picked_up_at_tick: nil,
      delivered_at_tick: nil
    }

    {:ok, Map.merge(defaults, attrs)}
  end

  @doc """
  A ship accepts the contract.
  """
  @spec accept(map(), String.t(), non_neg_integer()) ::
          {:ok, map()} | {:error, atom()}
  def accept(%{status: "posted"} = contract, fulfiller_id, tick) do
    {:ok,
     %{
       contract
       | status: "accepted",
         fulfiller_type: "ship",
         fulfiller_id: fulfiller_id,
         accepted_at_tick: tick
     }}
  end

  def accept(_, _, _), do: {:error, :invalid_status}

  @doc """
  The ship has begun working on the contract (picked up cargo or departed).
  """
  @spec begin_work(map()) :: {:ok, map()} | {:error, atom()}
  def begin_work(%{status: "accepted"} = contract) do
    {:ok, %{contract | status: "in_progress"}}
  end

  def begin_work(_), do: {:error, :invalid_status}

  # --- Delivery Contract Transitions ---

  @doc """
  Ship picks up pre-purchased cargo at the source location.
  The ship pays a cargo deposit as insurance.
  """
  @spec pickup(map(), non_neg_integer()) :: {:ok, map()} | {:error, atom()}
  def pickup(%{status: "accepted"} = contract, tick) do
    {:ok, %{contract | status: "picked_up", picked_up_at_tick: tick}}
  end

  def pickup(_, _), do: {:error, :invalid_status}

  @doc """
  Ship has undocked from the source and is in transit to the destination.
  """
  @spec begin_transit(map()) :: {:ok, map()} | {:error, atom()}
  def begin_transit(%{status: "picked_up"} = contract) do
    {:ok, %{contract | status: "in_transit"}}
  end

  def begin_transit(_), do: {:error, :invalid_status}

  @doc """
  Ship delivers cargo at the destination. Returns the payout amount
  (delivery_fee + cargo_deposit).
  """
  @spec confirm_delivery(map(), non_neg_integer()) ::
          {:ok, map(), non_neg_integer()} | {:error, atom()}
  def confirm_delivery(%{status: status} = contract, tick)
      when status in ["picked_up", "in_transit"] do
    # Cargo-delivery contracts pay `delivery_fee + cargo_deposit` (the
    # deposit was escrowed by the ship on pickup, released on delivery).
    # Passenger and crew-mission contracts use `payment` instead because
    # they don't involve deposit-carrying cargo — fall back to that when
    # the delivery fields aren't set so those contract types pay out
    # correctly through the same lifecycle.
    payout =
      case {contract[:delivery_fee], contract[:cargo_deposit]} do
        {nil, nil} -> contract[:payment] || 0
        {fee, deposit} -> (fee || 0) + (deposit || 0)
      end

    {:ok, %{contract | status: "delivered", delivered_at_tick: tick, quantity_remaining: 0},
     payout}
  end

  def confirm_delivery(_, _), do: {:error, :invalid_status}

  @doc """
  Completes a delivered contract. Final cleanup.
  """
  @spec complete_delivery(map(), non_neg_integer()) :: {:ok, map()} | {:error, atom()}
  def complete_delivery(%{status: "delivered"} = contract, tick) do
    {:ok, %{contract | status: "completed", completed_at_tick: tick}}
  end

  def complete_delivery(_, _), do: {:error, :invalid_status}

  @doc """
  Forfeits the cargo deposit when a delivery contract expires during
  transit. The requestor keeps the deposit as compensation for lost cargo.
  Returns the deposit amount forfeited.
  """
  @spec forfeit_deposit(map()) :: {:ok, map(), non_neg_integer()} | {:error, atom()}
  def forfeit_deposit(%{status: status} = contract) when status in ["picked_up", "in_transit"] do
    forfeited = contract.cargo_deposit || 0
    {:ok, %{contract | status: "expired", cargo_deposit: 0}, forfeited}
  end

  def forfeit_deposit(_), do: {:error, :invalid_status}

  @doc """
  Delivery confirmed. Supports partial fills via `delivered_quantity`.
  """
  @spec fulfill(map(), non_neg_integer()) :: {:ok, map()} | {:error, atom()}
  def fulfill(%{status: "in_progress"} = contract, delivered_quantity) do
    remaining = max(contract.quantity_remaining - delivered_quantity, 0)

    status = if remaining == 0, do: "fulfilled", else: "in_progress"

    {:ok, %{contract | status: status, quantity_remaining: remaining}}
  end

  def fulfill(_, _), do: {:error, :invalid_status}

  @doc """
  Releases escrow to the fulfiller. Returns the amount to transfer.
  """
  @spec pay(map()) :: {:ok, map(), non_neg_integer()} | {:error, atom()}
  def pay(%{status: "fulfilled"} = contract) do
    payout = contract.escrow_amount

    {:ok, %{contract | status: "paid", escrow_amount: 0}, payout}
  end

  def pay(_), do: {:error, :invalid_status}

  @doc """
  Final cleanup — contract is done.
  """
  @spec complete(map(), non_neg_integer()) :: {:ok, map()} | {:error, atom()}
  def complete(%{status: "paid"} = contract, tick) do
    {:ok, %{contract | status: "completed", completed_at_tick: tick}}
  end

  def complete(_, _), do: {:error, :invalid_status}

  @doc """
  Contract expired without being fulfilled. Returns escrow amount to refund.
  """
  @spec expire(map()) :: {:ok, map(), non_neg_integer()} | {:error, atom()}
  def expire(%{status: status} = contract)
      when status in ["posted", "accepted", "in_progress"] do
    refund = contract.escrow_amount
    {:ok, %{contract | status: "expired", escrow_amount: 0}, refund}
  end

  def expire(_), do: {:error, :invalid_status}

  @doc """
  Requestor cancels the contract. Only from posted status. Returns escrow refund.
  """
  @spec cancel(map()) :: {:ok, map(), non_neg_integer()} | {:error, atom()}
  def cancel(%{status: "posted"} = contract) do
    refund = contract.escrow_amount
    {:ok, %{contract | status: "cancelled", escrow_amount: 0}, refund}
  end

  def cancel(_), do: {:error, :invalid_status}

  @doc """
  Escalates the contract payment based on urgency and time. Called each tick
  for unfilled contracts.
  """
  @spec escalate(map()) :: map()
  def escalate(%{status: "posted"} = contract) do
    scaled_rate = contract.escalation_rate * Simulator.Simulation.Config.tick_scale()
    increase = round(contract.payment * scaled_rate * max(contract.urgency, 0.1))

    %{
      contract
      | payment: contract.payment + increase,
        escrow_amount: contract.escrow_amount + increase
    }
  end

  def escalate(contract), do: contract
end
