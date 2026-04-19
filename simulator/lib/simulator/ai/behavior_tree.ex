defmodule Simulator.AI.BehaviorTree do
  @moduledoc """
  Behavior Tree engine for tactical agent execution.

  The tactical layer of the hybrid AI system. Once the utility scoring
  system selects a goal (e.g., `:trade_run`), a behavior tree handles
  the step-by-step execution.

  ## Node Types

    * `sequence(children)` — execute children in order. Fails on first failure.
      Resumes from where it left off (stores index in blackboard).
    * `selector(children)` — try children in order. Succeeds on first success.
      Resets each tick (always starts from first child).
    * `condition(fun)` — evaluate a predicate. Returns `:success` or `:failure`.
    * `action(name, fun)` — execute a side-effecting step. Returns
      `:success`, `:failure`, or `:running` (will be called again next tick).

  ## Tick Model

  `tick/2` advances the tree by one step. The tree returns:
    * `{:running, tree}` — still executing, call again next tick
    * `{:success, tree}` — completed successfully
    * `{:failure, tree}` — failed, caller should handle

  State is carried in a `blackboard` map that persists across ticks.

  ## Example

      trade_run = sequence([
        action(:dock, &dock_at_facility/1),
        action(:refuel, &refuel_ship/1),
        action(:buy, &buy_cargo/1),
        action(:undock, &undock/1),
        action(:travel, &begin_transit/1),
        action(:wait_arrival, &check_arrived/1),
        action(:dock, &dock_at_facility/1),
        action(:sell, &sell_cargo/1),
        action(:refuel, &refuel_ship/1),
        action(:undock, &undock/1)
      ])
  """

  @type status :: :running | :success | :failure
  @type blackboard :: map()

  @type bt_node ::
          {:sequence, [bt_node()], non_neg_integer()}
          | {:selector, [bt_node()]}
          | {:condition, atom(), (blackboard() -> boolean())}
          | {:action, atom(), (blackboard() -> {status(), blackboard()})}

  # --- Node Constructors ---

  @doc """
  Creates a sequence node. Executes children in order, failing on first failure.
  Remembers which child it was on between ticks.
  """
  @spec sequence([bt_node()]) :: bt_node()
  def sequence(children), do: {:sequence, children, 0}

  @doc """
  Creates a selector node. Tries children in order, succeeding on first success.
  Resets to first child each tick.
  """
  @spec selector([bt_node()]) :: bt_node()
  def selector(children), do: {:selector, children}

  @doc """
  Creates a condition node. Evaluates a predicate against the blackboard.
  """
  @spec condition(atom(), (blackboard() -> boolean())) :: bt_node()
  def condition(name, fun), do: {:condition, name, fun}

  @doc """
  Creates an action node. Executes a function that may return
  `:success`, `:failure`, or `:running`.
  """
  @spec action(atom(), (blackboard() -> {status(), blackboard()})) :: bt_node()
  def action(name, fun), do: {:action, name, fun}

  # --- Tick ---

  @doc """
  Advances the behavior tree by one step.

  Returns `{status, updated_tree, updated_blackboard}`.
  """
  @spec tick(bt_node(), blackboard()) :: {status(), bt_node(), blackboard()}
  def tick({:action, name, fun}, bb) do
    case fun.(bb) do
      {:success, new_bb} -> {:success, {:action, name, fun}, new_bb}
      {:failure, new_bb} -> {:failure, {:action, name, fun}, new_bb}
      {:running, new_bb} -> {:running, {:action, name, fun}, new_bb}
    end
  end

  def tick({:condition, name, fun}, bb) do
    if fun.(bb) do
      {:success, {:condition, name, fun}, bb}
    else
      {:failure, {:condition, name, fun}, bb}
    end
  end

  def tick({:sequence, children, index}, bb) do
    if index >= length(children) do
      # All children succeeded
      {:success, {:sequence, children, 0}, bb}
    else
      child = Enum.at(children, index)

      case tick(child, bb) do
        {:success, updated_child, new_bb} ->
          updated_children = List.replace_at(children, index, updated_child)
          # Move to next child
          next = {:sequence, updated_children, index + 1}
          # Check if that was the last one
          if index + 1 >= length(children) do
            {:success, {:sequence, updated_children, 0}, new_bb}
          else
            {:running, next, new_bb}
          end

        {:running, updated_child, new_bb} ->
          updated_children = List.replace_at(children, index, updated_child)
          {:running, {:sequence, updated_children, index}, new_bb}

        {:failure, updated_child, new_bb} ->
          updated_children = List.replace_at(children, index, updated_child)
          {:failure, {:sequence, updated_children, 0}, new_bb}
      end
    end
  end

  def tick({:selector, children}, bb) do
    tick_selector(children, [], bb)
  end

  defp tick_selector([], tried, bb) do
    # All children failed
    {:failure, {:selector, Enum.reverse(tried)}, bb}
  end

  defp tick_selector([child | rest], tried, bb) do
    case tick(child, bb) do
      {:success, updated_child, new_bb} ->
        {:success, {:selector, Enum.reverse(tried) ++ [updated_child | rest]}, new_bb}

      {:running, updated_child, new_bb} ->
        {:running, {:selector, Enum.reverse(tried) ++ [updated_child | rest]}, new_bb}

      {:failure, updated_child, new_bb} ->
        tick_selector(rest, [updated_child | tried], new_bb)
    end
  end

  # --- Utilities ---

  @doc """
  Returns the name of the currently executing node (for debugging/display).
  """
  @spec current_action(bt_node()) :: atom() | nil
  def current_action({:action, name, _fun}), do: name
  def current_action({:condition, name, _fun}), do: name

  def current_action({:sequence, children, index}) do
    if index < length(children) do
      current_action(Enum.at(children, index))
    end
  end

  def current_action({:selector, [child | _]}), do: current_action(child)
  def current_action(_), do: nil

  @doc """
  Returns true if the tree has completed (not running).
  """
  @spec complete?(status()) :: boolean()
  def complete?(:success), do: true
  def complete?(:failure), do: true
  def complete?(:running), do: false

  @doc """
  Resets a sequence node back to index 0.
  """
  @spec reset(bt_node()) :: bt_node()
  def reset({:sequence, children, _index}), do: {:sequence, children, 0}
  def reset(node), do: node
end
