defmodule Simulator.Agents.ShipAgent.Plan do
  @moduledoc """
  A multi-step plan that a ship commits to and executes over several ticks.

  Ships don't make single decisions — they commit to plans and re-evaluate
  when conditions change or the plan expires. This prevents jittery behavior
  where a ship flip-flops every tick.

  ## Plan Types

    * `:trade_run` — buy at one location, sell at another
    * `:refuel` — travel to a location and buy fuel
    * `:idle` — wait at current location (no profitable routes)
  """

  alias Simulator.Agents.ShipAgent.PlanStep

  @type t :: %__MODULE__{
          type: :trade_run | :refuel | :idle,
          steps: [PlanStep.t()],
          current_step_index: non_neg_integer(),
          expected_profit: float(),
          created_at_tick: non_neg_integer(),
          expires_at_tick: non_neg_integer()
        }

  @enforce_keys [:type, :steps, :created_at_tick, :expires_at_tick]
  defstruct [
    :type,
    :created_at_tick,
    :expires_at_tick,
    steps: [],
    current_step_index: 0,
    expected_profit: 0.0
  ]

  @doc """
  Returns the next step to execute, or `nil` if the plan is complete.
  """
  @spec next_step(t()) :: PlanStep.t() | nil
  def next_step(%__MODULE__{steps: steps, current_step_index: idx}) do
    Enum.at(steps, idx)
  end

  @doc """
  Advances to the next step, returning the updated plan.
  """
  @spec advance(t()) :: t()
  def advance(%__MODULE__{current_step_index: idx} = plan) do
    %{plan | current_step_index: idx + 1}
  end

  @doc """
  Returns true if the plan has been completed (all steps executed).
  """
  @spec complete?(t()) :: boolean()
  def complete?(%__MODULE__{steps: steps, current_step_index: idx}) do
    idx >= length(steps)
  end

  @doc """
  Returns true if the plan has expired given the current tick.
  """
  @spec expired?(t(), non_neg_integer()) :: boolean()
  def expired?(%__MODULE__{expires_at_tick: expires}, current_tick) do
    current_tick > expires
  end
end
