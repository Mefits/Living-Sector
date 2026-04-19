defmodule Simulator.Simulation.PriorityManager do
  @moduledoc """
  Manages agent tick priority for adaptive resolution scaling.

  Not every agent needs to tick at full speed. Agents far from player
  activity or narrative events can be "backgrounded" — ticking at a
  reduced rate or paused entirely.

  ## Priority Tiers

    * `:foreground` — full tick rate, detailed simulation (default)
    * `:background` — tick every 5th tick, simplified decisions
    * `:dormant` — no ticking, state frozen, resume on interaction

  For the POC, all agents default to `:foreground`. The manager exposes
  an API for future use when the simulation scales beyond a single node.
  """

  use GenServer

  @table __MODULE__

  # --- Public API ---

  @doc """
  Starts the priority manager.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Sets the tick priority for an agent.
  """
  @spec set_priority(String.t(), :foreground | :background | :dormant) :: :ok
  def set_priority(agent_id, priority) when priority in [:foreground, :background, :dormant] do
    :ets.insert(@table, {agent_id, priority})
    :ok
  end

  @doc """
  Gets the tick priority for an agent. Returns `:foreground` if not set.
  """
  @spec get_priority(String.t()) :: :foreground | :background | :dormant
  def get_priority(agent_id) do
    case :ets.lookup(@table, agent_id) do
      [{_, priority}] -> priority
      [] -> :foreground
    end
  end

  @doc """
  Returns true if the agent should process this tick based on its priority.
  """
  @spec should_tick?(String.t(), non_neg_integer()) :: boolean()
  def should_tick?(agent_id, tick) do
    case get_priority(agent_id) do
      :foreground -> true
      :background -> rem(tick, 5 * Simulator.Simulation.Config.tick_multiplier()) == 0
      :dormant -> false
    end
  end

  @doc """
  Returns a manual override for an agent, or `nil` if no override is set.

  Used by `ChunkManager.should_tick?/2` to allow manual foreground/dormant
  overrides that take precedence over spatial chunk divisors. Only returns
  non-nil for agents explicitly set to `:foreground` or `:dormant`.
  Agents at default priority (not explicitly set) return `nil`.
  """
  @spec get_override(String.t()) :: :foreground | :dormant | nil
  def get_override(agent_id) do
    case :ets.lookup(@table, agent_id) do
      [{_, :foreground}] -> :foreground
      [{_, :dormant}] -> :dormant
      _ -> nil
    end
  end

  @doc """
  Returns all priority assignments as a list of `{agent_id, priority}`.
  """
  @spec all_priorities() :: [{String.t(), atom()}]
  def all_priorities do
    :ets.tab2list(@table)
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    {:ok, %{table: table}}
  end
end
