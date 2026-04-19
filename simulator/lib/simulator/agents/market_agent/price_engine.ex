defmodule Simulator.Agents.MarketAgent.PriceEngine do
  @moduledoc """
  Price calculation engine for market commodities.

  Prices are driven by **coverage** — how many ticks of demand the current
  supply can satisfy. This creates stable prices when supply is adequate
  and gradual movement when supply/demand shifts.

  ## Coverage Model

  `coverage = supply / max(demand, 1)` — ticks of demand covered.

    * coverage > 100: very abundant → slight downward drift
    * coverage 20-100: adequate → stable (no pressure)
    * coverage 5-20: tightening → gradual upward pressure
    * coverage 1-5: scarce → moderate upward pressure
    * coverage < 1: critical → strong upward pressure

  ## Price Movement

  Prices change by at most `elasticity` per tick (default 2%). This means
  even in a crisis, prices take 30+ ticks to double — giving ships time
  to respond with deliveries before prices hit extremes.

  ## Design Philosophy

  The old model (raw supply/demand ratio) caused 7% swings per tick,
  crashing prices to floor in ~50 ticks. The coverage model treats
  large stockpiles as stability buffers, not oversupply signals.
  """

  @absolute_price_ceiling 500.0

  # Shortage urgency amplifies the per-tick elasticity cap on upward pressure
  # so prices can actually climb during sustained scarcity. Below the onset
  # threshold the multiplier is 1.0 (no change); above it, we linearly scale
  # up to a cap.
  @urgency_onset_ticks 20
  @urgency_ramp_ticks 30
  @urgency_max_multiplier 4.0

  @doc """
  Recalculates a commodity price based on supply coverage relative to demand.

  ## Parameters

    * `current_price` — the commodity's price last tick
    * `supply` — available units in the market
    * `demand` — units consumed per tick (aggregate from pops + facilities)
    * `elasticity` — max price change per tick as a fraction (e.g., 0.02 = 2%)
    * `shortage_ticks` — consecutive ticks this commodity has been in shortage
      (supply below a low fraction of demand). Amplifies upward pressure via
      an urgency multiplier so price can climb out of the elasticity cap.
  """
  @spec recalculate(
          float(),
          non_neg_integer(),
          non_neg_integer(),
          float(),
          non_neg_integer()
        ) :: float()
  def recalculate(current_price, supply, demand, elasticity, shortage_ticks \\ 0) do
    effective_demand = max(demand, 1)
    coverage = supply / effective_demand

    # Coverage → pressure: how much the price wants to move
    # Negative = downward pressure (abundant), positive = upward (scarce)
    pressure = coverage_to_pressure(coverage)

    # Apply elasticity as a speed limiter. Urgency only accelerates upward
    # movement — oversupply still bleeds off at the normal rate.
    urgency = urgency_multiplier(shortage_ticks)
    effective_elasticity = if pressure > 0, do: elasticity * urgency, else: elasticity
    clamped_pressure = pressure * effective_elasticity

    new_price = current_price * (1.0 + clamped_pressure)

    new_price
    |> max(1.0)
    |> min(@absolute_price_ceiling)
    |> Float.round(2)
  end

  @doc """
  Returns the urgency multiplier that `recalculate/5` applies to upward
  pressure when a commodity has been in shortage for `shortage_ticks`
  consecutive ticks. Exposed for tests and inspection.
  """
  @spec urgency_multiplier(non_neg_integer()) :: float()
  def urgency_multiplier(shortage_ticks) when shortage_ticks <= @urgency_onset_ticks, do: 1.0

  def urgency_multiplier(shortage_ticks) do
    raw = 1.0 + (shortage_ticks - @urgency_onset_ticks) / @urgency_ramp_ticks
    min(raw, @urgency_max_multiplier)
  end

  # Maps coverage (ticks of supply) to a pressure value (-1.0 to +1.0)
  # This is the core economic curve of the simulation.
  defp coverage_to_pressure(coverage) do
    cond do
      # Critical shortage: < 1 tick of supply
      coverage < 1 -> 1.0
      # Scarce: 1-5 ticks
      coverage < 5 -> 0.5 + (5 - coverage) / 8
      # Tightening: 5-20 ticks
      coverage < 20 -> (20 - coverage) / 30
      # Adequate: 20-100 ticks — stable, no pressure
      coverage < 100 -> 0.0
      # Abundant: 100-500 ticks — moderate downward drift
      coverage < 500 -> -0.3
      # Heavily oversupplied: 500-5000
      coverage < 5000 -> -0.6
      # Massively oversupplied: crash price fast
      true -> -1.0
    end
  end

  @doc """
  Applies the market spread to a base price, returning the buy and sell prices.

  The buyer pays more than the base price; the seller receives less.
  The spread is the market's fee for facilitating the trade.

  ## Examples

      iex> PriceEngine.apply_spread(40.0, 0.10)
      {42.0, 38.0}
  """
  @spec apply_spread(float(), float()) :: {float(), float()}
  def apply_spread(base_price, spread) do
    half_spread = spread / 2
    buy_price = Float.round(base_price * (1 + half_spread), 2)
    sell_price = Float.round(base_price * (1 - half_spread), 2)
    {buy_price, sell_price}
  end
end
