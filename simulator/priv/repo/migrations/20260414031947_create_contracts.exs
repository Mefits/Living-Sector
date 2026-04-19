defmodule Simulator.Repo.Migrations.CreateContracts do
  use Ecto.Migration

  def change do
    create table(:contracts) do
      add :contract_type, :string, null: false
      add :status, :string, null: false, default: "posted"
      add :requestor_type, :string, null: false
      add :requestor_id, :string, null: false
      add :fulfiller_type, :string
      add :fulfiller_id, :string
      add :commodity, :string, null: false
      add :quantity, :integer, null: false
      add :quantity_remaining, :integer, null: false
      add :source_location, :string
      add :destination_location, :string, null: false
      add :payment, :integer, null: false
      add :escrow_amount, :integer, null: false, default: 0
      add :urgency, :float, null: false, default: 0.0
      add :escalation_rate, :float, null: false, default: 0.01
      add :posted_at_tick, :integer, null: false
      add :accepted_at_tick, :integer
      add :deadline_tick, :integer
      add :completed_at_tick, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:contracts, [:status])
    create index(:contracts, [:requestor_type, :requestor_id])
    create index(:contracts, [:fulfiller_type, :fulfiller_id])
    create index(:contracts, [:destination_location])
    create index(:contracts, [:commodity, :status])
  end
end
