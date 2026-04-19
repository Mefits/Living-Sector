defmodule Simulator.Agents.CrewComplementPersistenceTest do
  use ExUnit.Case, async: true

  alias Simulator.Agents.CrewComplement

  describe "serialize/1 + deserialize/2 round-trip" do
    test "a fresh crew round-trips without drift" do
      original = CrewComplement.new([:pilot, :engineer, :trader])
      json_safe = CrewComplement.serialize(original)
      restored = CrewComplement.deserialize(json_safe, original.roles)

      assert restored.size == original.size
      assert restored.roles == original.roles
      assert restored.skills == original.skills
      assert restored.hunger == original.hunger
      assert restored.fatigue == original.fatigue
      assert restored.morale == original.morale
      assert restored.health == original.health
      assert restored.credits == original.credits
      assert restored.current_task == original.current_task
      assert restored.personality == original.personality
    end

    test "preserves skill XP earned from crew missions" do
      crew =
        CrewComplement.new([:pilot, :engineer])
        |> CrewComplement.grant_skill_xp(:engineering, 15)
        |> CrewComplement.grant_skill_xp(:combat, 7)

      assert crew.skills.engineering == 55
      assert crew.skills.combat == 27

      restored =
        crew
        |> CrewComplement.serialize()
        |> CrewComplement.deserialize([:pilot, :engineer])

      assert restored.skills.engineering == 55
      assert restored.skills.combat == 27
    end

    test "preserves morale/fatigue/hunger drift" do
      crew = %{
        CrewComplement.new([:pilot])
        | hunger: 42.5,
          fatigue: 77.0,
          morale: 33.3,
          health: 95.0
      }

      restored =
        crew
        |> CrewComplement.serialize()
        |> CrewComplement.deserialize([:pilot])

      assert restored.hunger == 42.5
      assert restored.fatigue == 77.0
      assert restored.morale == 33.3
      assert restored.health == 95.0
    end

    test "preserves current_task across restart" do
      for task <- [:piloting, :resting, :eating, :on_mission, :loading, :idle] do
        crew = %{CrewComplement.new([:pilot]) | current_task: task}
        restored = crew |> CrewComplement.serialize() |> CrewComplement.deserialize([:pilot])
        assert restored.current_task == task, "expected #{task} to round-trip"
      end
    end

    test "rebuilds a fresh crew when the blob is nil" do
      restored = CrewComplement.deserialize(nil, [:pilot, :engineer])

      assert restored.size == 2
      assert restored.roles == [:pilot, :engineer]
    end

    test "simulates a full JSONB round-trip via Jason" do
      crew =
        CrewComplement.new([:pilot, :engineer, :trader])
        |> CrewComplement.grant_skill_xp(:navigation, 20)

      # Go through JSON encode + decode the way SQLite's state column
      # actually stores it.
      roundtripped =
        crew
        |> CrewComplement.serialize()
        |> Jason.encode!()
        |> Jason.decode!()
        |> CrewComplement.deserialize(crew.roles)

      assert roundtripped.size == crew.size
      assert roundtripped.roles == crew.roles
      assert roundtripped.skills.navigation == crew.skills.navigation
    end
  end
end
