defmodule Simulator.Repo.Migrations.DropNameUniqueOnShipsAndFacilities do
  @moduledoc """
  Admin / god-mode endpoints let the user name ships and facilities
  anything they want; uniqueness only matters at the agent-registry /
  id level. Drop the DB-side unique name constraints so users can
  have two "Void Star" ships or two "Hermes Station" facilities
  without us renaming them.

  Non-user-facing identifiers (locations, bodies, factions, systems)
  keep their unique name constraints — those are referenced by name
  in code paths and shouldn't collide.
  """

  use Ecto.Migration

  def change do
    drop_if_exists index(:ships, [:name])
    drop_if_exists index(:facilities, [:name])
  end
end
