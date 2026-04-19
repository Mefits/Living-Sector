defmodule Simulator.Economy.Commodities do
  @moduledoc """
  Defines the resource types available in the simulation.

  Commodities are organized into tiers reflecting a production supply chain.
  Raw materials are extracted, refined into intermediate goods, then
  manufactured into end products.

  ## Tiers

    * `:raw` — mined/extracted from celestial bodies (ore, ice, gas)
    * `:refined` — processed from raw materials (metals, fuel, polymers, water)
    * `:manufactured` — assembled from refined goods (components, electronics, tools)
    * `:consumer` — end products for populations and crew (food, medical, luxury)

  Base prices increase with tier — refined goods cost more than raw,
  manufactured more than refined. This creates profit margins at each
  step of the supply chain.
  """

  @type tier :: :raw | :refined | :manufactured | :consumer
  @type commodity ::
          :ore
          | :ice
          | :gas
          | :metals
          | :fuel
          | :polymers
          | :water
          | :components
          | :electronics
          | :tools
          | :food
          | :medical
          | :luxury

  @commodities_by_tier %{
    raw: [:ore, :ice, :gas],
    refined: [:metals, :fuel, :polymers, :water],
    manufactured: [:components, :electronics, :tools],
    consumer: [:food, :medical, :luxury]
  }

  @all_commodities Enum.flat_map(@commodities_by_tier, fn {_tier, commodities} -> commodities end)

  @commodity_tier for {tier, commodities} <- @commodities_by_tier,
                      commodity <- commodities,
                      into: %{},
                      do: {commodity, tier}

  @base_prices %{
    # Raw — cheap, abundant at source
    ore: 15.0,
    ice: 10.0,
    gas: 20.0,
    # Refined — moderate, require processing
    metals: 45.0,
    fuel: 25.0,
    polymers: 40.0,
    water: 12.0,
    # Manufactured — expensive, require refined inputs
    components: 80.0,
    electronics: 120.0,
    tools: 90.0,
    # Consumer — varies by necessity
    food: 18.0,
    medical: 100.0,
    luxury: 150.0
  }

  @doc """
  Returns the list of all commodities in the simulation.
  """
  @spec all() :: [commodity()]
  def all, do: @all_commodities

  @doc """
  Returns commodities in a specific tier.
  """
  @spec by_tier(tier()) :: [commodity()]
  def by_tier(tier), do: Map.get(@commodities_by_tier, tier, [])

  @doc """
  Returns the tier for a commodity.
  """
  @spec tier(commodity()) :: tier()
  def tier(commodity), do: Map.fetch!(@commodity_tier, commodity)

  @doc """
  Returns all tier definitions.
  """
  @spec tiers() :: %{tier() => [commodity()]}
  def tiers, do: @commodities_by_tier

  @doc """
  Returns the base (seed) price for a commodity.

  ## Examples

      iex> Simulator.Economy.Commodities.base_price(:ore)
      15.0

      iex> Simulator.Economy.Commodities.base_price(:electronics)
      120.0
  """
  @spec base_price(commodity()) :: float()
  def base_price(commodity) when commodity in @all_commodities do
    Map.fetch!(@base_prices, commodity)
  end

  @doc """
  Returns true if the atom is a valid commodity.
  """
  @spec valid?(atom()) :: boolean()
  def valid?(commodity), do: commodity in @all_commodities
end
