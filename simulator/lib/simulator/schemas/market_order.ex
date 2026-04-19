defmodule Simulator.Schemas.MarketOrder do
  @moduledoc """
  Ecto schema for a pending buy or sell order on a market.

  Orders are persisted so they survive restarts. The `agent_type` and
  `agent_id` identify the placing agent polymorphically (e.g., "ship" + ship.id).
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "market_orders" do
    field :agent_type, :string
    field :agent_id, :integer
    field :type, :string
    field :commodity, :string
    field :quantity, :integer
    field :price, :float
    field :placed_at_tick, :integer

    belongs_to :market, Simulator.Schemas.Market

    timestamps()
  end

  @doc """
  Changeset for creating a market order.
  """
  @spec changeset(%__MODULE__{} | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(order, attrs) do
    order
    |> cast(attrs, [
      :market_id,
      :agent_type,
      :agent_id,
      :type,
      :commodity,
      :quantity,
      :price,
      :placed_at_tick
    ])
    |> validate_required([
      :market_id,
      :agent_type,
      :agent_id,
      :type,
      :commodity,
      :quantity,
      :price,
      :placed_at_tick
    ])
    |> validate_inclusion(:type, ~w(buy sell))
    |> validate_number(:quantity, greater_than: 0)
    |> validate_number(:price, greater_than: 0)
    |> foreign_key_constraint(:market_id)
  end
end
