defmodule SimulatorWeb.ApiController do
  @moduledoc """
  JSON API for simulation inspection and control.

  Designed for programmatic access — Claude can `curl` these endpoints
  to self-review simulation behavior, and external tools (Godot, scripts)
  can use them for integration.

  ## Endpoints

      GET  /api/health        — simulation health check
      GET  /api/report        — full simulation snapshot
      GET  /api/markets       — all market states
      GET  /api/ships         — all ship states
      GET  /api/facilities    — all facility states
      GET  /api/populations   — all population states
      GET  /api/factions      — all faction states (treasury, subsidies, shortages)
      GET  /api/agent/:id     — single agent state by ID
      POST /api/sim/pause     — pause simulation
      POST /api/sim/resume    — resume simulation
      POST /api/sim/speed     — set tick speed
  """

  use SimulatorWeb, :controller

  alias Simulator.{Metrics, Queries, Serializer, TickCoordinator}
  alias Simulator.Tools.Reviewer

  @doc """
  Returns simulation health status.
  """
  def health(conn, _params) do
    case Reviewer.health_check() do
      :ok ->
        json(conn, %{status: "ok"})

      {:problems, problems} ->
        json(conn, %{status: "problems", problems: problems})
    end
  end

  @doc """
  Returns a full simulation snapshot: tick, markets, ships, facilities, metrics.
  """
  def report(conn, _params) do
    metrics = Metrics.snapshot()

    config = Simulator.Simulation.Config

    report = %{
      tick: TickCoordinator.get_tick(),
      running: TickCoordinator.running?(),
      health: format_health(Reviewer.health_check()),
      config: %{
        ticks_per_second: config.ticks_per_second(),
        world_speed: config.world_speed(),
        tick_scale: config.tick_scale(),
        tick_interval_ms: config.tick_interval_ms()
      },
      systems: build_systems(),
      markets: serialize_list(Queries.all_markets()),
      ships: serialize_list(Queries.all_ships()),
      facilities: serialize_list(Queries.all_facilities()),
      populations: serialize_list(Queries.all_populations()),
      factions: serialize_list(Queries.all_factions()),
      observers: build_observers(),
      metrics: %{
        tick_avg_us: metrics.tick.avg_duration_us,
        tick_p99_us: metrics.tick.p99_duration_us,
        ticks_per_second: metrics.tick.ticks_per_second,
        agent_count: metrics.agents.total,
        stalled_count: length(metrics.agents.stalled)
      }
    }

    json(conn, report)
  end

  @doc """
  Returns all market states.
  """
  def markets(conn, _params) do
    data = serialize_list(Queries.all_markets())
    json(conn, %{data: data})
  end

  @doc """
  Returns all ship states.
  """
  def ships(conn, _params) do
    data = serialize_list(Queries.all_ships())
    json(conn, %{data: data})
  end

  @doc """
  Returns all facility states.
  """
  def facilities(conn, _params) do
    data = serialize_list(Queries.all_facilities())
    json(conn, %{data: data})
  end

  @doc """
  Returns all population states.
  """
  def populations(conn, _params) do
    data = serialize_list(Queries.all_populations())
    json(conn, %{data: data})
  end

  @doc """
  Returns all faction states. Useful for listing available factions and
  deciding which `simulation:faction:<faction_id>` topics to subscribe to.
  """
  def factions(conn, _params) do
    data = serialize_list(Queries.all_factions())
    json(conn, %{data: data})
  end

  @doc """
  Returns all ship positions as a compact list. Lightweight endpoint
  for game clients that prefer polling over WebSocket.
  """
  def positions(conn, _params) do
    tick = Simulator.TickCoordinator.get_tick()

    ships =
      Simulator.Spatial.ChunkManager.all_positions()
      |> Enum.map(fn {id, x, y} ->
        %{id: id, x: Float.round(x * 1.0, 3), y: Float.round(y * 1.0, 3)}
      end)

    json(conn, %{tick: tick, ships: ships})
  end

  @doc """
  Returns a single agent's state by ID.
  """
  def agent(conn, %{"id" => agent_id}) do
    case Simulator.Agents.Agent.whereis(agent_id) do
      {:ok, pid} ->
        state =
          try do
            GenServer.call(pid, :get_state, 2_000) |> Serializer.serialize_state()
          catch
            :exit, _ -> %{"error" => "agent_timeout"}
          end

        json(conn, state)

      :error ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "agent_not_found", id: agent_id})
    end
  end

  @doc """
  Pauses the simulation.
  """
  def pause(conn, _params) do
    TickCoordinator.pause()
    json(conn, %{status: "paused", tick: TickCoordinator.get_tick()})
  end

  @doc """
  Resumes the simulation.
  """
  def resume(conn, _params) do
    if TickCoordinator.get_tick() == 0 do
      TickCoordinator.start()
    else
      TickCoordinator.resume()
    end

    json(conn, %{status: "running", tick: TickCoordinator.get_tick()})
  end

  @doc """
  Sets the tick speed. Expects `{"interval_ms": integer}` in the body.
  """
  def speed(conn, %{"interval_ms" => ms}) when is_integer(ms) and ms > 0 do
    TickCoordinator.set_speed(ms)
    json(conn, %{status: "speed_set", interval_ms: ms})
  end

  def speed(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "interval_ms must be a positive integer"})
  end

  # --- Private ---

  defp serialize_list(items) do
    Enum.map(items, &Serializer.serialize_state/1)
  end

  defp build_observers do
    Simulator.Spatial.ChunkManager.list_observers()
    |> Enum.map(fn obs ->
      %{
        id: obs.id,
        x: obs.x,
        y: obs.y,
        radius: obs.radius,
        owner: to_string(obs.owner),
        label: obs.label
      }
    end)
  end

  defp format_health(:ok), do: "ok"
  defp format_health({:problems, problems}), do: %{status: "problems", problems: problems}

  defp build_systems do
    Simulator.World.Registry.system_ids()
    |> Enum.map(fn system_id ->
      {ox, oy} = Simulator.World.Registry.universe_offset(system_id)

      bodies =
        case Simulator.Agents.Agent.whereis(system_id) do
          {:ok, pid} ->
            state = Simulator.World.System.get_state(pid)

            Enum.map(state.bodies, fn {body_id, body} ->
              bx = body.orbit_radius * :math.cos(body.current_angle * :math.pi() / 180)
              by = body.orbit_radius * :math.sin(body.current_angle * :math.pi() / 180)

              %{
                id: body_id,
                name: body.name,
                type: to_string(body.type),
                orbit_radius: body.orbit_radius,
                orbit_period: body.orbit_period,
                current_angle: Float.round(body.current_angle, 2),
                x: Float.round(ox + bx, 4),
                y: Float.round(oy + by, 4)
              }
            end)

          :error ->
            []
        end

      %{id: system_id, offset_x: ox, offset_y: oy, bodies: bodies}
    end)
  end
end
