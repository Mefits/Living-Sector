defmodule Simulator.Schemas.ShipRetirement do
  @moduledoc """
  Ecto schema for recording ship decommissions.

  When a ship goes bankrupt and gets recycled, its final state is
  persisted here for historical review. Survives server restarts.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "ship_retirements" do
    field :ship_id, :string
    field :name, :string
    field :class, :string
    field :faction_id, :string
    field :final_location, :string
    field :new_location, :string
    field :final_credits, :integer, default: 0
    field :cargo_value, :integer, default: 0
    field :crew_size, :integer, default: 0
    field :crew_morale, :integer, default: 0
    field :tick, :integer
    field :reason, :string, default: "bankruptcy"

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a ship retirement record.
  """
  def changeset(retirement, attrs) do
    retirement
    |> cast(attrs, [
      :ship_id,
      :name,
      :class,
      :faction_id,
      :final_location,
      :new_location,
      :final_credits,
      :cargo_value,
      :crew_size,
      :crew_morale,
      :tick,
      :reason
    ])
    |> validate_required([:ship_id, :name, :tick])
  end
end
