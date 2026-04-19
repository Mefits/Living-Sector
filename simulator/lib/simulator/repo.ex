defmodule Simulator.Repo do
  @moduledoc """
  Ecto repository backed by SQLite.

  All simulation state (agents, markets, trades, world data) is persisted
  here. Agents load state from the DB on startup and write back on
  meaningful events, batched through `Simulator.PersistenceManager` so
  writes flow through a single `Repo.transaction` every few seconds —
  which matches SQLite's single-writer model well.

  SQLite keeps the sim self-contained: no external service, no Docker,
  the DB is one file under `priv/`. That's also what makes a desktop
  bundle (Godot + Elixir release) feasible.
  """

  use Ecto.Repo,
    otp_app: :simulator,
    adapter: Ecto.Adapters.SQLite3
end
