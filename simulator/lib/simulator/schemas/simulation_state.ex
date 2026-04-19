defmodule Simulator.Schemas.SimulationState do
  @moduledoc """
  Key-value store for global simulation state.

  Persists data that doesn't belong to any single agent, such as the
  current tick number, simulation speed, and global flags. Uses a string
  primary key so entries are addressed by name (e.g., `"tick_coordinator"`).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:key, :string, autogenerate: false}

  schema "simulation_state" do
    field :value, :map, default: %{}

    timestamps()
  end

  @doc """
  Changeset for upserting simulation state.
  """
  @spec changeset(%__MODULE__{} | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(state, attrs) do
    state
    |> cast(attrs, [:key, :value])
    |> validate_required([:key])
  end
end
