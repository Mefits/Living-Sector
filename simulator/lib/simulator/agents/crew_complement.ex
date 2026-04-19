defmodule Simulator.Agents.CrewComplement do
  @moduledoc """
  Aggregate crew state for a ship or facility.

  Instead of spawning individual GenServer processes per crew member
  (which consumed 63% of all agents for minimal behavior), a crew
  complement represents the entire crew as aggregate statistics.

  ## What It Tracks

    * `size` — number of crew members
    * `roles` — list of roles (pilot, engineer, etc.)
    * `hunger` — average hunger (0-100)
    * `fatigue` — average fatigue (0-100)
    * `morale` — average morale (0-100)
    * `health` — average health (0-100)
    * `skills` — composite skill map
    * `credits` — total accumulated wages
    * `personality` — composite personality weights

  ## Tick Processing

  The complement ticks as part of its parent agent (ship/facility),
  not as a separate process. This eliminates ~800 GenServer processes.

  ## Future: Individual Promotion

  When a specific crew member needs to be an individual (VIP extraction,
  crew transfer, narrative event), they can be "promoted" from the
  complement to a full CrewAgent temporarily.
  """

  alias Simulator.AI.Personality

  alias Simulator.Simulation.Config

  @hunger_rate 2 * Config.tick_scale()
  @fatigue_rate_active 1 * Config.tick_scale()
  @fatigue_rate_rest -5 * Config.tick_scale()
  @morale_decay_rate 0.5 * Config.tick_scale()
  @morale_recovery_docked 3 * Config.tick_scale()
  @morale_recovery_resting 5 * Config.tick_scale()
  @morale_check_interval 5 * Config.tick_multiplier()

  @type t :: %__MODULE__{
          size: non_neg_integer(),
          roles: [atom()],
          hunger: float(),
          fatigue: float(),
          morale: float(),
          health: float(),
          skills: %{atom() => float()},
          credits: float(),
          personality: Personality.t(),
          current_task: atom()
        }

  defstruct size: 0,
            roles: [],
            hunger: 10.0,
            fatigue: 10.0,
            morale: 70.0,
            health: 100.0,
            skills: %{navigation: 30, engineering: 30, trading: 30, combat: 20},
            credits: 0.0,
            personality: %{},
            current_task: :idle

  @doc """
  Creates a new crew complement from a list of roles.
  """
  @spec new([atom()]) :: t()
  def new(roles) do
    %__MODULE__{
      size: length(roles),
      roles: roles,
      personality: Personality.random_crew_personality(),
      skills: compute_skills(roles)
    }
  end

  @doc """
  Returns a JSON-safe map representation of the complement, suitable
  for writing to a `state` JSONB column.

  Atoms (roles, skill keys, personality axes, `current_task`) become
  strings. `deserialize/2` is the inverse.
  """
  @spec serialize(t()) :: map()
  def serialize(%__MODULE__{} = c) do
    %{
      "size" => c.size,
      "roles" => Enum.map(c.roles, &to_string/1),
      "hunger" => c.hunger,
      "fatigue" => c.fatigue,
      "morale" => c.morale,
      "health" => c.health,
      "skills" => Map.new(c.skills, fn {k, v} -> {to_string(k), v} end),
      "credits" => c.credits,
      "personality" => serialize_personality(c.personality),
      "current_task" => to_string(c.current_task)
    }
  end

  @doc """
  Rebuilds a complement from a map loaded out of the state JSONB.

  Missing keys fall back to the struct defaults. Role and skill atoms
  are restored via `String.to_existing_atom/1` so a typo in the stored
  blob won't inject untrusted atoms into the VM — unknown values fall
  back to `:general` for roles and are dropped for skills.
  """
  @spec deserialize(map() | nil, [atom()]) :: t()
  def deserialize(nil, roles), do: new(roles)
  def deserialize(map, roles) when not is_map(map), do: new(roles)

  def deserialize(map, fallback_roles) when is_map(map) do
    restored_roles =
      case map["roles"] do
        list when is_list(list) -> Enum.map(list, &safe_atom(&1, :general))
        _ -> fallback_roles
      end

    %__MODULE__{
      size: map["size"] || length(restored_roles),
      roles: restored_roles,
      hunger: Map.get(map, "hunger", 10.0),
      fatigue: Map.get(map, "fatigue", 10.0),
      morale: Map.get(map, "morale", 70.0),
      health: Map.get(map, "health", 100.0),
      skills: deserialize_skills(map["skills"], restored_roles),
      credits: Map.get(map, "credits", 0.0),
      personality: deserialize_personality(map["personality"]),
      current_task: safe_atom(map["current_task"], :idle)
    }
  end

  defp serialize_personality(%{} = personality) do
    Map.new(personality, fn
      {k, v} when is_map(v) -> {to_string(k), Map.new(v, fn {gk, gv} -> {to_string(gk), gv} end)}
      {k, v} -> {to_string(k), v}
    end)
  end

  defp serialize_personality(_), do: %{}

  defp deserialize_personality(%{} = map) do
    Map.new(map, fn
      {k, v} when is_map(v) ->
        # nested map (e.g., prefer_goals); re-atomize inner keys only
        # for known goal atoms.
        {safe_atom(k, :_unknown), Map.new(v, fn {gk, gv} -> {safe_atom(gk, :_unknown), gv} end)}

      {k, v} ->
        {safe_atom(k, :_unknown), v}
    end)
    |> Map.reject(fn {k, _} -> k == :_unknown end)
  end

  defp deserialize_personality(_), do: %{}

  defp deserialize_skills(nil, roles), do: compute_skills(roles)

  defp deserialize_skills(map, roles) when is_map(map) do
    base = compute_skills(roles)

    Enum.reduce(map, base, fn {k, v}, acc ->
      case safe_atom(k, :_unknown) do
        :_unknown -> acc
        atom -> Map.put(acc, atom, v)
      end
    end)
  end

  defp deserialize_skills(_, roles), do: compute_skills(roles)

  defp safe_atom(nil, default), do: default
  defp safe_atom(atom, _default) when is_atom(atom), do: atom

  defp safe_atom(s, default) when is_binary(s) do
    try do
      String.to_existing_atom(s)
    rescue
      ArgumentError -> default
    end
  end

  defp safe_atom(_, default), do: default

  @doc """
  Advances the crew complement by one tick. Handles need decay,
  task execution, morale adjustment, and skill growth.

  Called by the parent agent (ship/facility) during its tick.

  ## Options

    * `:docked` — whether the parent is docked at a facility (morale recovery)
    * `:food_available` — food units available for crew to eat from

  Returns `{updated_complement, food_consumed}` when food tracking is enabled,
  or just the updated complement for backward compatibility.
  """
  @spec tick(t(), non_neg_integer(), keyword()) :: t() | {t(), non_neg_integer()}
  def tick(complement, tick, opts \\ []) do
    docked = Keyword.get(opts, :docked, false)
    food_available = Keyword.get(opts, :food_available, nil)

    {complement, food_consumed} =
      complement
      |> apply_hunger()
      |> apply_fatigue()
      |> maybe_adjust_morale(tick, docked)
      |> auto_manage_needs(food_available)

    if food_available != nil do
      {complement, food_consumed}
    else
      complement
    end
  end

  @doc """
  Returns the efficiency score (0.0-1.0) based on crew health and morale.
  Used by ShipAgent to modify travel speed, fuel consumption, trade outcomes.
  """
  @spec efficiency(t()) :: float()
  def efficiency(%__MODULE__{size: 0}), do: 0.5

  def efficiency(%__MODULE__{} = c) do
    (c.health / 100 * 0.6 + c.morale / 100 * 0.4)
    |> max(0.1)
    |> min(1.0)
  end

  @doc """
  Pays wages to the crew. Returns updated complement with accumulated credits.
  """
  @spec pay_wages(t(), non_neg_integer()) :: t()
  def pay_wages(%__MODULE__{} = c, wage_per_crew) do
    %{c | credits: c.credits + c.size * wage_per_crew}
  end

  @doc """
  Grants `amount` points of XP to a specific crew skill, capped at 100.

  Used by crew missions on completion: a security-detail mission grows
  `:combat`, a maintenance mission grows `:engineering`, etc. Other
  skills are untouched. Unknown skill atoms pass through as a no-op so
  a stale mission category doesn't crash the ship.
  """
  @spec grant_skill_xp(t(), atom(), non_neg_integer()) :: t()
  def grant_skill_xp(%__MODULE__{skills: skills} = c, skill, amount)
      when is_atom(skill) and is_integer(amount) and amount > 0 do
    if Map.has_key?(skills, skill) do
      new_value = min(Map.fetch!(skills, skill) + amount, 100)
      %{c | skills: Map.put(skills, skill, new_value)}
    else
      c
    end
  end

  def grant_skill_xp(%__MODULE__{} = c, _skill, _amount), do: c

  @doc """
  Returns true if crew morale is critically low and ship should dock.
  """
  @spec needs_shore_leave?(t()) :: boolean()
  def needs_shore_leave?(%__MODULE__{morale: morale}), do: morale < 50

  @doc """
  Returns true if crew morale has recovered enough to depart.
  """
  @spec shore_leave_complete?(t()) :: boolean()
  def shore_leave_complete?(%__MODULE__{morale: morale}), do: morale >= 100

  @doc """
  Returns a status report map (for inspector/API).
  """
  @spec report(t()) :: map()
  def report(%__MODULE__{} = c) do
    %{
      size: c.size,
      roles: c.roles,
      hunger: round(c.hunger),
      fatigue: round(c.fatigue),
      morale: round(c.morale),
      health: round(c.health),
      efficiency: Float.round(efficiency(c), 2),
      credits: round(c.credits),
      skills: c.skills,
      current_task: c.current_task
    }
  end

  # --- Private ---

  defp apply_hunger(c) do
    %{c | hunger: min(c.hunger + @hunger_rate, 100.0)}
  end

  defp apply_fatigue(%{current_task: :resting} = c) do
    %{c | fatigue: max(c.fatigue + @fatigue_rate_rest, 0.0)}
  end

  defp apply_fatigue(%{current_task: :idle} = c) do
    %{c | fatigue: max(c.fatigue - 1, 0.0)}
  end

  defp apply_fatigue(c) do
    %{c | fatigue: min(c.fatigue + @fatigue_rate_active, 100.0)}
  end

  defp maybe_adjust_morale(c, tick, docked) when rem(tick, @morale_check_interval) == 0 do
    # Penalties from unmet needs
    penalty =
      cond do
        c.hunger > 60 -> -3
        c.fatigue > 70 -> -2
        c.health < 50 -> -4
        true -> 0
      end

    # Morale recovery when docked or resting (shore leave, relaxation)
    recovery =
      cond do
        docked and c.current_task == :resting -> @morale_recovery_resting
        docked -> @morale_recovery_docked
        c.current_task == :resting -> @morale_recovery_docked
        true -> 0
      end

    # Baseline drift toward 50 (slow decay when high, slow recovery when low)
    drift = if c.morale > 50, do: -@morale_decay_rate, else: @morale_decay_rate
    new_morale = (c.morale + penalty + recovery + drift) |> max(0) |> min(100)
    %{c | morale: new_morale}
  end

  defp maybe_adjust_morale(c, _tick, _docked), do: c

  # When food_available is tracked, returns {complement, food_consumed}
  # Thresholds set BELOW morale penalty zones (hunger > 60, fatigue > 70)
  # so crews self-manage before morale damage accumulates.
  defp auto_manage_needs(c, food_available) do
    cond do
      # Hunger highest priority — eat before morale penalty at 60
      c.hunger > 55 ->
        {can_eat, food_used} = check_food(c, food_available)

        if can_eat do
          {%{c | hunger: max(c.hunger - 25, 0), current_task: :eating}, food_used}
        else
          {%{c | current_task: :eating}, 0}
        end

      # Fatigue next — rest before morale penalty at 70
      c.fatigue > 65 ->
        {%{c | current_task: :resting}, 0}

      # In a need-task but needs are satisfied — return to work
      # Resume thresholds match trigger thresholds to avoid no-man's-land states
      c.current_task in [:eating, :resting] and c.hunger < 55 and c.fatigue < 65 ->
        {%{c | current_task: primary_task(c.roles)}, 0}

      c.current_task == :idle ->
        {%{c | current_task: primary_task(c.roles)}, 0}

      true ->
        {c, 0}
    end
  end

  # Crew needs 1 food per crew member to eat
  defp check_food(_c, nil), do: {true, 0}
  defp check_food(c, available) when available >= c.size, do: {true, c.size}
  defp check_food(_c, _available), do: {false, 0}

  defp primary_task(roles) do
    cond do
      :pilot in roles -> :piloting
      :engineer in roles -> :engineering
      :trader in roles -> :trading
      true -> :idle
    end
  end

  defp compute_skills(roles) do
    base = %{navigation: 30, engineering: 30, trading: 30, combat: 20}

    Enum.reduce(roles, base, fn role, skills ->
      case role do
        :pilot -> Map.update!(skills, :navigation, &min(&1 + 10, 100))
        :engineer -> Map.update!(skills, :engineering, &min(&1 + 10, 100))
        :trader -> Map.update!(skills, :trading, &min(&1 + 10, 100))
        _ -> skills
      end
    end)
  end
end
