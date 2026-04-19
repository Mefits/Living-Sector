defmodule Simulator.PersistenceManagerTest do
  use Simulator.SimulationCase, async: false
  use Simulator.DataCase, async: false

  alias Simulator.{PersistenceManager, Repo}
  alias Simulator.Schemas.{StarSystem, CelestialBody, Location, Facility, Market}

  defp seed_market! do
    {:ok, system} = Repo.insert(StarSystem.changeset(%StarSystem{}, %{name: "Sol"}))

    {:ok, body} =
      Repo.insert(
        CelestialBody.changeset(%CelestialBody{}, %{
          body_id: "earth-#{System.unique_integer([:positive])}",
          name: "Earth",
          type: "planet",
          orbit_radius: 1.0,
          orbit_period: 365,
          star_system_id: system.id
        })
      )

    {:ok, location} =
      Repo.insert(
        Location.changeset(%Location{}, %{
          name: "Earth Orbit",
          type: "planet",
          celestial_body_id: body.id
        })
      )

    {:ok, facility} =
      Repo.insert(
        Facility.changeset(%Facility{}, %{
          name: "Earth Station",
          type: "station",
          location_id: location.id
        })
      )

    {:ok, market} =
      Repo.insert(
        Market.changeset(%Market{}, %{
          facility_id: facility.id,
          prices: %{"ore" => 40.0, "fuel" => 25.0, "food" => 15.0},
          supply: %{"ore" => 500, "fuel" => 500, "food" => 500},
          demand: %{"ore" => 20, "fuel" => 50, "food" => 100},
          production: %{"ore" => 0, "fuel" => 30, "food" => 80}
        })
      )

    market
  end

  describe "mark_dirty/3 and flush/0" do
    test "flushes dirty entries to the database" do
      market = seed_market!()

      PersistenceManager.mark_dirty(:market, market.id, fn ->
        Repo.get!(Market, market.id)
        |> Market.changeset(%{prices: %{"ore" => 99.0, "fuel" => 25.0, "food" => 15.0}})
        |> Repo.update!()
      end)

      PersistenceManager.flush()

      updated = Repo.get!(Market, market.id)
      assert updated.prices["ore"] == 99.0
    end

    test "deduplicates — only latest persist_fn is called" do
      market = seed_market!()

      # First mark — sets ore to 50
      PersistenceManager.mark_dirty(:market, market.id, fn ->
        Repo.get!(Market, market.id)
        |> Market.changeset(%{prices: %{"ore" => 50.0, "fuel" => 25.0, "food" => 15.0}})
        |> Repo.update!()
      end)

      # Second mark — sets ore to 77 (should overwrite first)
      PersistenceManager.mark_dirty(:market, market.id, fn ->
        Repo.get!(Market, market.id)
        |> Market.changeset(%{prices: %{"ore" => 77.0, "fuel" => 25.0, "food" => 15.0}})
        |> Repo.update!()
      end)

      PersistenceManager.flush()

      updated = Repo.get!(Market, market.id)
      assert updated.prices["ore"] == 77.0
    end
  end

  describe "persist_now/1" do
    test "writes immediately without waiting for sweep" do
      market = seed_market!()

      PersistenceManager.persist_now(fn ->
        Repo.get!(Market, market.id)
        |> Market.changeset(%{prices: %{"ore" => 55.0, "fuel" => 25.0, "food" => 15.0}})
        |> Repo.update!()
      end)

      updated = Repo.get!(Market, market.id)
      assert updated.prices["ore"] == 55.0
    end
  end

  describe "MarketAgent persistence integration" do
    test "market agent persists state via mark_dirty after tick" do
      market = seed_market!()

      {:ok, pid} =
        DynamicSupervisor.start_child(
          Simulator.AgentSupervisor,
          {Simulator.Agents.MarketAgent,
           %{
             id: "market-persist-test",
             facility_id: "earth-station",
             db_id: market.id,
             supply: %{ore: 500, fuel: 500, food: 50},
             demand: %{ore: 20, fuel: 50, food: 200},
             prices: %{ore: 40.0, fuel: 25.0, food: 15.0}
           }}
        )

      # Advance a tick — this triggers mark_dirty
      send(pid, {:tick, 1})
      :sys.get_state(pid)

      # Flush the persistence manager
      PersistenceManager.flush()

      # Verify the DB was updated
      updated = Repo.get!(Market, market.id)
      # Food price should have risen (demand >> supply)
      assert updated.prices["food"] > 15.0
    end
  end
end
