defmodule Simulator.Economy.MissionCatalogTest do
  use ExUnit.Case, async: true

  alias Simulator.Economy.MissionCatalog

  describe "all/0" do
    test "every template has the expected keys" do
      for template <- MissionCatalog.all() do
        assert is_atom(template.category)
        assert is_binary(template.display_name)
        assert is_list(template.posted_by)
        assert Enum.all?(template.posted_by, &is_atom/1)
        assert template.duration_ticks > 0
        assert template.base_payment > 0
        assert is_atom(template.required_skill)
        assert template.skill_gain in 1..5
      end
    end
  end

  describe "for_facility_type/1" do
    test "returns only templates that list the type in posted_by" do
      for template <- MissionCatalog.for_facility_type(:station) do
        assert :station in template.posted_by
      end
    end

    test "every supported facility type has at least one mission" do
      for type <- MissionCatalog.supported_facility_types() do
        missions = MissionCatalog.for_facility_type(type)
        refute missions == [], "no missions for facility type #{inspect(type)}"
      end
    end

    test "accepts string facility types (for round-tripped data)" do
      atom_missions = MissionCatalog.for_facility_type(:station)
      string_missions = MissionCatalog.for_facility_type("station")
      assert length(atom_missions) == length(string_missions)
    end

    test "unknown types return []" do
      assert MissionCatalog.for_facility_type(:unknown_type) == []
      assert MissionCatalog.for_facility_type("nonexistent") == []
      assert MissionCatalog.for_facility_type(nil) == []
    end
  end

  describe "get/1" do
    test "finds a known category by atom and by string" do
      assert %{category: :security_detail} = MissionCatalog.get(:security_detail)
      assert %{category: :security_detail} = MissionCatalog.get("security_detail")
    end

    test "returns nil for unknown categories" do
      assert MissionCatalog.get(:nope) == nil
      assert MissionCatalog.get("never-heard-of-it") == nil
      assert MissionCatalog.get(nil) == nil
    end
  end
end
