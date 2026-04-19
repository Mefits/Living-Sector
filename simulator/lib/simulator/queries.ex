defmodule Simulator.Queries do
  @moduledoc """
  Read-only query functions for the dashboard and HTTP API.

  Backed by `Simulator.AgentSnapshots`, an ETS cache each agent writes
  its own public state into once per tick. Every query here is an ETS
  scan — no `GenServer.call`, no cross-agent blocking, scales cleanly
  to thousands of agents regardless of world state.

  Staleness bound is one tick (~125 ms); for endpoint latency that's
  imperceptible, and the tradeoff vs. "live call a thousand agents
  and wait" is the difference between a working API and one that
  stalls whenever agents are busy.
  """

  alias Simulator.AgentSnapshots

  @doc """
  Returns all ship snapshots.
  """
  @spec all_ships() :: [map()]
  def all_ships, do: AgentSnapshots.list(:ship)

  @doc """
  Returns all market snapshots.
  """
  @spec all_markets() :: [map()]
  def all_markets, do: AgentSnapshots.list(:market)

  @doc """
  Returns all facility snapshots.
  """
  @spec all_facilities() :: [map()]
  def all_facilities, do: AgentSnapshots.list(:facility)

  @doc """
  Returns all population snapshots.
  """
  @spec all_populations() :: [map()]
  def all_populations, do: AgentSnapshots.list(:population)

  @doc """
  Returns all faction snapshots.
  """
  @spec all_factions() :: [map()]
  def all_factions, do: AgentSnapshots.list(:faction)

  @doc """
  Returns all body snapshots.
  """
  @spec all_bodies() :: [map()]
  def all_bodies, do: AgentSnapshots.list(:body)

  @doc """
  Returns a list of `{agent_id, snapshot}` for the given type. Some
  callers (dashboard inspector) want the id alongside the state.
  """
  @spec all_agents_of_type(atom()) :: [{String.t(), map()}]
  def all_agents_of_type(type) when is_atom(type) do
    type
    |> AgentSnapshots.list()
    |> Enum.map(fn snap -> {Map.get(snap, :id), snap} end)
  end

  @doc """
  Returns all pending buy/sell orders across all markets, sorted
  oldest first. Each order is annotated with the market location.
  """
  @spec all_market_orders() :: [map()]
  def all_market_orders do
    all_markets()
    |> Enum.flat_map(fn state ->
      location = Map.get(state, :facility_id)

      buys = annotate_orders(Map.get(state, :pending_buy_orders, []), location)
      sells = annotate_orders(Map.get(state, :pending_sell_orders, []), location)

      buys ++ sells
    end)
    |> Enum.sort_by(&Map.get(&1, :placed_at_tick, 0))
  end

  defp annotate_orders(orders, location) do
    Enum.map(orders, fn order ->
      order
      |> order_to_map()
      |> Map.put(:location, location)
    end)
  end

  defp order_to_map(%_{} = struct), do: Map.from_struct(struct)
  defp order_to_map(map) when is_map(map), do: map

  @doc """
  Returns the system agent snapshot, or nil if not running. Single
  named lookup — still fast even via direct call, but goes through
  the snapshot cache for consistency.
  """
  @spec system_state(String.t()) :: map() | nil
  def system_state(system_id \\ "system-sol") do
    AgentSnapshots.get(:system, system_id)
  end
end
