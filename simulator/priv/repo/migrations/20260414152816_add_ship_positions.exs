defmodule Simulator.Repo.Migrations.AddShipPositions do
  use Ecto.Migration

  def change do
    alter table(:ships) do
      add :position_x, :float, default: 0.0
      add :position_y, :float, default: 0.0
    end
  end
end
