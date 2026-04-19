defmodule Simulator.Schemas.Faction do
  @moduledoc """
  Ecto schema for factions — organizations that own facilities, employ
  ships/crew, and control contract access via reputation.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}

  schema "factions" do
    field :name, :string
    field :type, :string
    field :description, :string
    field :home_system, :string
    field :personality, :map, default: %{}
    field :colors, :map, default: %{}
    field :treasury, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating/updating a faction.
  """
  def changeset(faction, attrs) do
    faction
    |> cast(attrs, [
      :id,
      :name,
      :type,
      :description,
      :home_system,
      :personality,
      :colors,
      :treasury
    ])
    |> validate_required([:id, :name, :type])
  end
end
