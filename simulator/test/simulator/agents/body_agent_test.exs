defmodule Simulator.Agents.BodyAgentTest do
  use Simulator.SimulationCase, async: false

  alias Simulator.Agents.{BodyAgent, MarketAgent}

  @production_interval 5 * Simulator.Simulation.Config.tick_multiplier()

  defp start_market(id, facility_id, overrides \\ %{}) do
    config =
      Map.merge(
        %{
          id: id,
          facility_id: facility_id,
          prices: %{food: 10.0, water: 5.0, ore: 40.0, ice: 8.0},
          supply: %{food: 100, water: 100, ore: 100, ice: 100},
          demand: %{},
          production: %{},
          consumption: %{}
        },
        overrides
      )

    {:ok, pid} =
      DynamicSupervisor.start_child(Simulator.AgentSupervisor, {MarketAgent, config})

    pid
  end

  defp start_body(overrides) do
    config =
      Map.merge(
        %{
          id: "body-earth",
          body_id: "earth",
          name: "Earth",
          biome: "terrestrial",
          resources: %{ore: 0.5, ice: 0.3},
          locations: ["earth-station"]
        },
        overrides
      )

    {:ok, pid} =
      DynamicSupervisor.start_child(Simulator.AgentSupervisor, {BodyAgent, config})

    pid
  end

  defp send_tick(pid, tick) do
    send(pid, {:tick, tick})
    :sys.get_state(pid)
  end

  describe "initialization" do
    test "normalizes the biome atom from the JSON string" do
      pid = start_body(%{biome: "terrestrial"})
      state = BodyAgent.get_state(pid)
      assert state.biome == :terrestrial
    end

    test "seeds current resources from the input map" do
      pid = start_body(%{resources: %{"ore" => 0.6, "ice" => 0.4}})
      resources = BodyAgent.get_resources(pid)
      assert resources.ore == 0.6
      assert resources.ice == 0.4
    end

    test "unknown biomes fall back to nil (no production)" do
      pid = start_body(%{biome: "crystal_lattice"})
      state = BodyAgent.get_state(pid)
      assert state.biome == nil
    end
  end

  describe "production" do
    test "terrestrial body pushes food to co-located market on production ticks" do
      market = start_market("market-earth-station", "earth-station")
      body = start_body(%{locations: ["earth-station"]})

      send_tick(body, @production_interval)

      supply = MarketAgent.get_supply(market)
      assert supply.food > 100
    end

    test "asteroid biome produces nothing renewable (mining-only)" do
      market = start_market("market-asteroid-1", "asteroid-1")

      body =
        start_body(%{
          id: "body-asteroid",
          body_id: "asteroid",
          biome: "asteroid",
          resources: %{ore: 0.9},
          locations: ["asteroid-1"]
        })

      send_tick(body, @production_interval)

      supply = MarketAgent.get_supply(market)
      # No food/water from asteroid.
      assert Map.get(supply, :food, 0) == 100
      assert Map.get(supply, :water, 0) == 100
    end
  end

  describe "extraction" do
    test "extract/3 depletes body richness and returns actual amount" do
      pid = start_body(%{resources: %{ore: 1.0}})

      actual = BodyAgent.extract(pid, :ore, 50)
      assert actual > 0

      resources = BodyAgent.get_resources(pid)
      assert resources.ore < 1.0
    end

    test "extract/3 returns 0 when the resource is already depleted" do
      pid = start_body(%{resources: %{ore: 0.0}})

      assert BodyAgent.extract(pid, :ore, 50) == 0
    end

    test "extract/3 returns 0 for missing commodities" do
      pid = start_body(%{resources: %{ore: 0.5}})

      assert BodyAgent.extract(pid, :platinum, 50) == 0
    end
  end

  describe "regeneration" do
    test "depleted resources regen toward seed value over production ticks" do
      pid = start_body(%{resources: %{ore: 0.5}})

      # Deplete aggressively first.
      for _ <- 1..20, do: BodyAgent.extract(pid, :ore, 50)

      depleted = BodyAgent.get_resources(pid).ore

      # Let regen run across several production cycles.
      for n <- 1..10 do
        send_tick(pid, n * @production_interval)
      end

      recovered = BodyAgent.get_resources(pid).ore
      assert recovered > depleted
      assert recovered <= 0.5
    end
  end

  describe "food_availability_multiplier/1" do
    test "returns neutral (1.0) when the body has no food history" do
      pid = start_body(%{biome: "asteroid"})
      assert BodyAgent.food_availability_multiplier(pid) == 1.0
    end

    test "clamps to the conservative band after sustained production" do
      start_market("market-earth-station", "earth-station")
      pid = start_body(%{biome: "terrestrial", locations: ["earth-station"]})

      for n <- 1..5 do
        send_tick(pid, n * @production_interval)
      end

      mult = BodyAgent.food_availability_multiplier(pid)
      assert mult >= 0.5
      assert mult <= 2.0
    end
  end
end
