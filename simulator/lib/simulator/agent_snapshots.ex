defmodule Simulator.AgentSnapshots do
  @moduledoc """
  ETS-backed cache of the "public" part of each live agent's state.

  Read-heavy endpoints like `/api/report` used to fan out
  `GenServer.call(pid, :get_state, 1000)` to every agent — with ~350
  agents and five list calls per report, that's ~1,750 sync calls per
  request, every one of them blocked waiting for its target to finish
  a tick. Any moment of transient tick-cost spike (cold start, event
  burst) turned the request into a timeout cascade.

  Instead, each agent writes its own snapshot to this ETS table once
  per tick (microseconds — one `:ets.insert`). Readers just scan the
  table, no GenServer contention, scales to thousands of agents.

  ## Layout

  Single set table `:agent_snapshots` keyed by `{type, agent_id}` →
  serialized map.

    * `put(type, agent_id, snap)` — agent updates its row
    * `list(type)`               — all snapshots of a given type
    * `get(type, agent_id)`      — single snapshot by id
    * `delete(type, agent_id)`   — remove on terminate

  Written by the `Simulator.Agents.Agent` `__using__` macro — agent
  modules don't call this directly.
  """

  @table :agent_snapshots

  @doc """
  Initializes the ETS table. Called by `Simulator.Application` on
  startup alongside the other ETS-backed caches.
  """
  @spec init() :: :ok
  def init do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [
        :named_table,
        :set,
        :public,
        read_concurrency: true,
        write_concurrency: true
      ])
    end

    :ok
  end

  @doc """
  Stores (or replaces) the snapshot for a single agent.
  """
  @spec put(atom(), String.t(), map()) :: :ok
  def put(type, agent_id, snapshot)
      when is_atom(type) and is_binary(agent_id) and is_map(snapshot) do
    :ets.insert(@table, {{type, agent_id}, snapshot})
    :ok
  catch
    # Table disappeared (test teardown, shutdown) — swallow so
    # callers in handle_tick don't crash the agent on shutdown.
    :error, :badarg -> :ok
  end

  @doc """
  Returns all snapshots of the given type, in undefined order.
  """
  @spec list(atom()) :: [map()]
  def list(type) when is_atom(type) do
    :ets.select(@table, [
      {{{type, :"$1"}, :"$2"}, [], [:"$2"]}
    ])
  catch
    :error, :badarg -> []
  end

  @doc """
  Returns a single snapshot, or nil if the agent hasn't written one.
  """
  @spec get(atom(), String.t()) :: map() | nil
  def get(type, agent_id) when is_atom(type) and is_binary(agent_id) do
    case :ets.lookup(@table, {type, agent_id}) do
      [{_, snapshot}] -> snapshot
      [] -> nil
    end
  catch
    :error, :badarg -> nil
  end

  @doc """
  Removes an agent's snapshot. Called from `terminate/2` in the Agent
  macro so decommissioned ships don't linger in the cache.
  """
  @spec delete(atom(), String.t()) :: :ok
  def delete(type, agent_id) when is_atom(type) and is_binary(agent_id) do
    :ets.delete(@table, {type, agent_id})
    :ok
  catch
    :error, :badarg -> :ok
  end

  @doc """
  Test-only: wipes the entire table. Used by `SimulationCase` so
  snapshots don't leak between tests.
  """
  @spec reset() :: :ok
  def reset do
    if :ets.whereis(@table) != :undefined do
      :ets.delete_all_objects(@table)
    end

    :ok
  end
end
