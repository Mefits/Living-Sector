defmodule SimulatorWeb.SimulationChannel do
  @moduledoc """
  Phoenix Channel that relays simulation events over WebSocket.

  Clients join a topic (e.g., `"simulation:market:earth-station"`) and
  receive all PubSub events for that topic as JSON pushes. Clients can
  also query agent state and control the simulation.

  ## Incoming Events

    * `"get_state"` — query a specific agent's state
    * `"get_snapshot"` — query all agents of a type
    * `"sim_control"` — pause/resume/set_speed

  ## Pushed Events

  All PubSub events are forwarded with atom event names converted to
  strings and payloads serialized to JSON-safe maps.
  """

  use SimulatorWeb, :channel

  alias Simulator.{Queries, Serializer, TickCoordinator}

  @impl true
  def join("simulation:" <> topic, _params, socket) do
    Simulator.Events.subscribe(topic)
    {:ok, assign(socket, :topic, topic)}
  end

  # --- Incoming client messages ---

  @impl true
  def handle_in("get_state", %{"id" => agent_id}, socket) do
    result =
      case Simulator.Agents.Agent.whereis(agent_id) do
        {:ok, pid} ->
          state = GenServer.call(pid, :get_state, 5_000)
          {:ok, Serializer.serialize_state(state)}

        :error ->
          {:error, %{"reason" => "agent_not_found"}}
      end

    case result do
      {:ok, data} -> {:reply, {:ok, data}, socket}
      {:error, err} -> {:reply, {:error, err}, socket}
    end
  end

  def handle_in("get_snapshot", %{"type" => type}, socket) do
    data =
      case type do
        "ships" -> Queries.all_ships()
        "markets" -> Queries.all_markets()
        "facilities" -> Queries.all_facilities()
        "populations" -> Queries.all_populations()
        _ -> []
      end

    serialized = Enum.map(data, &Serializer.serialize_state/1)
    {:reply, {:ok, %{"data" => serialized}}, socket}
  end

  def handle_in("sim_control", %{"action" => action} = params, socket) do
    result = handle_control(action, params)
    {:reply, result, socket}
  end

  def handle_in("move_observer", %{"x" => x, "y" => y} = params, socket)
      when is_number(x) and is_number(y) do
    id = Map.get(params, "id", "default")
    radius = (params["radius"] || 20.0) / 1.0

    # Check if observer exists — create if not
    existing = Simulator.Spatial.ChunkManager.list_observers()

    if Enum.any?(existing, &(&1.id == id)) do
      update = %{x: x / 1.0, y: y / 1.0, radius: radius}
      Simulator.Spatial.ChunkManager.update_observer(id, update)
    else
      observer = %Simulator.Spatial.Observer{
        id: id,
        x: x / 1.0,
        y: y / 1.0,
        radius: radius,
        owner: :player,
        label: id
      }

      Simulator.Spatial.ChunkManager.add_observer(observer)
    end

    {:reply, {:ok, %{"status" => "updated", "id" => id}}, socket}
  end

  def handle_in(_event, _payload, socket) do
    {:reply, {:error, %{"reason" => "unknown_event"}}, socket}
  end

  # --- PubSub event relay ---

  @impl true
  def handle_info({event_name, payload}, socket) when is_atom(event_name) do
    push(socket, to_string(event_name), Serializer.deep_stringify(payload))
    {:noreply, socket}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # --- Simulation control ---

  defp handle_control("pause", _params) do
    TickCoordinator.pause()
    {:ok, %{"status" => "paused"}}
  end

  defp handle_control("resume", _params) do
    if TickCoordinator.get_tick() == 0 do
      TickCoordinator.start()
    else
      TickCoordinator.resume()
    end

    {:ok, %{"status" => "running"}}
  end

  defp handle_control("set_speed", %{"interval_ms" => ms}) when is_integer(ms) and ms > 0 do
    TickCoordinator.set_speed(ms)
    {:ok, %{"status" => "speed_set", "interval_ms" => ms}}
  end

  defp handle_control("get_tick", _params) do
    {:ok, %{"tick" => TickCoordinator.get_tick(), "running" => TickCoordinator.running?()}}
  end

  defp handle_control(_action, _params) do
    {:error, %{"reason" => "unknown_action"}}
  end
end
