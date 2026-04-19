defmodule Simulator.Agents.BodyAgent.BiomeProfilesTest do
  use ExUnit.Case, async: true

  alias Simulator.Agents.BodyAgent.BiomeProfiles

  describe "production_profile/1" do
    test "terrestrial produces food, water, polymers" do
      profile = BiomeProfiles.production_profile(:terrestrial)
      assert profile.food > 0
      assert profile.water > 0
      assert profile.polymers > 0
    end

    test "gas_giant produces gas and fuel" do
      profile = BiomeProfiles.production_profile(:gas_giant)
      assert profile.gas > 0
      assert profile.fuel > 0
    end

    test "ice biome produces ice and water" do
      profile = BiomeProfiles.production_profile(:ice)
      assert profile.ice > 0
      assert profile.water > 0
    end

    test "asteroid, molten, lifeless produce nothing renewable" do
      assert BiomeProfiles.production_profile(:asteroid) == %{}
      assert BiomeProfiles.production_profile(:molten) == %{}
      assert BiomeProfiles.production_profile(:lifeless) == %{}
    end

    test "unknown biomes fall back to empty profile" do
      assert BiomeProfiles.production_profile(:starfish) == %{}
      assert BiomeProfiles.production_profile(nil) == %{}
    end
  end

  describe "known_biomes/0" do
    test "every known biome has a defined production profile" do
      for biome <- BiomeProfiles.known_biomes() do
        profile = BiomeProfiles.production_profile(biome)
        assert is_map(profile), "biome #{inspect(biome)} returned non-map profile"
      end
    end
  end
end
