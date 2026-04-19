defmodule Simulator.Schemas.Population do
  @moduledoc """
  Ecto schema for a population demographic bloc.

  Represents thousands or millions of people abstracted into a single record.
  Key aggregates (population count, sentiment, unrest, wealth) are direct
  columns. The `state` JSONB column holds satisfaction breakdowns, consumption
  rates, migration pressure, and VIP tracking.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "populations" do
    field :label, :string
    field :demographic, :string
    field :population_count, :integer, default: 0
    field :overall_sentiment, :integer, default: 50
    field :unrest, :integer, default: 0
    field :total_wealth, :integer, default: 0
    field :faction_id, :string
    field :food_satisfaction, :integer, default: 50
    field :consumption, :map, default: %{}
    field :production_commodity, :string
    field :production_amount, :integer, default: 0
    field :employed_fraction, :float, default: 0.85
    field :spending_rate, :float, default: 0.02
    field :growth_rate, :float, default: 0.001
    field :state, :map, default: %{}

    belongs_to :facility, Simulator.Schemas.Facility

    timestamps()
  end

  @doc """
  Changeset for creating or updating a population bloc.
  """
  @spec changeset(%__MODULE__{} | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(population, attrs) do
    population
    |> cast(attrs, [
      :label,
      :demographic,
      :facility_id,
      :population_count,
      :overall_sentiment,
      :unrest,
      :total_wealth,
      :food_satisfaction,
      :state
    ])
    |> validate_required([:label, :demographic, :facility_id])
    |> validate_inclusion(:demographic, ~w(workers merchants scientists military unemployed))
    |> validate_number(:population_count, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:facility_id)
  end
end
