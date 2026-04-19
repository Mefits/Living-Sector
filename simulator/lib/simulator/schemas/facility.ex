defmodule Simulator.Schemas.Facility do
  @moduledoc """
  Ecto schema for a station, port, colony, or habitat.

  Relational columns (location, docking capacity, services, condition) are
  indexed for queries. The `state` JSONB column holds volatile data like
  docked ship lists and workforce details that change frequently.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "facilities" do
    field :name, :string
    field :type, :string
    field :docking_capacity, :integer, default: 10
    field :services, {:array, :string}, default: []
    field :condition, :float, default: 1.0
    field :reputation, :integer, default: 50
    field :credits, :integer, default: 0
    field :faction_id, :string
    field :body_id, :string
    field :initial_reserves, :map, default: %{}
    field :state, :map, default: %{}

    belongs_to :location, Simulator.Schemas.Location
    has_one :market, Simulator.Schemas.Market
    has_many :crew_members, Simulator.Schemas.CrewMember
    has_many :populations, Simulator.Schemas.Population

    timestamps()
  end

  @doc """
  Changeset for creating or updating a facility.
  """
  @spec changeset(%__MODULE__{} | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(facility, attrs) do
    facility
    |> cast(attrs, [
      :name,
      :type,
      :location_id,
      :docking_capacity,
      :services,
      :condition,
      :reputation,
      :credits,
      :faction_id,
      :body_id,
      :initial_reserves,
      :state
    ])
    |> validate_required([:name, :type, :location_id])
    |> validate_inclusion(
      :type,
      ~w(station colony outpost orbital_hub mining_rig refinery factory farm hub)
    )
    |> validate_number(:condition, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> foreign_key_constraint(:location_id)
  end
end
