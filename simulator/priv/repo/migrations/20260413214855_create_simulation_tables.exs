defmodule Simulator.Repo.Migrations.CreateSimulationTables do
  use Ecto.Migration

  def change do
    # --- World Layer ---

    create table(:star_systems) do
      add :name, :string, null: false
      add :state, :map, null: false, default: %{}
      timestamps()
    end

    create unique_index(:star_systems, [:name])

    create table(:celestial_bodies) do
      add :name, :string, null: false
      add :type, :string, null: false
      add :orbit_radius, :float, null: false
      add :orbit_period, :integer, null: false
      add :current_angle, :float, null: false, default: 0.0
      add :star_system_id, references(:star_systems, on_delete: :delete_all), null: false
      timestamps()
    end

    create index(:celestial_bodies, [:star_system_id])

    create table(:locations) do
      add :name, :string, null: false
      add :type, :string, null: false
      add :celestial_body_id, references(:celestial_bodies, on_delete: :delete_all), null: false
      timestamps()
    end

    create index(:locations, [:celestial_body_id])

    # --- Entity Layer ---

    create table(:facilities) do
      add :name, :string, null: false
      add :type, :string, null: false
      add :location_id, references(:locations, on_delete: :delete_all), null: false
      add :docking_capacity, :integer, null: false, default: 10
      add :services, {:array, :string}, null: false, default: []
      add :condition, :float, null: false, default: 1.0
      add :reputation, :integer, null: false, default: 50
      add :credits, :integer, null: false, default: 0
      add :state, :map, null: false, default: %{}
      timestamps()
    end

    create index(:facilities, [:location_id])

    create table(:markets) do
      add :facility_id, references(:facilities, on_delete: :delete_all), null: false
      add :prices, :map, null: false, default: %{}
      add :supply, :map, null: false, default: %{}
      add :demand, :map, null: false, default: %{}
      add :production, :map, null: false, default: %{}
      add :consumption, :map, null: false, default: %{}
      add :price_elasticity, :float, null: false, default: 0.05
      add :spread, :float, null: false, default: 0.10
      add :state, :map, null: false, default: %{}
      timestamps()
    end

    create unique_index(:markets, [:facility_id])

    create table(:ships) do
      add :name, :string, null: false
      add :class, :string, null: false, default: "freighter"
      add :location_id, references(:locations, on_delete: :nilify_all)
      add :cargo, :map, null: false, default: %{}
      add :cargo_capacity, :integer, null: false, default: 500
      add :fuel, :float, null: false, default: 100.0
      add :fuel_capacity, :float, null: false, default: 100.0
      add :fuel_consumption_rate, :float, null: false, default: 0.5
      add :credits, :integer, null: false, default: 5000
      add :efficiency, :float, null: false, default: 1.0
      add :state, :map, null: false, default: %{}
      timestamps()
    end

    create index(:ships, [:location_id])

    create table(:crew_members) do
      add :name, :string, null: false
      add :role, :string, null: false
      add :ship_id, references(:ships, on_delete: :nilify_all)
      add :facility_id, references(:facilities, on_delete: :nilify_all)
      add :hunger, :integer, null: false, default: 0
      add :fatigue, :integer, null: false, default: 0
      add :morale, :integer, null: false, default: 70
      add :health, :integer, null: false, default: 100
      add :skills, :map, null: false, default: %{}
      add :traits, {:array, :string}, null: false, default: []
      add :state, :map, null: false, default: %{}
      timestamps()
    end

    create index(:crew_members, [:ship_id])
    create index(:crew_members, [:facility_id])

    create table(:populations) do
      add :label, :string, null: false
      add :demographic, :string, null: false
      add :facility_id, references(:facilities, on_delete: :delete_all), null: false
      add :population_count, :integer, null: false, default: 0
      add :overall_sentiment, :integer, null: false, default: 50
      add :unrest, :integer, null: false, default: 0
      add :total_wealth, :integer, null: false, default: 0
      add :state, :map, null: false, default: %{}
      timestamps()
    end

    create index(:populations, [:facility_id])

    # --- Economy Layer ---

    create table(:market_orders) do
      add :market_id, references(:markets, on_delete: :delete_all), null: false
      add :agent_type, :string, null: false
      add :agent_id, :integer, null: false
      add :type, :string, null: false
      add :commodity, :string, null: false
      add :quantity, :integer, null: false
      add :price, :float, null: false
      add :placed_at_tick, :integer, null: false
      timestamps()
    end

    create index(:market_orders, [:market_id])
    create index(:market_orders, [:agent_type, :agent_id])

    create table(:trades) do
      add :market_id, references(:markets, on_delete: :delete_all), null: false
      add :buyer_type, :string, null: false
      add :buyer_id, :integer, null: false
      add :seller_type, :string, null: false
      add :seller_id, :integer, null: false
      add :commodity, :string, null: false
      add :quantity, :integer, null: false
      add :price, :float, null: false
      add :tick, :integer, null: false
      add :executed_at, :utc_datetime, null: false, default: fragment("CURRENT_TIMESTAMP")
    end

    create index(:trades, [:market_id])
    create index(:trades, [:tick])

    # --- Simulation Layer ---

    create table(:simulation_state, primary_key: false) do
      add :key, :string, primary_key: true
      add :value, :map, null: false, default: %{}
      timestamps()
    end
  end
end
