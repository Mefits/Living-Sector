defmodule Simulator.AI.Utility do
  @moduledoc """
  Utility-based action scoring for agent decision-making.

  The strategic layer of the hybrid AI system. Given an agent's personality
  weights and a set of considerations (scored 0.0-1.0 per personality axis),
  each possible action receives a composite score. The highest-scoring action
  wins.

  ## How It Works

  1. **Considerations** are pure functions that evaluate the agent's state
     and return a value from 0.0 (no concern) to 1.0 (critical concern),
     tagged with a personality axis (`:safety`, `:profit`, etc.).

  2. **Actions** declare which considerations are relevant to them and
     how each consideration maps: either as a positive factor (higher
     consideration = more reason to do this action) or negative
     (higher consideration = less reason).

  3. **Scoring** multiplies each consideration value by its personality
     weight, sums them, and normalizes. The action with the highest
     score wins.

  ## Example

      personality = %{profit: 0.8, safety: 0.5}

      considerations = %{
        fuel_urgency: {0.9, :safety},      # fuel is very low
        trade_profit: {0.6, :profit}       # decent trade available
      }

      actions = [
        {:trade_run, [{:trade_profit, :positive}]},
        {:refuel, [{:fuel_urgency, :positive}]},
        {:idle, []}
      ]

      best_action(actions, considerations, personality)
      # => {:refuel, 0.45}  (0.9 * 0.5 = 0.45 beats trade's 0.6 * 0.8 = 0.48... wait)
      # Actually trade wins here! The aggressive personality overrides the safety concern.
  """

  alias Simulator.AI.Personality

  @type consideration :: {float(), atom()}
  @type consideration_map :: %{atom() => consideration()}
  @type action_spec :: {atom(), [{atom(), :positive | :negative}]}

  @doc """
  Scores a single action given its relevant considerations and the personality.

  Each consideration is a `{value, axis}` tuple. The score for the action is
  the sum of `value * personality_weight` for positive considerations, minus
  the same for negative ones.

  Returns the score as a float.
  """
  @spec score_action(action_spec(), consideration_map(), Personality.t()) :: float()
  def score_action({_action, factors}, considerations, personality) do
    Enum.reduce(factors, 0.0, fn {consideration_key, direction}, acc ->
      case Map.get(considerations, consideration_key) do
        {value, axis} ->
          weight = Map.get(personality, axis, 0.0)
          contribution = value * weight

          case direction do
            :positive -> acc + contribution
            :negative -> acc - contribution
          end

        nil ->
          acc
      end
    end)
  end

  @doc """
  Scores all actions and returns the best one as `{action_name, score}`.

  If the personality includes a `:prefer_goals` map, each goal in that map
  gets its declared bonus added to its score — this tie-breaks close calls
  toward archetype-natural behavior (cautious traders lean into contracts,
  aggressive ones into market speculation, etc.).

  If no action scores above 0, returns `{:idle, 0.0}`.
  """
  @spec best_action([action_spec()], consideration_map(), Personality.t()) ::
          {atom(), float()}
  def best_action(actions, considerations, personality) do
    prefer_goals = Map.get(personality, :prefer_goals, %{})

    scored =
      Enum.map(actions, fn {action_name, _factors} = spec ->
        base = score_action(spec, considerations, personality)
        bonus = Map.get(prefer_goals, action_name, 0.0)
        {action_name, base + bonus}
      end)

    case Enum.max_by(scored, &elem(&1, 1), fn -> {:idle, 0.0} end) do
      {_action, score} = result when score > 0 -> result
      _ -> {:idle, 0.0}
    end
  end

  @doc """
  Scores all actions and returns the full ranked list, highest first.
  Useful for debugging and the dashboard inspector. Applies the same
  archetype-preference bonuses as `best_action/3`.
  """
  @spec rank_actions([action_spec()], consideration_map(), Personality.t()) ::
          [{atom(), float()}]
  def rank_actions(actions, considerations, personality) do
    prefer_goals = Map.get(personality, :prefer_goals, %{})

    actions
    |> Enum.map(fn {action_name, _factors} = spec ->
      base = score_action(spec, considerations, personality)
      bonus = Map.get(prefer_goals, action_name, 0.0)
      {action_name, base + bonus}
    end)
    |> Enum.sort_by(&elem(&1, 1), :desc)
  end
end
