defmodule Simulator.AI.Personality do
  @moduledoc """
  Personality profiles that drive agent decision-making.

  A personality is a map of axis weights (0.0 to 1.0) that determine
  how much an agent cares about each concern. The utility scoring system
  multiplies consideration values by their personality weight to produce
  action scores.

  ## Axes

    * `:profit` — desire for economic gain
    * `:safety` — aversion to risk (fuel, health, danger)
    * `:morale` — concern for crew/population wellbeing
    * `:exploration` — preference for novelty and new locations
    * `:loyalty` — commitment to current contracts/assignments
    * `:aggression` — willingness to take hostile actions (future)

  ## Archetypes

  Predefined personality profiles for common agent behaviors.
  Agents can also be spawned with randomized personalities for
  emergent variation.
  """

  @type t :: %{atom() => float()}

  @axes [:profit, :safety, :morale, :exploration, :loyalty, :aggression]

  @doc """
  Returns all personality axes.
  """
  @spec axes() :: [atom()]
  def axes, do: @axes

  # --- Ship Archetypes ---

  @doc """
  Conservative trader — prioritizes safety and steady profits.
  Refuels early, avoids long routes, keeps crew happy.

  Prefers known-payout goals (contracts, station jobs) over speculative trading.
  """
  @spec cautious_trader() :: t()
  def cautious_trader do
    %{
      profit: 0.6,
      safety: 0.9,
      morale: 0.5,
      exploration: 0.1,
      loyalty: 0.7,
      aggression: 0.0,
      prefer_goals: %{fulfill_contract: 0.3, fulfill_delivery: 0.3, station_job: 0.2}
    }
  end

  @doc """
  Profit-maximizing trader — takes risks for bigger payoffs.
  Runs fuel low, picks the most profitable route regardless of distance.

  Prefers market speculation over contracts.
  """
  @spec aggressive_trader() :: t()
  def aggressive_trader do
    %{
      profit: 0.95,
      safety: 0.2,
      morale: 0.2,
      exploration: 0.3,
      loyalty: 0.3,
      aggression: 0.1,
      prefer_goals: %{trade_run: 0.3}
    }
  end

  @doc """
  Balanced trader — moderate on all axes. The default.
  """
  @spec balanced_trader() :: t()
  def balanced_trader do
    %{
      profit: 0.7,
      safety: 0.5,
      morale: 0.4,
      exploration: 0.3,
      loyalty: 0.5,
      aggression: 0.0,
      prefer_goals: %{}
    }
  end

  @doc """
  Explorer — prefers new routes and unknown destinations.
  Accepts lower profit for the chance to discover.
  """
  @spec explorer() :: t()
  def explorer do
    %{
      profit: 0.3,
      safety: 0.5,
      morale: 0.4,
      exploration: 0.9,
      loyalty: 0.2,
      aggression: 0.0,
      prefer_goals: %{explore: 0.4}
    }
  end

  # --- Trucker Archetypes ---

  @doc """
  Reliable trucker — prioritizes contract fulfillment and safety.
  Prefers delivery contracts over speculative trading.
  """
  @spec reliable_trucker() :: t()
  def reliable_trucker do
    %{
      profit: 0.5,
      safety: 0.7,
      morale: 0.5,
      exploration: 0.1,
      loyalty: 0.9,
      aggression: 0.0,
      prefer_goals: %{fulfill_delivery: 0.4, fulfill_contract: 0.3}
    }
  end

  @doc """
  Opportunistic trucker — takes the most profitable delivery contracts.
  Higher profit focus than reliable trucker, lower safety threshold.
  """
  @spec opportunistic_trucker() :: t()
  def opportunistic_trucker do
    %{
      profit: 0.7,
      safety: 0.4,
      morale: 0.3,
      exploration: 0.2,
      loyalty: 0.7,
      aggression: 0.1,
      prefer_goals: %{fulfill_delivery: 0.25, trade_run: 0.2}
    }
  end

  @doc """
  Courier — small, fast, specialized in moving people and light parcels.
  Prefers short, predictable passenger runs over speculative trading.
  """
  @spec courier() :: t()
  def courier do
    %{
      profit: 0.6,
      safety: 0.8,
      morale: 0.7,
      exploration: 0.2,
      loyalty: 0.8,
      aggression: 0.0,
      prefer_goals: %{
        fulfill_passenger_transport: 0.35,
        fulfill_delivery: 0.25,
        station_job: 0.15
      }
    }
  end

  # --- Crew Archetypes ---

  @doc """
  Diligent crew member — works hard, tolerates discomfort.
  """
  @spec diligent() :: t()
  def diligent do
    %{profit: 0.3, safety: 0.4, morale: 0.3, exploration: 0.1, loyalty: 0.9, aggression: 0.0}
  end

  @doc """
  Self-preserving crew — prioritizes own needs over duty.
  """
  @spec self_preserving() :: t()
  def self_preserving do
    %{profit: 0.5, safety: 0.9, morale: 0.8, exploration: 0.2, loyalty: 0.2, aggression: 0.1}
  end

  # --- Generation ---

  @doc """
  Generates a random personality with values between 0.1 and 1.0.
  """
  @spec random() :: t()
  def random do
    Map.new(@axes, fn axis -> {axis, 0.1 + :rand.uniform() * 0.9} end)
  end

  @doc """
  Generates a personality based on an archetype with slight random variation.
  Each numeric axis is perturbed by ±0.1 (clamped to 0.0-1.0). Non-numeric
  fields like `:prefer_goals` pass through unchanged.
  """
  @spec with_variation(t()) :: t()
  def with_variation(base) do
    Map.new(base, fn
      {axis, value} when is_number(value) ->
        perturbed = value + (:rand.uniform() * 0.2 - 0.1)
        {axis, perturbed |> max(0.0) |> min(1.0) |> Float.round(2)}

      {key, value} ->
        {key, value}
    end)
  end

  @doc """
  Returns a random ship archetype with slight variation.
  """
  @spec random_ship_personality() :: t()
  def random_ship_personality do
    archetype =
      Enum.random([
        &cautious_trader/0,
        &aggressive_trader/0,
        &balanced_trader/0,
        &explorer/0,
        &reliable_trucker/0,
        &opportunistic_trucker/0,
        &courier/0
      ])

    with_variation(archetype.())
  end

  @doc """
  Returns a random crew personality with slight variation.
  """
  @spec random_crew_personality() :: t()
  def random_crew_personality do
    archetype = Enum.random([&diligent/0, &self_preserving/0, &balanced_trader/0])
    with_variation(archetype.())
  end
end
