defmodule Simulator.Agents.BodyAgent.BiomeProfiles do
  @moduledoc """
  Maps a body's biome to its renewable production profile.

  Production profiles describe the commodities a body produces organically
  per production tick (food from terrestrial ecosystems, gas from gas
  giants, etc.) — the values are base rates before pop scaling and the
  production-tick interval multiplier. Rates tuned so a healthy
  terrestrial planet with a few thousand pops easily covers local food
  demand without overwhelming the manufactured-goods economy.

  Biomes that produce nothing renewable (asteroids, molten worlds, lifeless
  moons) return `%{}` — those bodies only yield commodities through mining
  extraction, which depletes their richness.
  """

  @type profile :: %{atom() => float()}

  @doc """
  Returns the renewable production profile for a biome.

  Unknown biomes return `%{}`.
  """
  @spec production_profile(atom() | nil) :: profile()
  def production_profile(:terrestrial),
    do: %{food: 3.0, water: 1.5, polymers: 0.2}

  def production_profile(:ocean),
    do: %{water: 4.0, food: 1.0}

  def production_profile(:desert),
    do: %{food: 0.1, water: 0.3}

  def production_profile(:ice),
    do: %{ice: 2.0, water: 1.0}

  def production_profile(:gas_giant),
    do: %{gas: 3.0, fuel: 0.5}

  def production_profile(:industrial),
    do: %{food: 0.5, polymers: 0.5}

  def production_profile(:molten), do: %{}
  def production_profile(:asteroid), do: %{}
  def production_profile(:lifeless), do: %{}
  def production_profile(_), do: %{}

  @doc """
  Returns the list of known biome atoms. Useful for tests and validation.
  """
  @spec known_biomes() :: [atom()]
  def known_biomes do
    [
      :terrestrial,
      :ocean,
      :desert,
      :ice,
      :gas_giant,
      :industrial,
      :molten,
      :asteroid,
      :lifeless
    ]
  end
end
