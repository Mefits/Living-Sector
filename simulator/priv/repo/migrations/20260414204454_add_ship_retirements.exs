defmodule Simulator.Repo.Migrations.AddShipRetirements do
  use Ecto.Migration

  def change do
    create table(:ship_retirements) do
      add :ship_id, :string, null: false
      add :name, :string, null: false
      add :class, :string
      add :faction_id, :string
      add :final_location, :string
      add :new_location, :string
      add :final_credits, :integer, default: 0
      add :cargo_value, :integer, default: 0
      add :crew_size, :integer, default: 0
      add :crew_morale, :integer, default: 0
      add :tick, :integer, null: false
      add :reason, :string, default: "bankruptcy"

      timestamps(type: :utc_datetime)
    end

    create index(:ship_retirements, [:ship_id])
    create index(:ship_retirements, [:tick])
  end
end
