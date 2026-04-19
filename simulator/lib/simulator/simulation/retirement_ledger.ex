defmodule Simulator.Simulation.RetirementLedger do
  @moduledoc """
  Tracks decommissioned ships for historical analysis.

  When a ship gets recycled after bankruptcy, its final state is
  recorded in both ETS (fast reads for dashboard) and Postgres
  (survives restarts). On startup, ETS is hydrated from the DB.
  """

  alias Simulator.Schemas.ShipRetirement

  @ets_table :retirement_ledger

  @doc """
  Initializes the ETS table and loads existing records from DB.
  """
  @spec init() :: :ok
  def init do
    if :ets.whereis(@ets_table) == :undefined do
      :ets.new(@ets_table, [:named_table, :bag, :public, read_concurrency: true])
    end

    # Hydrate ETS from DB
    load_from_db()

    :ok
  end

  @doc """
  Records a ship's retirement to both ETS and DB.
  """
  @spec record(map()) :: :ok
  def record(entry) do
    :ets.insert(@ets_table, {entry.tick, entry})

    # Persist to DB asynchronously (don't block the agent)
    Task.start(fn ->
      %ShipRetirement{}
      |> ShipRetirement.changeset(%{
        ship_id: to_string(entry.ship_id),
        name: to_string(entry.name),
        class: to_string(entry[:class]),
        faction_id: to_string(entry[:faction_id]),
        final_location: entry[:final_location] && to_string(entry.final_location),
        new_location: entry[:new_location] && to_string(entry.new_location),
        final_credits: entry[:final_credits] || 0,
        cargo_value: entry[:cargo_value] || 0,
        crew_size: entry[:crew_size] || 0,
        crew_morale: entry[:crew_morale] || 0,
        tick: entry.tick,
        reason: to_string(entry[:reason] || "bankruptcy")
      })
      |> Simulator.Repo.insert()
    end)

    :ok
  end

  @doc """
  Returns all retired ships, most recent first.
  """
  @spec all() :: [map()]
  def all do
    :ets.tab2list(@ets_table)
    |> Enum.map(&elem(&1, 1))
    |> Enum.sort_by(& &1.tick, :desc)
  end

  @doc """
  Returns the count of retirements.
  """
  @spec count() :: non_neg_integer()
  def count do
    :ets.info(@ets_table, :size) || 0
  end

  # Load all retirement records from DB into ETS
  defp load_from_db do
    Simulator.Repo.all(ShipRetirement)
    |> Enum.each(fn r ->
      entry = %{
        ship_id: r.ship_id,
        name: r.name,
        class: String.to_atom(r.class || "freighter"),
        faction_id: r.faction_id,
        final_location: r.final_location,
        new_location: r.new_location,
        final_credits: r.final_credits,
        cargo_value: r.cargo_value,
        crew_size: r.crew_size,
        crew_morale: r.crew_morale,
        tick: r.tick,
        reason: String.to_atom(r.reason || "bankruptcy")
      }

      :ets.insert(@ets_table, {r.tick, entry})
    end)
  rescue
    _ -> :ok
  end
end
