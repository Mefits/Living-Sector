defmodule Simulator.AdminTest do
  use Simulator.SimulationCase, async: false
  use Simulator.DataCase, async: false

  alias Simulator.Admin
  alias Simulator.Repo
  alias Simulator.Schemas.{CelestialBody, Facility, Location, StarSystem}

  # Minimal in-memory world fixture. We don't seed the full JSON —
  # just enough for the admin paths to resolve a system/body/location
  # and look up class stats. Returns the body_id string so tests that
  # create facilities can pass it through Admin.create_facility/1.
  defp fixture_world do
    {:ok, system} =
      Repo.insert(StarSystem.changeset(%StarSystem{}, %{name: "Sol"}))

    body_id = "earth-#{System.unique_integer([:positive])}"

    {:ok, body} =
      Repo.insert(
        CelestialBody.changeset(%CelestialBody{}, %{
          body_id: body_id,
          name: "Earth",
          type: "planet",
          orbit_radius: 1.0,
          orbit_period: 365,
          star_system_id: system.id
        })
      )

    {:ok, location} =
      Repo.insert(
        Ecto.Changeset.change(%Location{}, %{
          name: "earth-station",
          type: "station",
          celestial_body_id: body.id
        })
      )

    %{system: system, body: body, body_id: body_id, location: location}
  end

  describe "create_ship/1" do
    test "inserts a ship, spawns the agent, and returns the derived id" do
      fixture_world()

      {:ok, ship} =
        Admin.create_ship(%{
          "name" => "Test Void",
          "class" => "courier",
          "faction_id" => "independent",
          "location" => "earth-station",
          "credits" => 7_500
        })

      assert ship.id == "ship-test-void"
      assert ship.class == :courier
      assert {:ok, _pid} = Simulator.Agents.Agent.whereis(ship.id)
    end

    test "suffixes the id on collision" do
      fixture_world()

      {:ok, first} =
        Admin.create_ship(%{
          "name" => "Void Star",
          "class" => "courier",
          "faction_id" => "independent",
          "location" => "earth-station"
        })

      {:ok, second} =
        Admin.create_ship(%{
          "name" => "Void Star",
          "class" => "courier",
          "faction_id" => "independent",
          "location" => "earth-station"
        })

      assert first.id == "ship-void-star"
      assert second.id == "ship-void-star-2"
    end

    test "errors on missing required params" do
      fixture_world()

      assert {:error, {:missing_param, "name"}} =
               Admin.create_ship(%{
                 "class" => "courier",
                 "faction_id" => "independent",
                 "location" => "earth-station"
               })
    end

    test "errors on unknown ship class" do
      fixture_world()

      assert {:error, {:unknown_ship_class, "warpcruiser"}} =
               Admin.create_ship(%{
                 "name" => "Whatever",
                 "class" => "warpcruiser",
                 "faction_id" => "independent",
                 "location" => "earth-station"
               })
    end

    test "errors on unknown location" do
      fixture_world()

      assert {:error, {:unknown_location, "atlantis"}} =
               Admin.create_ship(%{
                 "name" => "Lost",
                 "class" => "courier",
                 "faction_id" => "independent",
                 "location" => "atlantis"
               })
    end
  end

  describe "destroy_ship/1" do
    test "terminates the agent and removes the DB row" do
      fixture_world()

      {:ok, ship} =
        Admin.create_ship(%{
          "name" => "Doomed",
          "class" => "courier",
          "faction_id" => "independent",
          "location" => "earth-station"
        })

      assert {:ok, _pid} = Simulator.Agents.Agent.whereis(ship.id)
      assert :ok = Admin.destroy_ship(ship.id)
      assert :error = Simulator.Agents.Agent.whereis(ship.id)
    end

    test "returns :not_found for unknown ship" do
      assert {:error, :not_found} = Admin.destroy_ship("ship-ghost")
    end
  end

  describe "adjust_supply/3" do
    test "applies a positive delta to market supply" do
      # Spawn a fresh market agent for this test. Seed-less.
      {:ok, _pid} =
        DynamicSupervisor.start_child(
          Simulator.AgentSupervisor,
          {Simulator.Agents.MarketAgent,
           %{
             id: "market-admin-test",
             facility_id: "admin-test",
             supply: %{fuel: 100},
             demand: %{},
             production: %{},
             consumption: %{}
           }}
        )

      assert :ok = Admin.adjust_supply("admin-test", "fuel", 50)

      {:ok, pid} = Simulator.Agents.Agent.whereis("market-admin-test")
      # Flush the cast via a sync call.
      state = Simulator.Agents.MarketAgent.get_state(pid)
      assert state.supply.fuel == 150
    end

    test "negative delta floors at 0" do
      {:ok, _pid} =
        DynamicSupervisor.start_child(
          Simulator.AgentSupervisor,
          {Simulator.Agents.MarketAgent,
           %{
             id: "market-admin-floor",
             facility_id: "admin-floor",
             supply: %{fuel: 30},
             demand: %{},
             production: %{},
             consumption: %{}
           }}
        )

      assert :ok = Admin.adjust_supply("admin-floor", "fuel", -500)

      {:ok, pid} = Simulator.Agents.Agent.whereis("market-admin-floor")
      state = Simulator.Agents.MarketAgent.get_state(pid)
      assert state.supply.fuel == 0
    end

    test "returns :not_found when market doesn't exist" do
      assert {:error, :not_found} = Admin.adjust_supply("nowhere", "fuel", 100)
    end
  end

  describe "create_facility/1 + destroy_facility/1" do
    test "creates facility + market and spawns both agents" do
      %{body_id: body_id} = fixture_world()

      {:ok, result} =
        Admin.create_facility(%{
          "name" => "Test Outpost",
          "type" => "station",
          "faction_id" => "independent",
          "body_id" => body_id,
          "location_name" => "test-outpost",
          "credits" => 15_000
        })

      assert result.facility_id == "facility-test-outpost"
      assert result.market_id == "market-test-outpost"
      assert {:ok, _} = Simulator.Agents.Agent.whereis(result.facility_id)
      assert {:ok, _} = Simulator.Agents.Agent.whereis(result.market_id)
      assert Repo.get_by(Location, name: "test-outpost") != nil
    end

    test "suffixes the location name on collision" do
      %{body_id: body_id} = fixture_world()

      {:ok, a} =
        Admin.create_facility(%{
          "name" => "Clash",
          "type" => "outpost",
          "faction_id" => "independent",
          "body_id" => body_id,
          "location_name" => "clash-point"
        })

      {:ok, b} =
        Admin.create_facility(%{
          "name" => "Clash",
          "type" => "outpost",
          "faction_id" => "independent",
          "body_id" => body_id,
          "location_name" => "clash-point"
        })

      assert a.location == "clash-point"
      assert b.location == "clash-point-2"
    end

    test "destroy_facility terminates agents and removes DB row" do
      %{body_id: body_id} = fixture_world()

      {:ok, result} =
        Admin.create_facility(%{
          "name" => "Short Lived",
          "type" => "outpost",
          "faction_id" => "independent",
          "body_id" => body_id,
          "location_name" => "short-lived"
        })

      assert :ok = Admin.destroy_facility(result.facility_id)
      assert :error = Simulator.Agents.Agent.whereis(result.facility_id)
      assert :error = Simulator.Agents.Agent.whereis(result.market_id)
      assert Repo.get_by(Facility, name: "Short Lived") == nil
    end
  end
end
