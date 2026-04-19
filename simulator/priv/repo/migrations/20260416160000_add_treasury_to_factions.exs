defmodule Simulator.Repo.Migrations.AddTreasuryToFactions do
  use Ecto.Migration

  def change do
    alter table(:factions) do
      add :treasury, :integer, default: 0
    end
  end
end
