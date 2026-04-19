defmodule Simulator.AI.Considerations do
  @moduledoc """
  Pure functions that evaluate agent state and return a concern level (0.0-1.0).

  Each consideration maps to a personality axis. The utility scoring system
  uses these values, weighted by personality, to rank possible actions.

  All functions are pure — no side effects, no process calls, no ETS reads.
  They take the agent's state map and return a float.

  ## Convention

  - 0.0 = no concern (everything is fine)
  - 1.0 = maximum concern (critical situation)
  - Values are clamped to [0.0, 1.0]
  """

  # --- Ship Considerations ---

  @doc """
  How urgently does the ship need fuel? Maps to `:safety`.
  0.0 = tank is full, 1.0 = running on fumes.
  """
  @spec fuel_urgency(map()) :: {float(), atom()}
  def fuel_urgency(state) do
    ratio = state.fuel / max(state.fuel_capacity, 1.0)
    urgency = 1.0 - ratio
    {clamp(urgency), :safety}
  end

  @doc """
  How profitable is the best available trade route? Maps to `:profit`.
  0.0 = no profitable routes, 1.0 = extremely profitable.

  Uses the ship's known (possibly stale) price data to estimate
  the best profit margin without actually generating full plans.
  """
  @spec trade_opportunity(map()) :: {float(), atom()}
  def trade_opportunity(state) do
    prices = get_in(state, [:memory, :known_prices]) || %{}

    if map_size(prices) < 2 do
      {0.0, :profit}
    else
      # Find the max price differential for any commodity across known locations
      max_margin =
        for {_loc1, commodities1} <- prices,
            {_loc2, commodities2} <- prices,
            {commodity, p1} <- commodities1,
            p2 = Map.get(commodities2, commodity),
            p2 != nil,
            reduce: 0.0 do
          acc ->
            price1 = extract_price(p1)
            price2 = extract_price(p2)
            margin = abs(price2 - price1) / max(min(price1, price2), 1.0)
            max(acc, margin)
        end

      # Normalize: margin of 2.0 (200% markup) = 1.0 concern
      {clamp(max_margin / 2.0), :profit}
    end
  end

  @doc """
  How unhappy is the crew? Maps to `:morale`.
  0.0 = crew is content, 1.0 = mutiny imminent.

  Uses crew morale directly rather than efficiency (which blends
  health and morale). A crew at 30 morale = 0.7 concern.
  """
  @spec crew_morale_concern(map()) :: {float(), atom()}
  def crew_morale_concern(state) do
    crew = Map.get(state, :crew)
    morale = if crew, do: Map.get(crew, :morale, 70), else: 70
    concern = 1.0 - morale / 100.0
    {clamp(concern), :morale}
  end

  @doc """
  How much cargo space is available? Maps to `:profit`.
  0.0 = ship is full, 1.0 = ship is empty (opportunity to buy).
  """
  @spec cargo_opportunity(map()) :: {float(), atom()}
  def cargo_opportunity(state) do
    used = state.cargo |> Map.values() |> Enum.sum()
    available = max(state.cargo_capacity - used, 0)
    {clamp(available / max(state.cargo_capacity, 1)), :profit}
  end

  @doc """
  How long since the ship visited each known location? Maps to `:exploration`.
  0.0 = recently visited everywhere, 1.0 = hasn't moved in a long time.
  """
  @spec exploration_desire(map()) :: {float(), atom()}
  def exploration_desire(state) do
    visited = get_in(state, [:memory, :visited]) || []

    if visited == [] do
      {0.3, :exploration}
    else
      # More locations not recently visited = higher desire
      known_locations = get_in(state, [:memory, :known_prices]) |> Map.keys()
      visited_set = MapSet.new(visited)
      unvisited = Enum.count(known_locations, &(not MapSet.member?(visited_set, &1)))
      {clamp(unvisited / max(length(known_locations), 1)), :exploration}
    end
  end

  @doc """
  How much credits does the ship have relative to its needs? Maps to `:safety`.
  0.0 = wealthy, 1.0 = broke.
  """
  @spec financial_pressure(map()) :: {float(), atom()}
  def financial_pressure(state) do
    credits = Map.get(state, :credits, 0)

    pressure =
      cond do
        credits <= 0 -> 1.0
        credits < 500 -> 0.9
        credits < 1000 -> 0.7
        credits < 3000 -> 0.4
        credits < 5000 -> 0.2
        true -> 0.0
      end

    {clamp(pressure), :safety}
  end

  @doc """
  How good is the best available contract? Maps to `:profit`.
  0.0 = no contracts or poor value, 1.0 = excellent contract available.

  Evaluates contracts from `state.available_contracts` (populated when docked).
  """
  @spec contract_opportunity(map()) :: {float(), atom()}
  def contract_opportunity(state) do
    contracts =
      state
      |> Map.get(:available_contracts, [])
      |> Enum.filter(&supply_contract?/1)

    if contracts == [] do
      {0.0, :profit}
    else
      best = Enum.max_by(contracts, &contract_value(&1, state), fn -> nil end)

      if best do
        value = contract_value(best, state)
        {clamp(value), :profit}
      else
        {0.0, :profit}
      end
    end
  end

  @doc """
  Predicate identifying "supply-style" contracts — the shape the
  `:fulfill_contract` goal was written for: a classic buy-locally,
  deliver-elsewhere contract with a `:commodity` field and no
  pre-escrowed `:reserve_id`.

  Disambiguates from every other type currently on the contract board:

    * `"delivery"`, `"courier"`, `"construction_delivery"` have `:reserve_id`
    * `"passenger_transport"` and `"crew_mission"` have no `:commodity`

  Used by both the consideration scorer and the goal builder so they
  agree on which contracts `:fulfill_contract` can actually handle.
  """
  @spec supply_contract?(map()) :: boolean()
  def supply_contract?(contract) do
    contract[:commodity] != nil and contract[:reserve_id] == nil
  end

  # Contract value: profit margin after fuel costs, normalized to 0-1
  defp contract_value(contract, state) do
    distance = Map.get(contract, :distance, 100)
    fuel_cost = distance * state.fuel_consumption_rate * 10
    net = contract.payment - fuel_cost
    # Normalize: 5000 net profit = 1.0
    max(net / 5000.0, 0.0)
  end

  @doc """
  How distant are the best available contracts? Maps to `:safety`.
  0.0 = nearby contracts available, 1.0 = only far-away contracts available.

  High-safety personalities weight this as a negative factor on contract
  goals, steering them toward short hauls. Low-safety personalities feel
  it only faintly, so distance barely affects their scoring.
  """
  @spec contract_distance_concern(map()) :: {float(), atom()}
  def contract_distance_concern(state) do
    contracts = Map.get(state, :available_contracts, [])

    case contracts do
      [] ->
        {0.0, :safety}

      _ ->
        best_distance =
          contracts
          |> Enum.map(&(&1[:distance] || 100))
          |> Enum.min(fn -> 100 end)

        # 200 ticks of travel = 1.0 concern
        {clamp(best_distance / 200.0), :safety}
    end
  end

  @doc """
  Does the ship have cargo it could sell? Maps to `:profit`.
  0.0 = empty cargo hold, 1.0 = cargo hold is full.
  """
  @spec cargo_to_sell(map()) :: {float(), atom()}
  def cargo_to_sell(state) do
    used = state.cargo |> Map.values() |> Enum.sum()
    capacity = max(state.cargo_capacity, 1)
    {clamp(used / capacity), :profit}
  end

  @doc """
  How aligned are available contracts with the ship's faction? Maps to `:loyalty`.
  0.0 = no faction contracts available, 1.0 = best contract is from own faction.
  """
  @spec faction_affinity(map()) :: {float(), atom()}
  def faction_affinity(state) do
    contracts = Map.get(state, :available_contracts, [])
    ship_faction = Map.get(state, :faction_id)

    if contracts == [] or ship_faction == nil or ship_faction == "independent" do
      {0.3, :loyalty}
    else
      faction_contracts = Enum.filter(contracts, &(&1[:faction_id] == ship_faction))

      if faction_contracts == [] do
        {0.2, :loyalty}
      else
        # Best faction contract value relative to best overall
        best_faction = Enum.max_by(faction_contracts, & &1.payment, fn -> nil end)
        best_overall = Enum.max_by(contracts, & &1.payment, fn -> nil end)

        if best_faction && best_overall && best_overall.payment > 0 do
          ratio = best_faction.payment / best_overall.payment
          {clamp(0.3 + ratio * 0.7), :loyalty}
        else
          {0.3, :loyalty}
        end
      end
    end
  end

  # --- Delivery Contract Considerations ---

  @doc """
  How good is the best available delivery contract? Maps to `:profit`.
  Evaluates delivery contracts (those with a source_location and reserve_id)
  by delivery_fee / estimated travel ticks.
  0.0 = no delivery contracts, 1.0 = highly profitable delivery available.
  """
  @spec delivery_opportunity(map()) :: {float(), atom()}
  def delivery_opportunity(state) do
    contracts = Map.get(state, :available_contracts, [])
    cargo_capacity = Map.get(state, :cargo_capacity, 100)

    delivery_contracts =
      Enum.filter(contracts, fn c ->
        c[:source_location] != nil and c[:reserve_id] != nil and c[:delivery_fee] != nil
      end)

    if delivery_contracts == [] do
      {0.0, :profit}
    else
      best =
        Enum.max_by(delivery_contracts, fn c ->
          delivery_value(c, cargo_capacity)
        end)

      score = delivery_value(best, cargo_capacity)
      {clamp(score), :profit}
    end
  end

  # Score a delivery contract from the ship's perspective.
  # Factors: fee per tick of travel, AND how well the contract
  # quantity matches the ship's cargo capacity.
  # A 2000-unit contract is great for a hauler (2000 cap) but
  # wasteful for a courier (50 cap) — they'd only carry a fraction.
  defp delivery_value(contract, cargo_capacity) do
    fee = contract.delivery_fee || 0
    dist = Map.get(contract, :distance, 100)
    quantity = contract.quantity || 0

    # How much can this ship actually carry?
    carryable = min(quantity, cargo_capacity)
    fill_ratio = carryable / max(quantity, 1)

    # Effective fee = delivery_fee scaled by fill ratio
    # A courier carrying 50/2000 units earns fee * 0.025 — not worth it
    effective_fee = fee * fill_ratio

    # Normalize: 15 credits/tick of travel = 1.0
    effective_fee / max(dist, 1) / 15.0
  end

  @doc """
  How good is the best available passenger transport contract?
  Maps to `:profit`.

  Scored on payment-per-tick-of-travel, normalized against a nominal
  "good passenger run" (~10 cr/tick). Also factors in how well the
  contract size fits the ship's passenger capacity — a 20-passenger
  run is wasteful for a miner with 0 seats.
  """
  @spec passenger_opportunity(map()) :: {float(), atom()}
  def passenger_opportunity(state) do
    contracts = Map.get(state, :available_contracts, [])
    capacity = Map.get(state, :passenger_capacity, 0)

    passenger_contracts =
      Enum.filter(contracts, fn c ->
        c[:contract_type] == "passenger_transport" and
          c[:source_location] != nil and
          c[:passenger_count] != nil
      end)

    cond do
      capacity == 0 or passenger_contracts == [] ->
        {0.0, :profit}

      true ->
        best = Enum.max_by(passenger_contracts, &passenger_value(&1, capacity))
        {clamp(passenger_value(best, capacity)), :profit}
    end
  end

  defp passenger_value(contract, capacity) do
    fee = contract[:payment] || 0
    dist = Map.get(contract, :distance, 100)
    pax = contract[:passenger_count] || 0

    carryable = min(pax, capacity)
    fill_ratio = carryable / max(pax, 1)

    effective_fee = fee * fill_ratio
    # Normalize: 10 cr/tick of travel = 1.0 consideration.
    effective_fee / max(dist, 1) / 10.0
  end

  @doc """
  How much passenger capacity does the ship have free? Maps to `:profit`.
  0.0 = full (or no seats at all), 1.0 = completely empty.
  """
  @spec passenger_capacity_remaining(map()) :: {float(), atom()}
  def passenger_capacity_remaining(state) do
    capacity = Map.get(state, :passenger_capacity, 0)
    passengers = Map.get(state, :passengers, 0)

    if capacity == 0 do
      {0.0, :profit}
    else
      available = max(capacity - passengers, 0)
      {clamp(available / capacity), :profit}
    end
  end

  @doc """
  How attractive is the best available crew mission? Maps to `:profit`.

  Scored as `payment_per_tick × skill_fit` where `skill_fit` is the
  fraction of the required skill the crew currently has. A courier with
  20 combat looking at a 30-combat security job scores 0.67; the same
  courier's specialty (navigation 50) finds a VIP escort much more
  appealing. Normalised against a nominal "good mission" of 50 cr/tick
  so the consideration tops out at 1.0.
  """
  @spec crew_mission_opportunity(map()) :: {float(), atom()}
  def crew_mission_opportunity(state) do
    contracts = Map.get(state, :available_contracts, [])
    crew_skills = crew_skills(state)

    mission_contracts = Enum.filter(contracts, &is_crew_mission?/1)

    if mission_contracts == [] do
      {0.0, :profit}
    else
      best =
        mission_contracts
        |> Enum.map(&crew_mission_score(&1, crew_skills))
        |> Enum.max(fn -> 0.0 end)

      {clamp(best), :profit}
    end
  end

  @doc """
  How well do the crew's skills match the available crew missions?
  Maps to `:loyalty` — a well-matched crew is one that takes on the
  kind of work they're trained for, which loyalty-oriented archetypes
  weight more heavily than the raw profit.

  Returns the average `skill_fit` across all currently-posted missions,
  not just the best — the signal is "are we a good fit for this sector's
  work right now" rather than "is there one great mission waiting".
  """
  @spec crew_mission_fit(map()) :: {float(), atom()}
  def crew_mission_fit(state) do
    contracts = Map.get(state, :available_contracts, [])
    crew_skills = crew_skills(state)

    fits =
      contracts
      |> Enum.filter(&is_crew_mission?/1)
      |> Enum.map(&skill_fit(&1, crew_skills))

    case fits do
      [] ->
        {0.0, :loyalty}

      _ ->
        avg = Enum.sum(fits) / length(fits)
        {clamp(avg), :loyalty}
    end
  end

  defp is_crew_mission?(contract), do: contract[:contract_type] == "crew_mission"

  defp crew_skills(state) do
    case Map.get(state, :crew) do
      %{skills: skills} when is_map(skills) -> skills
      _ -> %{}
    end
  end

  defp crew_mission_score(contract, crew_skills) do
    payment = contract[:payment] || 0
    duration = contract[:duration_ticks] || 1
    per_tick = payment / max(duration, 1)

    # Normalize: 50 cr/tick ≈ 1.0 consideration, before skill fit.
    per_tick * skill_fit(contract, crew_skills) / 50.0
  end

  defp skill_fit(contract, crew_skills) do
    required = contract[:required_skill]
    required_atom = to_atom_safely(required)

    if is_nil(required_atom) do
      0.5
    else
      level = Map.get(crew_skills, required_atom, 0)
      # Missions "want" a crew with ~50 in the matching skill; beyond
      # that the fit tops out so specialists don't infinitely dominate.
      min(level / 50.0, 1.0)
    end
  end

  defp to_atom_safely(nil), do: nil
  defp to_atom_safely(a) when is_atom(a), do: a

  defp to_atom_safely(s) when is_binary(s) do
    try do
      String.to_existing_atom(s)
    rescue
      ArgumentError -> nil
    end
  end

  @doc """
  Can the ship afford typical cargo deposits? Maps to `:safety`.
  0.0 = can't afford any deposits, 1.0 = plenty of capital for deposits.
  """
  @spec deposit_affordability(map()) :: {float(), atom()}
  def deposit_affordability(state) do
    credits = Map.get(state, :credits, 0)
    contracts = Map.get(state, :available_contracts, [])

    all_delivery =
      Enum.filter(contracts, fn c ->
        c[:source_location] != nil and c[:reserve_id] != nil and c[:delivery_fee] != nil
      end)

    zero_deposit = Enum.filter(all_delivery, &((&1[:cargo_deposit] || 0) == 0))
    with_deposit = Enum.filter(all_delivery, &((&1[:cargo_deposit] || 0) > 0))

    cond do
      # Zero-deposit contracts available — any ship can afford these
      zero_deposit != [] ->
        {1.0, :safety}

      with_deposit != [] ->
        avg_deposit =
          Enum.sum(Enum.map(with_deposit, & &1.cargo_deposit)) / length(with_deposit)

        {clamp(credits / max(avg_deposit * 1.5, 1)), :safety}

      true ->
        {0.0, :safety}
    end
  end

  # --- Crew Considerations ---

  @doc """
  How hungry is the crew member? Maps to `:safety`.
  """
  @spec hunger_urgency(map()) :: {float(), atom()}
  def hunger_urgency(state) do
    {clamp(Map.get(state, :hunger, 0) / 100.0), :safety}
  end

  @doc """
  How tired is the crew member? Maps to `:safety`.
  """
  @spec fatigue_urgency(map()) :: {float(), atom()}
  def fatigue_urgency(state) do
    {clamp(Map.get(state, :fatigue, 0) / 100.0), :safety}
  end

  @doc """
  How low is crew morale? Maps to `:morale`.
  """
  @spec morale_concern(map()) :: {float(), atom()}
  def morale_concern(state) do
    morale = Map.get(state, :morale, 70)
    {clamp(1.0 - morale / 100.0), :morale}
  end

  @doc """
  How injured/sick is the crew member? Maps to `:safety`.
  """
  @spec health_urgency(map()) :: {float(), atom()}
  def health_urgency(state) do
    health = Map.get(state, :health, 100)
    {clamp(1.0 - health / 100.0), :safety}
  end

  # --- Helpers ---

  defp clamp(v), do: v |> max(0.0) |> min(1.0)

  defp extract_price(%{price: p}), do: p
  defp extract_price(p) when is_number(p), do: p
  defp extract_price(_), do: 0.0
end
