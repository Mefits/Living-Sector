defmodule Simulator.Schemas.CrewMember do
  @moduledoc """
  Ecto schema for an individual crew member.

  Core needs (hunger, fatigue, morale, health) and skills are persisted
  as direct columns for queryability. The `state` JSONB column holds
  volatile data: current task, relationships, contract info, and pay owed.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "crew_members" do
    field :name, :string
    field :role, :string
    field :hunger, :integer, default: 0
    field :fatigue, :integer, default: 0
    field :morale, :integer, default: 70
    field :health, :integer, default: 100
    field :skills, :map, default: %{}
    field :traits, {:array, :string}, default: []
    field :state, :map, default: %{}

    belongs_to :ship, Simulator.Schemas.Ship
    belongs_to :facility, Simulator.Schemas.Facility

    timestamps()
  end

  @doc """
  Changeset for creating or updating a crew member.
  """
  @spec changeset(%__MODULE__{} | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(crew_member, attrs) do
    crew_member
    |> cast(attrs, [
      :name,
      :role,
      :ship_id,
      :facility_id,
      :hunger,
      :fatigue,
      :morale,
      :health,
      :skills,
      :traits,
      :state
    ])
    |> validate_required([:name, :role])
    |> validate_inclusion(:role, ~w(pilot engineer medic gunner trader general))
    |> validate_number(:hunger, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:morale, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:health, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
  end
end
