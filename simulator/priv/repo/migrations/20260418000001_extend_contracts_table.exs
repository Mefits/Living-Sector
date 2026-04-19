defmodule Simulator.Repo.Migrations.ExtendContractsTable do
  use Ecto.Migration

  # Adds all the fields ContractLifecycle sets on the ETS contract
  # struct that weren't in the original schema. Required so
  # Repo.all(Contract) on boot reconstructs the full ETS map.
  #
  # `contract_id` is a unique string key matching the ETS id
  # ("contract-N") — the DB still has an integer PK, we just use
  # this column for the key round-trip.
  def change do
    alter table(:contracts) do
      add :contract_id, :string
      add :faction_id, :string
      add :min_reputation, :integer
      add :faction_bonus, :float
      add :delivery_fee, :integer
      add :cargo_deposit, :integer
      add :cargo_value, :integer
      add :reserve_id, :string
      add :picked_up_at_tick, :integer
      add :delivered_at_tick, :integer
      add :passenger_count, :integer
    end

    create unique_index(:contracts, [:contract_id])
  end
end
