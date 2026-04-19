defmodule Simulator.Repo.Migrations.AddBiomeAndStateToCelestialBodies do
  use Ecto.Migration

  def change do
    alter table(:celestial_bodies) do
      add :biome, :string
      add :state, :map, default: %{}
    end
  end
end
