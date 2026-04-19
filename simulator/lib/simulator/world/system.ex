defmodule Simulator.World.System do
  @moduledoc """
  Manages a solar system — orbital positions, travel time calculations,
  and ship tracking.

  The SystemAgent advances orbital positions each tick, so travel times
  between locations change dynamically based on planetary alignment.
  A skilled ship (or player) times trade runs to coincide with favorable
  orbital windows.
  """

  use Simulator.Agents.Agent

  alias Simulator.World.Body

  @base_speed 0.03

  # --- Public API ---

  @doc """
  Calculates travel time in ticks between two body IDs.
  """
  @spec query_travel_time(pid(), String.t(), String.t()) ::
          {:ok, non_neg_integer()} | {:error, atom()}
  def query_travel_time(pid, from_body_id, to_body_id) do
    GenServer.call(pid, {:query_travel_time, from_body_id, to_body_id})
  end

  @doc """
  Returns the current state of all bodies (positions).
  """
  @spec get_state(pid()) :: map()
  def get_state(pid) do
    GenServer.call(pid, :get_state)
  end

  @doc """
  Returns a map of body positions for UI rendering.
  """
  @spec get_body_positions(pid()) :: map()
  def get_body_positions(pid) do
    GenServer.call(pid, :get_body_positions)
  end

  @doc """
  Returns the resource map for a specific celestial body.

  Returns `%{}` if the body doesn't exist or has no resources.
  """
  @spec get_body_resources(pid(), String.t()) :: %{atom() => float()}
  def get_body_resources(pid, body_id) do
    GenServer.call(pid, {:get_body_resources, body_id})
  end

  # --- Agent Callbacks ---

  @impl Simulator.Agents.Agent
  def agent_type, do: :system

  @impl Simulator.Agents.Agent
  def init_agent(config) do
    state = %{
      id: config.id,
      name: config[:name] || config.id,
      bodies: config[:bodies] || %{},
      facilities: config[:facilities] || %{},
      ship_registry: MapSet.new(),
      tech_level: config[:tech_level] || 1.0,
      tick_count: 0,
      __db_id__: config[:db_id],
      __agent_type__: :system
    }

    {:ok, state}
  end

  @impl Simulator.Agents.Agent
  @orbital_broadcast_interval 10 * Simulator.Simulation.Config.tick_multiplier()

  def handle_tick(tick, state) do
    bodies =
      Map.new(state.bodies, fn {id, body} ->
        {id, Body.advance_orbit(body)}
      end)

    state = %{state | bodies: bodies, tick_count: tick}

    # Broadcast orbital positions periodically
    state =
      if rem(tick, @orbital_broadcast_interval) == 0 do
        broadcast_positions(state, tick)
        mark_dirty(state)
      else
        state
      end

    {:ok, state}
  end

  # --- GenServer Call Handlers ---

  @impl GenServer
  def handle_call({:query_travel_time, from_id, to_id}, _from, state) do
    result = calculate_travel_time(state, from_id, to_id)
    {:reply, result, state}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:get_body_resources, body_id}, _from, state) do
    resources =
      case Map.get(state.bodies, body_id) do
        %{resources: resources} when resources != %{} -> resources
        _ -> %{}
      end

    {:reply, resources, state}
  end

  def handle_call(:get_body_positions, _from, state) do
    positions =
      Map.new(state.bodies, fn {id, body} ->
        {id,
         %{
           name: body.name,
           angle: body.current_angle,
           radius: body.orbit_radius,
           x: body.orbit_radius * :math.cos(body.current_angle * :math.pi() / 180),
           y: body.orbit_radius * :math.sin(body.current_angle * :math.pi() / 180)
         }}
      end)

    {:reply, positions, state}
  end

  # --- Private ---

  defp calculate_travel_time(_state, from_id, to_id) when from_id == to_id do
    {:ok, 0}
  end

  defp calculate_travel_time(state, from_id, to_id) do
    from_body = find_body(state, from_id)
    to_body = find_body(state, to_id)

    case {from_body, to_body} do
      {nil, _} ->
        {:error, :unknown_location}

      {_, nil} ->
        {:error, :unknown_location}

      {a, b} ->
        dist = Body.distance(a, b)
        ticks = max(round(dist / (@base_speed * state.tech_level)), 1)
        {:ok, ticks}
    end
  end

  defp find_body(state, location_id) do
    # Look up body directly, or search facilities mapping
    case Map.get(state.bodies, location_id) do
      nil -> find_body_by_facility(state, location_id)
      body -> body
    end
  end

  defp find_body_by_facility(state, facility_id) do
    Enum.find_value(state.facilities, fn {body_id, facility_ids} ->
      if facility_id in facility_ids, do: Map.get(state.bodies, body_id)
    end)
  end

  defp broadcast_positions(state, tick) do
    positions =
      Map.new(state.bodies, fn {id, body} ->
        {id, %{angle: body.current_angle, radius: body.orbit_radius}}
      end)

    Simulator.Events.broadcast("system:#{state.id}", :orbital_update, %{
      system_id: state.id,
      positions: positions,
      tick: tick
    })

    state
  end
end
