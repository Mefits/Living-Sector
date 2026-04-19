defmodule Simulator.Schemas.Trade do
  @moduledoc """
  Ecto schema for an executed trade.

  Immutable record of every trade that clears through a market. Used for
  the dashboard trade history, economic analysis, and debugging. Trades
  are write-once — they are never updated after insertion.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "trades" do
    field :buyer_type, :string
    field :buyer_id, :integer
    field :seller_type, :string
    field :seller_id, :integer
    field :commodity, :string
    field :quantity, :integer
    field :price, :float
    field :tick, :integer
    field :executed_at, :utc_datetime

    belongs_to :market, Simulator.Schemas.Market
  end

  @doc """
  Changeset for recording an executed trade.
  """
  @spec changeset(%__MODULE__{} | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(trade, attrs) do
    trade
    |> cast(attrs, [
      :market_id,
      :buyer_type,
      :buyer_id,
      :seller_type,
      :seller_id,
      :commodity,
      :quantity,
      :price,
      :tick,
      :executed_at
    ])
    |> validate_required([
      :market_id,
      :buyer_type,
      :buyer_id,
      :seller_type,
      :seller_id,
      :commodity,
      :quantity,
      :price,
      :tick
    ])
    |> validate_number(:quantity, greater_than: 0)
    |> validate_number(:price, greater_than: 0)
    |> foreign_key_constraint(:market_id)
  end
end
