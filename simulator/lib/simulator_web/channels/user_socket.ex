defmodule SimulatorWeb.UserSocket do
  @moduledoc """
  WebSocket endpoint for external simulation clients.

  Routes all `"simulation:*"` topics to `SimulatorWeb.SimulationChannel`.
  No authentication for the POC — all connections are accepted.

  ## Connection

      ws://localhost:4000/simulation/websocket

  ## Topics

  Join any simulation topic by prefixing with `"simulation:"`:

      "simulation:tick"                          — global tick stream
      "simulation:system:system-sol"             — orbital updates
      "simulation:market:earth-station"          — price updates, trades
      "simulation:ship:ship-artemis-7"           — ship events
      "simulation:facility:facility-earth-station" — docking, population
  """

  use Phoenix.Socket

  channel "simulation:*", SimulatorWeb.SimulationChannel

  @impl true
  def connect(_params, socket, _connect_info) do
    {:ok, socket}
  end

  @impl true
  def id(_socket), do: nil
end
