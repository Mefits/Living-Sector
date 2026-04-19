defmodule Simulator.Schemas.StarSystem do
  @moduledoc """
  Ecto schema for a solar system.

  Each star system contains celestial bodies (planets, moons, belts) and is
  managed by a `SystemAgent` at runtime. The `state` JSONB column holds
  volatile simulation data (tech_level, piracy_threat, comm relay coverage)
  that persists across restarts without requiring migrations for new fields.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "star_systems" do
    field :name, :string
    field :universe_offset_x, :float, default: 0.0
    field :universe_offset_y, :float, default: 0.0
    field :state, :map, default: %{}

    has_many :celestial_bodies, Simulator.Schemas.CelestialBody

    timestamps()
  end

  @doc """
  Changeset for creating or updating a star system.
  """
  @spec changeset(%__MODULE__{} | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(star_system, attrs) do
    star_system
    |> cast(attrs, [:name, :state])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end
