defmodule Simulator.Release do
  @moduledoc """
  Helpers for operations a packaged release needs to run on its own,
  without `mix`.

  A production release doesn't include Elixir's Mix build tool, so
  `mix ecto.migrate` isn't available at runtime. These helpers do the
  equivalent by reaching into Ecto's migrator and seed layer directly
  — callable from the release shell via `bin/simulator eval` or
  programmatically on first-boot from `Simulator.Application`.
  """

  @app :simulator

  @doc """
  Runs any pending migrations for every configured repo.

  Called automatically on first boot (see `Simulator.Application`) so
  a desktop bundle can bring up its own DB without the user touching
  mix.
  """
  @spec migrate() :: :ok
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    :ok
  end

  @doc """
  Rolls `repo` back to migration version `version`. Exposed mostly so
  the release shell has an escape hatch if a migration misbehaves.
  """
  @spec rollback(module(), non_neg_integer()) :: any()
  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Seeds the world from JSON under `priv/data/`. Idempotent — the
  seed path uses upserts — so repeated calls don't duplicate rows.
  """
  @spec seed() :: :ok
  def seed do
    load_app()
    Simulator.Seed.seed_all()
    :ok
  end

  @doc """
  Returns true when the DB has at least one star system. Used by the
  first-boot hook to decide whether to seed.
  """
  @spec seeded?() :: boolean()
  def seeded? do
    load_app()

    try do
      Simulator.Repo.aggregate(Simulator.Schemas.StarSystem, :count) > 0
    rescue
      _ -> false
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
