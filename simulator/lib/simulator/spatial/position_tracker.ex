defmodule Simulator.Spatial.PositionTracker do
  @moduledoc """
  Computes spatial positions for entities based on their state.

  Extracts position computation logic so it can be shared between
  the dashboard SVG rendering and the ChunkManager spatial system.
  """

  alias Simulator.World.Body

  # No hardcoded map — uses WorldRegistry for location→body resolution

  @doc """
  Computes `{x, y}` for a celestial body given its orbital parameters.
  """
  @spec body_position(Body.t()) :: {float(), float()}
  def body_position(%Body{orbit_radius: r, current_angle: angle}) do
    {r * :math.cos(angle * :math.pi() / 180), r * :math.sin(angle * :math.pi() / 180)}
  end

  @doc """
  Computes `{x, y}` for a ship given its state, a map of body positions,
  and the current tick.

  Returns `nil` if the position cannot be determined.

  ## Parameters

    * `ship_state` — the ship's GenServer state (needs `:location`, `:transit`)
    * `body_positions` — `%{body_id => {x, y}}` map of current body coordinates
    * `current_tick` — the current simulation tick (for transit interpolation)
  """
  @spec ship_position(map(), map(), non_neg_integer()) :: {float(), float()} | nil
  def ship_position(ship_state, body_positions, current_tick) do
    cond do
      is_binary(ship_state.location) ->
        case body_id_for_location(ship_state.location) do
          nil -> nil
          body_id -> Map.get(body_positions, body_id)
        end

      ship_state[:transit] != nil ->
        transit = ship_state.transit
        from_pos = location_position(transit.from, body_positions)
        to_pos = location_position(transit.to, body_positions)

        cond do
          from_pos && to_pos ->
            interpolate(
              from_pos,
              to_pos,
              transit.departure_tick,
              transit.arrival_tick,
              current_tick
            )

          # Can't resolve one end — use the one we can, or fall back to last position
          to_pos ->
            to_pos

          from_pos ->
            from_pos

          true ->
            nil
        end

      true ->
        nil
    end
  end

  @doc """
  Returns the body_id for a location string (e.g., "earth-station" → "earth").
  """
  @spec body_id_for_location(String.t()) :: String.t() | nil
  def body_id_for_location(location) do
    Simulator.World.Registry.body_id_for_location(location)
  end

  @doc """
  Returns `{x, y}` for a location by resolving to its body's position.
  """
  @spec location_position(String.t(), map()) :: {float(), float()} | nil
  def location_position(location, body_positions) do
    case body_id_for_location(location) do
      nil -> nil
      body_id -> Map.get(body_positions, body_id)
    end
  end

  @doc """
  Linearly interpolates between two points based on tick progress.
  """
  @spec interpolate(
          {float(), float()},
          {float(), float()},
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer()
        ) :: {float(), float()}
  def interpolate({fx, fy}, {tx, ty}, departure_tick, arrival_tick, current_tick) do
    duration = max(arrival_tick - departure_tick, 1)
    elapsed = current_tick - departure_tick
    t = min(max(elapsed / duration, 0.0), 1.0)
    {fx + (tx - fx) * t, fy + (ty - fy) * t}
  end
end
