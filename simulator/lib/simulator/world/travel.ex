defmodule Simulator.World.Travel do
  @moduledoc """
  Travel time and fuel cost calculations between locations.

  For the POC, uses a static distance map between the three Sol locations.
  Phase 4 (SystemAgent) replaces this with dynamic orbital calculations.

  ## Distances (ticks)

  Tuned so travel at 1x speed feels like a journey a player could follow,
  escort, or intercept. At 20x dev speed, trips take 5-8 seconds.

      Earth Station ↔ Mars Station:  100 ticks (~1.5 min at 1x)
      Earth Station ↔ Belt Outpost:  150 ticks (~2.5 min at 1x)
      Mars Station  ↔ Belt Outpost:   80 ticks (~1.3 min at 1x)
  """

  @distances %{
    # Sol system
    {"earth-station", "mars-station"} => 100,
    {"mars-station", "earth-station"} => 100,
    {"earth-station", "belt-outpost"} => 150,
    {"belt-outpost", "earth-station"} => 150,
    {"mars-station", "belt-outpost"} => 80,
    {"belt-outpost", "mars-station"} => 80,
    # Alpha Centauri system
    {"haven-station", "proxima-outpost"} => 90,
    {"proxima-outpost", "haven-station"} => 90
  }

  @doc """
  Returns the travel time in ticks between two locations.

  Returns `{:ok, ticks}` or `{:error, :unknown_route}`.

  ## Examples

      iex> Travel.travel_time("earth-station", "mars-station")
      {:ok, 10}

      iex> Travel.travel_time("earth-station", "earth-station")
      {:ok, 0}
  """
  @spec travel_time(String.t(), String.t()) :: {:ok, non_neg_integer()} | {:error, :unknown_route}
  def travel_time(from, to) when from == to, do: {:ok, 0}

  def travel_time(from, to) do
    # Try WorldRegistry first (loaded from JSON), fall back to hardcoded
    case Simulator.World.Registry.travel_time(from, to) do
      nil ->
        case Map.fetch(@distances, {from, to}) do
          {:ok, ticks} -> {:ok, ticks}
          :error -> {:error, :unknown_route}
        end

      ticks ->
        {:ok, ticks}
    end
  end

  @doc """
  Calculates fuel consumed for a trip given the distance in ticks and
  a per-tick fuel consumption rate.

  ## Examples

      iex> Travel.fuel_cost(10, 0.5)
      5.0
  """
  @spec fuel_cost(non_neg_integer(), float()) :: float()
  def fuel_cost(distance_ticks, consumption_rate) do
    distance_ticks * consumption_rate
  end

  @doc """
  Returns all known location IDs.
  """
  @spec locations() :: [String.t()]
  def locations do
    Map.keys(@distances)
    |> Enum.flat_map(fn {from, to} -> [from, to] end)
    |> Enum.uniq()
  end

  @doc """
  Returns all reachable destinations from a given location.
  """
  @spec reachable_from(String.t()) :: [String.t()]
  def reachable_from(location) do
    # Try WorldRegistry first, fall back to hardcoded
    case Simulator.World.Registry.reachable_from(location) do
      [] ->
        @distances
        |> Enum.filter(fn {{from, _to}, _dist} -> from == location end)
        |> Enum.map(fn {{_from, to}, _dist} -> to end)

      destinations ->
        destinations
    end
  end
end
