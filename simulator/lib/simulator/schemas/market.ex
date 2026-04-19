defmodule Simulator.Schemas.Market do
  @moduledoc """
  Ecto schema for a local market at a facility.

  Core economic data (prices, supply, demand, production) is stored in
  dedicated JSONB columns for direct access. The `state` column holds
  additional volatile data like price history and trade volume.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "markets" do
    field :prices, :map, default: %{}
    field :supply, :map, default: %{}
    field :demand, :map, default: %{}
    field :production, :map, default: %{}
    field :consumption, :map, default: %{}
    field :price_elasticity, :float, default: 0.05
    field :spread, :float, default: 0.10
    field :facility_location, :string
    field :state, :map, default: %{}

    belongs_to :facility, Simulator.Schemas.Facility
    has_many :market_orders, Simulator.Schemas.MarketOrder
    has_many :trades, Simulator.Schemas.Trade

    timestamps()
  end

  @doc """
  Changeset for creating or updating a market.
  """
  @spec changeset(%__MODULE__{} | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(market, attrs) do
    market
    |> cast(attrs, [
      :facility_id,
      :prices,
      :supply,
      :demand,
      :production,
      :consumption,
      :price_elasticity,
      :spread,
      :state
    ])
    |> validate_required([:facility_id])
    |> validate_number(:price_elasticity, greater_than: 0)
    |> validate_number(:spread, greater_than_or_equal_to: 0)
    |> unique_constraint(:facility_id)
    |> foreign_key_constraint(:facility_id)
  end
end
