defmodule Simulator.Economy.Reputation do
  @moduledoc """
  Pure functions for reputation changes between agents and factions.

  Reputation is a 0-100 score per faction. Actions increase or decrease
  the score, affecting contract access and pricing.

  ## Tiers

    * 0-20:  Hostile — no access to faction contracts
    * 20-40: Neutral — access to open/stale contracts only
    * 40-60: Friendly — access to standard contracts
    * 60-80: Trusted — premium contracts, better rates
    * 80-100: Allied — exclusive contracts, faction bonuses

  ## Events

  All functions return `{new_reputation_map, change_amount}` so callers
  can broadcast reputation change events.
  """

  @doc """
  Increases reputation with a faction after completing a contract.
  Gain scales with contract payment value.
  """
  @spec contract_completed(%{String.t() => integer()}, String.t(), integer()) ::
          {%{String.t() => integer()}, integer()}
  def contract_completed(rep_map, faction_id, payment) do
    gain = min(5 + div(payment, 2000), 15)
    apply_change(rep_map, faction_id, gain)
  end

  @doc """
  Decreases reputation after breaching or expiring an accepted contract.
  """
  @spec contract_breached(%{String.t() => integer()}, String.t(), integer()) ::
          {%{String.t() => integer()}, integer()}
  def contract_breached(rep_map, faction_id, payment) do
    loss = -(10 + div(payment, 1000))
    loss = max(loss, -25)
    apply_change(rep_map, faction_id, loss)
  end

  @doc """
  Small reputation gain for trading at a faction's market.
  """
  @spec trade_at_market(%{String.t() => integer()}, String.t()) ::
          {%{String.t() => integer()}, integer()}
  def trade_at_market(rep_map, faction_id) do
    apply_change(rep_map, faction_id, 1)
  end

  @doc """
  Small reputation gain for delivering goods to a faction facility
  (even without a contract).
  """
  @spec delivery_to_facility(%{String.t() => integer()}, String.t()) ::
          {%{String.t() => integer()}, integer()}
  def delivery_to_facility(rep_map, faction_id) do
    apply_change(rep_map, faction_id, 1)
  end

  @doc """
  Returns the reputation tier name for a given score.
  """
  @spec tier(integer()) :: atom()
  def tier(rep) when rep < 20, do: :hostile
  def tier(rep) when rep < 40, do: :neutral
  def tier(rep) when rep < 60, do: :friendly
  def tier(rep) when rep < 80, do: :trusted
  def tier(_rep), do: :allied

  @doc """
  Returns the reputation score for a specific faction.
  """
  @spec get(%{String.t() => integer()}, String.t()) :: integer()
  def get(rep_map, faction_id) do
    Map.get(rep_map, faction_id, 30)
  end

  @doc """
  Checks if an agent has sufficient reputation to access something.
  """
  @spec meets_requirement?(%{String.t() => integer()}, String.t(), integer()) :: boolean()
  def meets_requirement?(rep_map, faction_id, min_rep) do
    get(rep_map, faction_id) >= min_rep
  end

  # --- Private ---

  defp apply_change(rep_map, faction_id, change) do
    current = Map.get(rep_map, faction_id, 30)
    new_val = (current + change) |> max(0) |> min(100)
    {Map.put(rep_map, faction_id, new_val), change}
  end
end
