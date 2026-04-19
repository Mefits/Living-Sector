defmodule Simulator.Agents.ShipAgent.CrewMissionTest do
  use ExUnit.Case, async: true

  alias Simulator.AI.{Considerations, Utility}
  alias Simulator.Agents.{CrewComplement, ShipAgent.Goals}

  describe "CrewComplement.grant_skill_xp/3" do
    test "adds to an existing skill and caps at 100" do
      crew = CrewComplement.new([:pilot, :engineer])
      eng_before = crew.skills.engineering

      {:ok, _} =
        {:ok,
         CrewComplement.grant_skill_xp(crew, :engineering, 5)
         |> then(fn updated ->
           assert updated.skills.engineering == eng_before + 5
           updated
         end)}

      capped = CrewComplement.grant_skill_xp(crew, :engineering, 9999)
      assert capped.skills.engineering == 100
    end

    test "leaves unrelated skills untouched" do
      crew = CrewComplement.new([:pilot, :engineer])
      other_before = crew.skills.combat

      updated = CrewComplement.grant_skill_xp(crew, :engineering, 3)
      assert updated.skills.combat == other_before
    end

    test "ignores unknown skill atoms (no crash, no side effect)" do
      crew = CrewComplement.new([:pilot])
      unchanged = CrewComplement.grant_skill_xp(crew, :archery, 5)
      assert unchanged.skills == crew.skills
    end
  end

  describe "crew_mission_opportunity consideration" do
    test "returns 0 when no crew_mission contracts are posted" do
      state = %{
        available_contracts: [
          %{contract_type: "delivery", payment: 500, duration_ticks: 10, required_skill: "combat"}
        ],
        crew: %{skills: %{combat: 40}}
      }

      {value, :profit} = Considerations.crew_mission_opportunity(state)
      assert value == 0.0
    end

    test "scores well for a high-payment mission matching crew skill" do
      state = %{
        available_contracts: [mission(payment: 3000, duration: 20, skill: "engineering")],
        crew: %{skills: %{engineering: 60}}
      }

      {low_skill, :profit} =
        Considerations.crew_mission_opportunity(%{state | crew: %{skills: %{engineering: 10}}})

      {high_skill, :profit} = Considerations.crew_mission_opportunity(state)

      assert high_skill > low_skill
    end

    test "picks the best-available mission across multiple postings" do
      state = %{
        available_contracts: [
          mission(payment: 500, duration: 30, skill: "combat"),
          mission(payment: 3000, duration: 30, skill: "combat")
        ],
        crew: %{skills: %{combat: 50}}
      }

      {value, :profit} = Considerations.crew_mission_opportunity(state)
      assert value > 0.0
    end
  end

  describe "crew_mission_fit consideration" do
    test "is 0 with no missions posted" do
      state = %{available_contracts: [], crew: %{skills: %{}}}
      {value, :loyalty} = Considerations.crew_mission_fit(state)
      assert value == 0.0
    end

    test "averages skill_fit across the available missions" do
      state = %{
        available_contracts: [
          mission(payment: 1000, duration: 20, skill: "combat"),
          mission(payment: 1000, duration: 20, skill: "engineering")
        ],
        crew: %{skills: %{combat: 50, engineering: 25}}
      }

      {value, :loyalty} = Considerations.crew_mission_fit(state)
      # combat: 50/50 = 1.0, engineering: 25/50 = 0.5 → avg 0.75
      assert_in_delta value, 0.75, 0.01
    end
  end

  describe "goal selection" do
    test ":do_crew_mission is in available_actions" do
      actions = Goals.available_actions()
      assert Enum.any?(actions, fn {name, _} -> name == :do_crew_mission end)
    end

    test "a crew with good engineering picks crew_mission over idle" do
      state = %{
        available_contracts: [mission(payment: 2000, duration: 25, skill: "engineering")],
        crew: %{skills: %{engineering: 60}, morale: 70},
        cargo: %{},
        cargo_capacity: 500,
        passenger_capacity: 0,
        passengers: 0,
        faction_id: "independent",
        fuel: 80.0,
        fuel_capacity: 100.0,
        fuel_consumption_rate: 0.05,
        credits: 2000,
        memory: %{known_prices: %{}, visited: []}
      }

      considerations = Goals.evaluate_considerations(state)

      scored =
        Utility.rank_actions(
          Goals.available_actions(),
          considerations,
          Simulator.AI.Personality.balanced_trader()
        )

      top = scored |> Enum.take(3) |> Enum.map(&elem(&1, 0))
      assert :do_crew_mission in top
    end
  end

  defp mission(opts) do
    %{
      contract_type: "crew_mission",
      source_location: "earth-station",
      destination_location: "earth-station",
      mission_category: "test",
      payment: Keyword.get(opts, :payment, 1000),
      duration_ticks: Keyword.get(opts, :duration, 20),
      required_skill: Keyword.get(opts, :skill, "engineering"),
      skill_gain: 2,
      faction_id: Keyword.get(opts, :faction, "independent")
    }
  end
end
