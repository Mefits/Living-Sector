defmodule Simulator.Repo.Migrations.CreateFactionsAndWorldColumns do
  use Ecto.Migration

  def change do
    # --- New table: factions ---
    create table(:factions, primary_key: false) do
      add :id, :string, primary_key: true
      add :name, :string, null: false
      add :type, :string, null: false
      add :description, :text
      add :home_system, :string
      add :personality, :map, null: false, default: %{}
      add :colors, :map, null: false, default: %{}
      timestamps()
    end

    create unique_index(:factions, [:name])

    # --- Add columns to existing tables ---

    # Star systems: universe position
    alter table(:star_systems) do
      add :universe_offset_x, :float, default: 0.0
      add :universe_offset_y, :float, default: 0.0
    end

    # Celestial bodies: resource richness
    alter table(:celestial_bodies) do
      add :resources, :map, default: %{}
    end

    # Facilities: faction ownership, body reference
    alter table(:facilities) do
      add :faction_id, :string
      add :body_id, :string
      add :initial_reserves, :map, default: %{}
    end

    # Ships: faction, speed, universe offset, personality
    alter table(:ships) do
      add :faction_id, :string
      add :faction_reputation, :map, default: %{}
      add :speed_modifier, :float, default: 1.0
      add :universe_offset_x, :float, default: 0.0
      add :universe_offset_y, :float, default: 0.0
      add :system_id, :string
      add :personality, :map, default: %{}
    end

    # Populations: faction, production/consumption
    alter table(:populations) do
      add :faction_id, :string
      add :consumption, :map, default: %{}
      add :production_commodity, :string
      add :production_amount, :integer, default: 0
      add :food_satisfaction, :integer, default: 50
      add :employed_fraction, :float, default: 0.85
      add :spending_rate, :float, default: 0.02
      add :growth_rate, :float, default: 0.001
    end

    # Crew: faction
    alter table(:crew_members) do
      add :faction_id, :string
      add :personality, :map, default: %{}
      add :credits, :integer, default: 0
      add :contract_expires_tick, :integer, default: 10_000
      add :home_location, :string
      add :relationships, :map, default: %{}
    end

    # Markets: add location reference for easy lookup
    alter table(:markets) do
      add :facility_location, :string
    end

    # Unique indexes for upsert support
    create unique_index(:locations, [:name])
    create unique_index(:facilities, [:name])
    create unique_index(:ships, [:name])
    create unique_index(:populations, [:label])
    create unique_index(:celestial_bodies, [:name])
  end
end
