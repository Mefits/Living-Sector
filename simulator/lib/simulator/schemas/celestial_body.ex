defmodule Simulator.Schemas.CelestialBody do
  @moduledoc """
  Ecto schema for a celestial body (planet, moon, asteroid belt).

  Stores orbital parameters that the `SystemAgent` advances each tick.
  The `current_angle` is persisted so orbital positions survive restarts.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "celestial_bodies" do
    field :body_id, :string
    field :name, :string
    field :type, :string
    field :orbit_radius, :float
    field :orbit_period, :integer
    field :current_angle, :float, default: 0.0
    field :resources, :map, default: %{}
    field :biome, :string
    field :state, :map, default: %{}

    belongs_to :star_system, Simulator.Schemas.StarSystem
    has_many :locations, Simulator.Schemas.Location

    timestamps()
  end

  @doc """
  Changeset for creating or updating a celestial body.
  """
  @spec changeset(%__MODULE__{} | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(body, attrs) do
    body
    |> cast(attrs, [
      :body_id,
      :name,
      :type,
      :orbit_radius,
      :orbit_period,
      :current_angle,
      :resources,
      :biome,
      :state,
      :star_system_id
    ])
    |> validate_required([:body_id, :name, :type, :orbit_radius, :orbit_period, :star_system_id])
    |> validate_inclusion(:type, ~w(planet moon belt hub asteroid))
    |> validate_number(:orbit_radius, greater_than: 0)
    |> validate_number(:orbit_period, greater_than: 0)
    |> foreign_key_constraint(:star_system_id)
  end
end
