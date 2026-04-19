defmodule Simulator.Repo.Migrations.AddBodyIdToCelestialBodies do
  use Ecto.Migration

  def change do
    alter table(:celestial_bodies) do
      add :body_id, :string
    end

    create unique_index(:celestial_bodies, [:body_id])
  end
end
