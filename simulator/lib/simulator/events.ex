defmodule Simulator.Events do
  @moduledoc """
  Central event bus for the simulation.

  All agent state changes publish here via `Phoenix.PubSub`. UI layers
  (LiveView, Phoenix Channels, future Godot client) subscribe to topics —
  they never query agents directly.

  ## Topic Conventions

      "tick"                    — global tick broadcast
      "simulation"              — simulation-wide lifecycle events
      "system:<system_id>"      — system-wide events (orbital updates, ship registry)
      "ship:<ship_id>"          — specific ship updates (position, cargo, plan)
      "market:<facility_id>"    — price changes, trades, shortages
      "facility:<facility_id>"  — docking events, service status, population changes
      "agent:<agent_id>"        — individual agent state (debug/inspector)

  Events are published as `{event_name, payload}` tuples where `event_name`
  is an atom and `payload` is a map.
  """

  @pubsub Simulator.PubSub
  @log_table :event_log
  @max_log_entries 5000

  @doc """
  Initializes the event log ETS table. Called once at app startup.
  """
  @spec init_log() :: :ok
  def init_log do
    if :ets.whereis(@log_table) == :undefined do
      :ets.new(@log_table, [:named_table, :ordered_set, :public, write_concurrency: true])
    end

    :ok
  end

  @doc """
  Logs an event to the ETS-backed event log. The dashboard polls
  the last N entries on its refresh cycle instead of subscribing
  to every agent's PubSub topic.
  """
  @spec log(atom(), map()) :: :ok
  def log(event_name, payload) when is_atom(event_name) do
    key = :erlang.unique_integer([:positive, :monotonic])
    :ets.insert(@log_table, {key, event_name, payload, System.monotonic_time(:millisecond)})

    # Trim old entries if over max
    size = :ets.info(@log_table, :size)

    if size > @max_log_entries * 2 do
      trim_log()
    end

    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc """
  Returns the most recent N log entries, newest first.
  """
  @spec recent_log(pos_integer()) :: [map()]
  def recent_log(limit \\ 50) do
    if :ets.whereis(@log_table) != :undefined do
      :ets.tab2list(@log_table)
      |> Enum.sort_by(&elem(&1, 0), :desc)
      |> Enum.take(limit)
      |> Enum.map(fn {_key, event, payload, ts} ->
        %{event: event, payload: payload, timestamp: ts}
      end)
    else
      []
    end
  end

  @doc """
  Returns the most recent N events related to a specific agent.

  Scans the event log and matches the agent_id against all string values
  in each event's payload (ship_id, facility_id, buyer_id, etc.).
  """
  @spec recent_events_for_agent(String.t(), pos_integer()) :: [map()]
  def recent_events_for_agent(agent_id, limit \\ 5) when is_binary(agent_id) do
    if :ets.whereis(@log_table) != :undefined do
      :ets.tab2list(@log_table)
      |> Enum.sort_by(&elem(&1, 0), :desc)
      |> Enum.filter(fn {_key, _event, payload, _ts} ->
        agent_in_payload?(payload, agent_id)
      end)
      |> Enum.take(limit)
      |> Enum.map(fn {_key, event, payload, ts} ->
        %{event: event, payload: payload, timestamp: ts}
      end)
    else
      []
    end
  end

  defp agent_in_payload?(payload, agent_id) when is_map(payload) do
    Enum.any?(payload, fn
      {_k, v} when is_binary(v) -> v == agent_id
      _ -> false
    end)
  end

  defp agent_in_payload?(_, _), do: false

  defp trim_log do
    entries = :ets.tab2list(@log_table) |> Enum.sort_by(&elem(&1, 0))
    to_delete = Enum.take(entries, length(entries) - @max_log_entries)

    for {key, _, _, _} <- to_delete do
      :ets.delete(@log_table, key)
    end
  end

  @doc """
  Broadcasts an event to all subscribers of the given topic.

  ## Examples

      Simulator.Events.broadcast("market:earth-station", :price_update, %{ore: 42.5})
      Simulator.Events.broadcast("tick", :tick, %{tick: 1})
  """
  @spec broadcast(String.t(), atom(), map()) :: :ok | {:error, term()}
  def broadcast(topic, event, payload) when is_binary(topic) and is_atom(event) do
    Phoenix.PubSub.broadcast(@pubsub, topic, {event, payload})
  end

  @doc """
  Subscribes the calling process to the given topic.

  The process will receive messages as `{event_name, payload}` tuples.

  ## Examples

      Simulator.Events.subscribe("market:earth-station")
  """
  @spec subscribe(String.t()) :: :ok | {:error, term()}
  def subscribe(topic) when is_binary(topic) do
    Phoenix.PubSub.subscribe(@pubsub, topic)
  end

  @doc """
  Unsubscribes the calling process from the given topic.
  """
  @spec unsubscribe(String.t()) :: :ok
  def unsubscribe(topic) when is_binary(topic) do
    Phoenix.PubSub.unsubscribe(@pubsub, topic)
  end
end
