defmodule Simulator.Agents.PopAgentPersistenceTest do
  use Simulator.SimulationCase, async: false
  use Simulator.DataCase, async: false

  alias Simulator.Agents.PopAgent
  alias Simulator.Repo
  alias Simulator.Schemas.{CelestialBody, Facility, Location, Population, StarSystem}

  defp fixture_pop(overrides \\ %{}) do
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
          name: "earth-station-#{System.unique_integer([:positive])}",
          type: "station",
          celestial_body_id: body.id
        })
      )

    {:ok, facility} =
      Repo.insert(
        Ecto.Changeset.change(%Facility{}, %{
          name: "Earth Station",
          type: "station",
          faction_id: "independent",
          location_id: location.id,
          body_id: body_id,
          credits: 10_000,
          condition: 1.0,
          reputation: 50
        })
      )

    {:ok, pop} =
      Repo.insert(
        Population.changeset(%Population{}, %{
          label: "Test Workers",
          demographic: "workers",
          facility_id: facility.id,
          population_count: 10_000,
          overall_sentiment: 65,
          unrest: 10,
          total_wealth: 500_000,
          food_satisfaction: 70
        })
      )

    state = %{
      id: "pop-test-workers",
      label: "Test Workers",
      location: location.name,
      facility_id: location.name,
      demographic: :workers,
      population_count: overrides[:population_count] || 10_000,
      growth_rate: 0.001,
      food_satisfaction: overrides[:food_satisfaction] || 70.0,
      safety_satisfaction: overrides[:safety_satisfaction] || 80,
      entertainment_satisfaction: overrides[:entertainment_satisfaction] || 50,
      total_wealth: overrides[:total_wealth] || 500_000,
      spending_rate: 0.02,
      labor_output: overrides[:labor_output] || 0,
      employed_fraction: 0.85,
      overall_sentiment: overrides[:overall_sentiment] || 65.0,
      unrest: overrides[:unrest] || 10.0,
      migration_pressure: overrides[:migration_pressure] || 0.0,
      body_food_multiplier: overrides[:body_food_multiplier] || 1.0,
      consumption: %{food: 50},
      production_commodity: nil,
      production_amount: 0,
      __db_id__: pop.id,
      __agent_type__: :population
    }

    %{pop: pop, state: state}
  end

  describe "persist_state/1" do
    test "writes top-level columns + state JSONB to DB" do
      %{pop: pop, state: state} =
        fixture_pop(%{
          population_count: 12_345,
          overall_sentiment: 47.3,
          unrest: 33.7,
          total_wealth: 640_000,
          food_satisfaction: 58.5,
          migration_pressure: 0.25,
          body_food_multiplier: 1.4,
          labor_output: 88
        })

      :ok = PopAgent.persist_state(state)

      reloaded = Repo.get!(Population, pop.id)

      assert reloaded.population_count == 12_345
      assert reloaded.overall_sentiment == 47
      assert reloaded.unrest == 34
      assert reloaded.total_wealth == 640_000
      assert reloaded.food_satisfaction == 59

      assert reloaded.state["migration_pressure"] == 0.25
      assert reloaded.state["body_food_multiplier"] == 1.4
      assert reloaded.state["labor_output"] == 88
    end

    test "is a no-op when __db_id__ is nil" do
      %{state: state} = fixture_pop()
      state = %{state | __db_id__: nil}

      assert :ok = PopAgent.persist_state(state)
    end
  end

  describe "round-trip via spawner-style config" do
    test "spawns an agent from a persisted pop and preserves live state" do
      %{pop: pop, state: state} =
        fixture_pop(%{
          population_count: 9_999,
          overall_sentiment: 22.0,
          unrest: 65.0,
          total_wealth: 120_000,
          food_satisfaction: 18.5,
          migration_pressure: 0.75,
          body_food_multiplier: 0.6
        })

      :ok = PopAgent.persist_state(state)

      # Simulate the spawner flow: reload the DB row, build a config map
      # the same way spawn_all_populations/0 does, and start the agent.
      reloaded = Repo.get!(Population, pop.id)
      saved_state = reloaded.state || %{}

      config = %{
        id: "pop-test-restored-#{System.unique_integer([:positive])}",
        db_id: reloaded.id,
        label: reloaded.label,
        facility_id: "earth-station",
        demographic: :workers,
        population_count: reloaded.population_count,
        overall_sentiment: reloaded.overall_sentiment,
        unrest: reloaded.unrest,
        food_satisfaction: reloaded.food_satisfaction,
        total_wealth: reloaded.total_wealth,
        consumption: %{food: 50},
        migration_pressure: saved_state["migration_pressure"] || 0.0,
        safety_satisfaction: saved_state["safety_satisfaction"] || 80,
        entertainment_satisfaction: saved_state["entertainment_satisfaction"] || 50,
        labor_output: saved_state["labor_output"] || 0,
        body_food_multiplier: saved_state["body_food_multiplier"] || 1.0
      }

      {:ok, pid} =
        DynamicSupervisor.start_child(Simulator.AgentSupervisor, {PopAgent, config})

      restored = PopAgent.get_state(pid)

      assert restored.population_count == 9_999
      assert restored.overall_sentiment == 22
      assert restored.unrest == 65
      assert restored.total_wealth == 120_000
      assert restored.food_satisfaction == 19
      assert restored.migration_pressure == 0.75
      assert restored.body_food_multiplier == 0.6
    end
  end
end
