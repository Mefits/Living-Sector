defmodule Simulator.Schemas.Location do
  @moduledoc """
  Ecto schema for a spatial anchor in the simulation.

  Locations are the nodes of the world graph — planets, orbital stations,
  asteroid belts. Ships travel between locations; facilities exist at locations.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "locations" do
    field :name, :string
    field :type, :string

    belongs_to :celestial_body, Simulator.Schemas.CelestialBody
    has_many :facilities, Simulator.Schemas.Facility
    has_many :ships, Simulator.Schemas.Ship

    timestamps()
  end

  @doc """
  Changeset for creating or updating a location.
  """
  @spec changeset(%__MODULE__{} | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(location, attrs) do
    location
    |> cast(attrs, [:name, :type, :celestial_body_id])
    |> validate_required([:name, :type, :celestial_body_id])
    |> validate_inclusion(:type, ~w(planet moon station belt hub))
    |> foreign_key_constraint(:celestial_body_id)
  end
end
