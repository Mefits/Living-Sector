defmodule Simulator.Schemas.Contract do
  @moduledoc """
  Ecto schema for contracts — binding agreements between agents.

  A contract represents a request for goods delivery or services,
  with escrowed payment that releases on fulfillment. Contracts are
  the economic feedback loop: facilities post what they need, ships
  fulfill for profit.

  ## Contract Types

    * `"delivery"` — deliver a quantity of commodity to a destination
    * `"supply"` — standing order, refilled when below threshold (future)

  ## Status Lifecycle

      posted → accepted → in_progress → fulfilled → paid → completed
        ↓         ↓            ↓
      expired   expired      expired (escrow returns to requestor)

  ## Partial Fills

  `quantity_remaining` tracks how much is still needed. Ships with
  smaller cargo capacity can partially fill a contract, and multiple
  ships can collaborate on large orders.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(posted accepted in_progress fulfilled paid completed expired cancelled picked_up in_transit delivered)

  schema "contracts" do
    # String ID matching the ETS key ("contract-N"). The DB still has
    # an auto-increment integer PK — `contract_id` is the round-trip
    # anchor so ContractBoard can rebuild its ETS keys on load.
    field :contract_id, :string

    field :contract_type, :string
    field :status, :string, default: "posted"
    field :requestor_type, :string
    field :requestor_id, :string
    field :fulfiller_type, :string
    field :fulfiller_id, :string
    field :commodity, :string
    field :quantity, :integer
    field :quantity_remaining, :integer
    field :source_location, :string
    field :destination_location, :string
    field :payment, :integer
    field :escrow_amount, :integer, default: 0
    field :urgency, :float, default: 0.0
    field :escalation_rate, :float, default: 0.01
    field :posted_at_tick, :integer
    field :accepted_at_tick, :integer
    field :deadline_tick, :integer
    field :completed_at_tick, :integer

    # Faction gating.
    field :faction_id, :string
    field :min_reputation, :integer
    field :faction_bonus, :float

    # Delivery-contract ledger.
    field :delivery_fee, :integer
    field :cargo_deposit, :integer
    field :cargo_value, :integer
    field :reserve_id, :string
    field :picked_up_at_tick, :integer
    field :delivered_at_tick, :integer

    # Passenger-transport ledger.
    field :passenger_count, :integer

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new contract.
  """
  def changeset(contract, attrs) do
    contract
    |> cast(attrs, [
      :contract_id,
      :contract_type,
      :status,
      :requestor_type,
      :requestor_id,
      :fulfiller_type,
      :fulfiller_id,
      :commodity,
      :quantity,
      :quantity_remaining,
      :source_location,
      :destination_location,
      :payment,
      :escrow_amount,
      :urgency,
      :escalation_rate,
      :posted_at_tick,
      :accepted_at_tick,
      :deadline_tick,
      :completed_at_tick,
      :faction_id,
      :min_reputation,
      :faction_bonus,
      :delivery_fee,
      :cargo_deposit,
      :cargo_value,
      :reserve_id,
      :picked_up_at_tick,
      :delivered_at_tick,
      :passenger_count
    ])
    |> validate_required([
      :contract_id,
      :contract_type,
      :requestor_type,
      :requestor_id,
      :commodity,
      :quantity,
      :quantity_remaining,
      :destination_location,
      :payment,
      :posted_at_tick
    ])
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:quantity, greater_than: 0)
    |> validate_number(:payment, greater_than: 0)
    |> unique_constraint(:contract_id)
  end
end
