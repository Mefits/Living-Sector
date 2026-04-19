defmodule Simulator.Schemas.Ship do
  @moduledoc """
  Ecto schema for a vessel in the simulation.

  Indexed columns cover the fields needed for queries (location, credits).
  The `state` JSONB column holds volatile simulation data: transit info,
  current plan, price memory, visited locations, and blacklist.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "ships" do
    field :name, :string
    field :class, :string, default: "freighter"
    field :cargo, :map, default: %{}
    field :cargo_capacity, :integer, default: 500
    field :fuel, :float, default: 100.0
    field :fuel_capacity, :float, default: 100.0
    field :fuel_consumption_rate, :float, default: 0.5
    field :credits, :integer, default: 5000
    field :efficiency, :float, default: 1.0
    field :faction_id, :string
    field :faction_reputation, :map, default: %{}
    field :speed_modifier, :float, default: 1.0
    field :universe_offset_x, :float, default: 0.0
    field :universe_offset_y, :float, default: 0.0
    field :system_id, :string
    field :personality, :map, default: %{}
    field :position_x, :float, default: 0.0
    field :position_y, :float, default: 0.0
    field :state, :map, default: %{}

    belongs_to :location, Simulator.Schemas.Location
    has_many :crew_members, Simulator.Schemas.CrewMember

    timestamps()
  end

  @doc """
  Changeset for creating or updating a ship.
  """
  @spec changeset(%__MODULE__{} | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(ship, attrs) do
    ship
    |> cast(attrs, [
      :name,
      :class,
      :location_id,
      :cargo,
      :cargo_capacity,
      :fuel,
      :fuel_capacity,
      :fuel_consumption_rate,
      :credits,
      :efficiency,
      :position_x,
      :position_y,
      :state
    ])
    |> validate_required([:name, :class])
    |> validate_inclusion(:class, ~w(freighter courier hauler tanker miner transport scout))
    |> validate_number(:fuel, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:location_id)
  end
end
