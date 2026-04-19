defmodule SimulatorWeb.DashboardLive do
  @moduledoc """
  Main simulation dashboard LiveView.

  Subscribes to PubSub topics and renders a real-time view of the
  simulation: system map, market prices, fleet status, and event log.
  Includes controls to play/pause and adjust tick speed.
  """

  use SimulatorWeb, :live_view

  alias Simulator.{Events, Metrics, Queries, TickCoordinator}

  @refresh_interval 2_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # No per-agent PubSub subscriptions — all data is polled on the
      # 2-second refresh cycle. Event log reads from ETS event_log table.
      Process.send_after(self(), :refresh, @refresh_interval)
    end

    socket =
      socket
      |> assign(:page_title, "Mission Control")
      |> assign(:tick, TickCoordinator.get_tick())
      |> assign(:running, TickCoordinator.running?())
      |> assign(:tick_speed, TickCoordinator.get_speed())
      |> assign(:metrics, Metrics.snapshot())
      |> assign(:event_log, [])
      |> assign(:inspected_agent, nil)
      |> assign(:agent_history, [])
      |> assign(:observers, Simulator.Spatial.ChunkManager.list_observers())
      |> assign(:show_chunks, false)
      |> assign(:retired_ships, Simulator.Simulation.RetirementLedger.all())
      |> assign(:fleet_page, 1)
      |> assign(:facilities_page, 1)
      |> assign(:contracts_page, 1)
      |> assign(:orders_page, 1)
      |> assign(:contracts_show_completed, false)
      |> assign_all_systems()
      |> assign_simulation_data()

    {:ok, socket}
  end

  @impl true
  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, @refresh_interval)

    socket =
      socket
      |> assign(:tick, TickCoordinator.get_tick())
      |> assign(:running, TickCoordinator.running?())
      |> assign(:metrics, Metrics.snapshot())
      |> assign_simulation_data()
      |> assign_all_systems()
      |> assign(:retired_ships, Simulator.Simulation.RetirementLedger.all())
      |> assign(:event_log, build_event_log())
      |> refresh_inspector()

    {:noreply, socket}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_chunks", _params, socket) do
    {:noreply, assign(socket, :show_chunks, !socket.assigns.show_chunks)}
  end

  def handle_event("move_observer", %{"x" => x, "y" => y}, socket) do
    Simulator.Spatial.ChunkManager.update_observer("default", %{x: x, y: y})

    {:noreply, socket}
  end

  def handle_event("set_observer_radius", %{"observer_radius" => radius_str}, socket) do
    case Float.parse(radius_str) do
      {radius, _} when radius > 0 ->
        Simulator.Spatial.ChunkManager.update_observer("default", %{radius: radius})
        {:noreply, socket}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_sim", _params, socket) do
    if socket.assigns.running do
      TickCoordinator.pause()
    else
      if TickCoordinator.get_tick() == 0 do
        TickCoordinator.start()
      else
        TickCoordinator.resume()
      end
    end

    {:noreply, assign(socket, :running, TickCoordinator.running?())}
  end

  def handle_event("set_speed", %{"speed" => speed}, socket) do
    case Integer.parse(speed) do
      {ms, _} when ms > 0 ->
        TickCoordinator.set_speed(ms)
        {:noreply, assign(socket, :tick_speed, ms)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("inspect_agent", %{"id" => agent_id}, socket) do
    agent_state = fetch_agent_state(agent_id)
    history = Simulator.Events.recent_events_for_agent(agent_id, 10)
    {:noreply, socket |> assign(:inspected_agent, agent_state) |> assign(:agent_history, history)}
  end

  def handle_event("close_inspector", _params, socket) do
    {:noreply, socket |> assign(:inspected_agent, nil) |> assign(:agent_history, [])}
  end

  def handle_event("fleet_page", %{"page" => page_str}, socket) do
    page = String.to_integer(page_str)
    page = max(1, min(page, socket.assigns.fleet_total_pages))
    {:noreply, socket |> assign(:fleet_page, page) |> assign_simulation_data()}
  end

  def handle_event("facilities_page", %{"page" => page_str}, socket) do
    page = String.to_integer(page_str)
    page = max(1, min(page, socket.assigns.facilities_total_pages))
    {:noreply, socket |> assign(:facilities_page, page) |> assign_simulation_data()}
  end

  def handle_event("toggle_completed_contracts", _params, socket) do
    show = !socket.assigns.contracts_show_completed

    {:noreply,
     socket
     |> assign(:contracts_show_completed, show)
     |> assign(:contracts_page, 1)
     |> assign_simulation_data()}
  end

  def handle_event("contracts_page", %{"page" => page_str}, socket) do
    page = String.to_integer(page_str)
    page = max(1, min(page, socket.assigns.contracts_total_pages))
    {:noreply, socket |> assign(:contracts_page, page) |> assign_simulation_data()}
  end

  def handle_event("orders_page", %{"page" => page_str}, socket) do
    page = String.to_integer(page_str)
    page = max(1, min(page, socket.assigns.orders_total_pages))
    {:noreply, socket |> assign(:orders_page, page) |> assign_simulation_data()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.dashboard flash={@flash}>
      <div class="min-h-screen bg-base-300 p-4">
        <%!-- Header --%>
        <div class="flex items-center justify-between mb-4">
          <div class="flex items-center gap-4">
            <h1 class="text-2xl font-bold text-base-content">Mission Control</h1>
            <span class="badge badge-lg badge-primary font-mono">TICK {@tick}</span>
          </div>
          <div class="flex items-center gap-3">
            <form phx-change="set_speed">
              <select
                name="speed"
                class="select select-sm select-bordered"
                value={@tick_speed}
              >
                <option value="125" selected={@tick_speed == 125}>1x</option>
                <option value="62" selected={@tick_speed == 62}>2x</option>
                <option value="25" selected={@tick_speed == 25}>5x</option>
                <option value="12" selected={@tick_speed == 12}>10x</option>
              </select>
            </form>
            <button
              phx-click="toggle_sim"
              class={[
                "btn btn-sm",
                if(@running, do: "btn-warning", else: "btn-success")
              ]}
            >
              {if @running, do: "⏸ Pause", else: "▶ Play"}
            </button>
          </div>
        </div>

        <%!-- Star Map — full width --%>
        <div class="card bg-base-100 shadow-lg mb-4">
          <div class="card-body p-4">
            <div class="flex items-center justify-between">
              <h2 class="card-title text-sm uppercase tracking-wider text-base-content/60">
                Star Map
              </h2>
              <div class="flex items-center gap-2">
                <button
                  phx-click="toggle_chunks"
                  class={[
                    "btn btn-xs",
                    if(@show_chunks, do: "btn-primary", else: "btn-ghost")
                  ]}
                >
                  Chunks
                </button>
                <%= if @show_chunks do %>
                  <form phx-change="set_observer_radius" class="flex items-center gap-1">
                    <label class="text-xs text-base-content/50">r:</label>
                    <input
                      type="number"
                      name="observer_radius"
                      value={observer_radius(@observers)}
                      step="0.5"
                      min="0.5"
                      max="100"
                      class="input input-xs input-bordered w-16 font-mono"
                    />
                  </form>
                <% end %>
              </div>
            </div>
            <div
              id="star-map"
              phx-hook="PanZoomMap"
              data-chunks-active={to_string(@show_chunks)}
              class="cursor-grab"
            >
              <.continuous_map
                all_systems={@all_systems}
                ships={@all_ships}
                tick={@tick}
                chunk_grid={@chunk_grid}
                observers={@observers}
                show_chunks={@show_chunks}
              />
            </div>
          </div>
        </div>

        <%!-- Two-column panels --%>
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
          <%!-- Fleet (paginated) --%>
          <div class="card bg-base-100 shadow-lg">
            <div class="card-body p-4">
              <h2 class="card-title text-sm uppercase tracking-wider text-base-content/60">
                Fleet ({@ships_total} ships)
              </h2>
              <.fleet_panel ships={@ships} />
              <.pagination
                page={@fleet_page}
                total_pages={@fleet_total_pages}
                event="fleet_page"
              />
            </div>
          </div>

          <%!-- Facilities (paginated) --%>
          <div class="card bg-base-100 shadow-lg">
            <div class="card-body p-4">
              <h2 class="card-title text-sm uppercase tracking-wider text-base-content/60">
                Facilities ({@facilities_total})
              </h2>
              <.facilities_panel facilities={@facilities} />
              <.pagination
                page={@facilities_page}
                total_pages={@facilities_total_pages}
                event="facilities_page"
              />
            </div>
          </div>

          <%!-- Markets --%>
          <div class="card bg-base-100 shadow-lg">
            <div class="card-body p-4">
              <h2 class="card-title text-sm uppercase tracking-wider text-base-content/60">
                Markets
              </h2>
              <.market_panel markets={@markets} />
            </div>
          </div>

          <%!-- Contract Board --%>
          <div class="card bg-base-100 shadow-lg">
            <div class="card-body p-4">
              <div class="flex items-center justify-between">
                <h2 class="card-title text-sm uppercase tracking-wider text-base-content/60">
                  Contract Board ({@contracts_total})
                </h2>
                <button
                  phx-click="toggle_completed_contracts"
                  class={[
                    "btn btn-xs",
                    if(@contracts_show_completed, do: "btn-primary", else: "btn-ghost")
                  ]}
                >
                  {if @contracts_show_completed, do: "All", else: "Active"}
                </button>
              </div>
              <.contracts_panel contracts={@contracts} tick={@tick} />
              <.pagination
                page={@contracts_page}
                total_pages={@contracts_total_pages}
                event="contracts_page"
              />
            </div>
          </div>

          <%!-- Market Orders --%>
          <div class="card bg-base-100 shadow-lg">
            <div class="card-body p-4">
              <h2 class="card-title text-sm uppercase tracking-wider text-base-content/60">
                Market Orders ({@orders_total})
              </h2>
              <.orders_panel orders={@orders} tick={@tick} />
              <.pagination
                page={@orders_page}
                total_pages={@orders_total_pages}
                event="orders_page"
              />
            </div>
          </div>

          <%!-- Event Log --%>
          <div class="card bg-base-100 shadow-lg">
            <div class="card-body p-4">
              <h2 class="card-title text-sm uppercase tracking-wider text-base-content/60">
                Event Log ({length(@event_log)})
              </h2>
              <.event_log_panel events={@event_log} />
            </div>
          </div>

          <%!-- Performance Metrics --%>
          <div class="card bg-base-100 shadow-lg">
            <div class="card-body p-4">
              <h2 class="card-title text-sm uppercase tracking-wider text-base-content/60">
                Performance Metrics
              </h2>
              <.metrics_panel metrics={@metrics} />
            </div>
          </div>

          <%!-- Retired Fleet --%>
          <%= if @retired_ships != [] do %>
            <div class="card bg-base-100 shadow-lg">
              <div class="card-body p-4">
                <h2 class="card-title text-sm uppercase tracking-wider text-base-content/60">
                  Retired Fleet ({length(@retired_ships)} decommissioned)
                </h2>
                <div class="overflow-x-auto max-h-48">
                  <table class="table table-xs">
                    <thead>
                      <tr>
                        <th>Tick</th>
                        <th>Ship</th>
                        <th>Class</th>
                        <th>Faction</th>
                        <th>Location</th>
                        <th>Morale</th>
                        <th class="text-right">Credits</th>
                      </tr>
                    </thead>
                    <tbody>
                      <tr :for={r <- @retired_ships} class="opacity-60">
                        <td class="font-mono text-xs">{r.tick}</td>
                        <td class="font-semibold">{r.name}</td>
                        <td class="text-xs">{r.class}</td>
                        <td class="text-xs">{short_faction(r.faction_id)}</td>
                        <td class="text-xs">{r.final_location || "—"}</td>
                        <td class="text-xs">{r.crew_morale}</td>
                        <td class="text-right font-mono text-xs">{r.final_credits}</td>
                      </tr>
                    </tbody>
                  </table>
                </div>
              </div>
            </div>
          <% end %>
        </div>

        <%!-- Agent Inspector Drawer --%>
        <.inspector_drawer agent={@inspected_agent} history={@agent_history} />
      </div>
    </Layouts.dashboard>
    """
  end

  # --- Components ---

  # Universe positions for each star system (offset in the continuous map)
  # System positions loaded from WorldRegistry (no hardcoded map)

  defp continuous_map(assigns) do
    ~H"""
    <svg viewBox="-20 -20 40 40" class="w-full h-[500px] bg-base-300 rounded-lg">
      <%!-- Unified chunk grid overlay --%>
      <%= if @show_chunks do %>
        <%!-- Red base covers everything --%>
        <rect x="-500" y="-500" width="1000" height="1000" fill={divisor_color(50)} opacity="0.2" />
        <%!-- Only render non-red chunks on top --%>
        <%= for {{col, row}, divisor} <- @chunk_grid, divisor < 50 do %>
          <rect
            x={-500.0 + col * 10.0}
            y={-500.0 + row * 10.0}
            width="10.0"
            height="10.0"
            fill={divisor_color(divisor)}
            opacity="0.2"
          />
        <% end %>
        <%!-- Observer circle --%>
        <circle
          :for={obs <- @observers}
          cx={obs.x}
          cy={obs.y}
          r={obs.radius}
          fill="none"
          stroke="#22d3ee"
          stroke-width="0.05"
          stroke-dasharray="0.15 0.1"
          opacity="0.6"
        />
      <% end %>
      <%!-- Render each star system --%>
      <%= for {system_id, sys} <- @all_systems do %>
        <% {ox, oy} = system_offset(system_id) %>
        <%!-- System connection lines --%>
        <%!-- Connection lines to other systems (avoid drawing duplicates) --%>
        <%= for {other_id, other_sys} <- @all_systems, other_id > system_id do %>
          <% {ox2, oy2} = system_offset(other_id) %>
          <line
            x1={ox}
            y1={oy}
            x2={ox2}
            y2={oy2}
            stroke="currentColor"
            stroke-opacity="0.06"
            stroke-width="0.05"
            stroke-dasharray="0.3 0.2"
          />
        <% end %>
        <%!-- Orbit rings --%>
        <circle
          :for={{_id, body} <- sys.bodies}
          cx={ox}
          cy={oy}
          r={body.radius}
          fill="none"
          stroke="currentColor"
          stroke-opacity="0.1"
          stroke-width="0.02"
        />
        <%!-- Star --%>
        <circle cx={ox} cy={oy} r="0.15" fill={sys.star_color} />
        <%!-- System label --%>
        <text
          x={ox}
          y={oy - 3.2}
          text-anchor="middle"
          fill="currentColor"
          font-size="0.35"
          opacity="0.4"
        >
          {sys.name}
        </text>
        <%!-- Bodies --%>
        <circle
          :for={{id, body} <- sys.bodies}
          cx={ox + body.x}
          cy={oy + body.y}
          r="0.12"
          fill={body_color(id)}
        />
        <text
          :for={{_id, body} <- sys.bodies}
          x={ox + body.x}
          y={oy + body.y - 0.2}
          text-anchor="middle"
          fill="currentColor"
          font-size="0.22"
          opacity="0.7"
        >
          {body.name}
        </text>
      <% end %>
      <%!-- Ships (all systems — uses universe-wide body map for inter-system transit) --%>
      <% universe_bodies = universe_body_positions(@all_systems) %>
      <%= for ship <- @ships do %>
        <% pos = universe_ship_position(ship, universe_bodies, @tick) %>
        <%= if pos do %>
          <%!-- Transit trail --%>
          <%= if ship.transit do %>
            <% {fx, fy} = universe_location_position(ship.transit.from, universe_bodies) %>
            <% {tx, ty} = universe_location_position(ship.transit.to, universe_bodies) %>
            <line
              x1={fx}
              y1={fy}
              x2={tx}
              y2={ty}
              stroke="#22d3ee"
              stroke-opacity="0.15"
              stroke-width="0.02"
              stroke-dasharray="0.08 0.06"
            />
          <% end %>
          <circle cx={elem(pos, 0)} cy={elem(pos, 1)} r="0.06" fill="#22d3ee" opacity="0.8" />
        <% end %>
      <% end %>
    </svg>
    """
  end

  defp market_panel(assigns) do
    tiers = Simulator.Economy.Commodities.tiers()
    assigns = assign(assigns, :tiers, tiers)

    ~H"""
    <div class="overflow-x-auto max-h-96 space-y-3">
      <%= for {tier, commodities} <- @tiers do %>
        <div>
          <div class="text-xs font-bold uppercase tracking-wider text-base-content/40 mb-1 px-1">
            {tier}
          </div>
          <table class="table table-xs">
            <thead>
              <tr>
                <th class="w-24">Location</th>
                <th :for={c <- commodities} class="text-right text-xs">{format_commodity(c)}</th>
              </tr>
            </thead>
            <tbody>
              <%= for market <- @markets do %>
                <tr class="border-b-0">
                  <td class="font-semibold pb-0 text-xs">{short_location(market.facility_id)}</td>
                  <td :for={c <- commodities} class="text-right font-mono pb-0 text-xs">
                    <%= if Map.get(market.prices, c) do %>
                      <span class="text-base-content/40">$</span>{format_price(market.prices, c)}
                    <% else %>
                      <span class="text-base-content/20">—</span>
                    <% end %>
                  </td>
                </tr>
                <tr>
                  <td class="pt-0"></td>
                  <td
                    :for={c <- commodities}
                    class="text-right font-mono text-xs text-base-content/50 pt-0"
                  >
                    <%= if Map.get(market.supply, c, 0) > 0 do %>
                      {format_int(market.supply, c)}
                    <% else %>
                      <span class="text-base-content/20">0</span>
                    <% end %>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      <% end %>
    </div>
    """
  end

  defp fleet_panel(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <table class="table table-xs">
        <thead>
          <tr>
            <th>Ship</th>
            <th class="text-xs">Faction</th>
            <th>Location</th>
            <th class="text-right">Credits</th>
            <th class="text-right">Fuel</th>
            <th>Plan</th>
          </tr>
        </thead>
        <tbody>
          <tr
            :for={ship <- @ships}
            phx-click="inspect_agent"
            phx-value-id={ship.id}
            class="cursor-pointer hover:bg-base-200"
          >
            <td class="font-semibold">{ship.name}</td>
            <td class="text-xs opacity-60">{short_faction(ship[:faction_id])}</td>
            <td>
              {cond do
                ship.location -> ship.location
                ship.transit -> "→ #{ship.transit.to}"
                true -> "—"
              end}
            </td>
            <td class="text-right font-mono">{format_number(ship.credits)}</td>
            <td class="text-right font-mono">{Float.round(ship.fuel, 1)}</td>
            <td class="text-xs opacity-70">
              {Map.get(ship, :current_goal) || "—"}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp facilities_panel(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <table class="table table-xs">
        <thead>
          <tr>
            <th>Facility</th>
            <th class="text-right">Docked</th>
            <th class="text-right">Condition</th>
            <th class="text-right">Credits</th>
          </tr>
        </thead>
        <tbody>
          <tr
            :for={facility <- @facilities}
            phx-click="inspect_agent"
            phx-value-id={facility.id}
            class="cursor-pointer hover:bg-base-200"
          >
            <td class="font-semibold">{facility.name}</td>
            <td class="text-right font-mono">
              {length(facility.docked_ships)}/{facility.docking_capacity}
            </td>
            <td class="text-right">
              <div
                class={[
                  "radial-progress text-xs",
                  cond do
                    facility.condition > 0.7 -> "text-success"
                    facility.condition > 0.3 -> "text-warning"
                    true -> "text-error"
                  end
                ]}
                style={"--value:#{round(facility.condition * 100)}; --size:1.5rem;"}
              >
              </div>
            </td>
            <td class="text-right font-mono">{facility.credits}</td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp contracts_panel(assigns) do
    ~H"""
    <div class="overflow-x-auto max-h-80">
      <table class="table table-xs">
        <thead>
          <tr>
            <th>Age</th>
            <th>Status</th>
            <th>Commodity</th>
            <th class="text-right">Qty</th>
            <th>Destination</th>
            <th>Source</th>
            <th class="text-right">Payment</th>
            <th>Requestor</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={c <- @contracts} class={contract_row_class(c.status)}>
            <td class="font-mono text-xs">{@tick - c.posted_at_tick}t</td>
            <td>
              <span class={[
                "badge badge-xs",
                case c.status do
                  "posted" -> "badge-info"
                  "accepted" -> "badge-warning"
                  s when s in ~w(picked_up in_transit) -> "badge-accent"
                  s when s in ~w(fulfilled completed paid) -> "badge-success"
                  _ -> "badge-ghost"
                end
              ]}>
                {c.status}
              </span>
            </td>
            <td class="text-xs">{c.commodity}</td>
            <td class="text-right font-mono text-xs">{c.quantity}</td>
            <td class="text-xs">{short_location(c.destination_location)}</td>
            <td class="text-xs">{short_location(c[:source_location])}</td>
            <td class="text-right font-mono text-xs">{format_number(c.payment)}</td>
            <td class="text-xs opacity-60">{short_id(c.requestor_id)}</td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp orders_panel(assigns) do
    ~H"""
    <div class="overflow-x-auto max-h-80">
      <table class="table table-xs">
        <thead>
          <tr>
            <th>Age</th>
            <th>Type</th>
            <th>Commodity</th>
            <th class="text-right">Qty</th>
            <th class="text-right">Price</th>
            <th>Location</th>
            <th>Agent</th>
          </tr>
        </thead>
        <tbody>
          <tr
            :for={o <- @orders}
            class={if o.type == :buy, do: "text-success/80", else: "text-error/80"}
          >
            <td class="font-mono text-xs">{@tick - o.placed_at_tick}t</td>
            <td>
              <span class={[
                "badge badge-xs",
                if(o.type == :buy, do: "badge-success", else: "badge-error")
              ]}>
                {o.type}
              </span>
            </td>
            <td class="text-xs">{o.commodity}</td>
            <td class="text-right font-mono text-xs">{o.quantity}</td>
            <td class="text-right font-mono text-xs">{Float.round(o.price * 1.0, 1)}</td>
            <td class="text-xs">{short_location(o.location)}</td>
            <td class="text-xs opacity-60">{short_id(o.agent_id)}</td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp contract_row_class("posted"), do: ""
  defp contract_row_class("accepted"), do: "opacity-70"
  defp contract_row_class(s) when s in ~w(picked_up in_transit), do: "opacity-60"
  defp contract_row_class(_), do: "opacity-40"

  defp short_id(nil), do: "—"
  defp short_id(id), do: id |> to_string() |> String.replace(~r/^(facility|ship|pop)-/, "")

  attr :page, :integer, required: true
  attr :total_pages, :integer, required: true
  attr :event, :string, required: true

  defp pagination(assigns) do
    ~H"""
    <div
      :if={@total_pages > 1}
      class="flex items-center justify-between mt-2 pt-2 border-t border-base-200"
    >
      <button
        phx-click={@event}
        phx-value-page={@page - 1}
        disabled={@page <= 1}
        class="btn btn-xs btn-ghost"
      >
        Prev
      </button>
      <span class="text-xs text-base-content/60 font-mono">
        {@page} / {@total_pages}
      </span>
      <button
        phx-click={@event}
        phx-value-page={@page + 1}
        disabled={@page >= @total_pages}
        class="btn btn-xs btn-ghost"
      >
        Next
      </button>
    </div>
    """
  end

  defp metrics_panel(assigns) do
    ~H"""
    <div class="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-6 gap-3">
      <.metric_card
        label="Tick Avg"
        value={format_us(@metrics.tick.avg_duration_us)}
        subtitle="dispatch time"
      />
      <.metric_card
        label="Tick P99"
        value={format_us(@metrics.tick.p99_duration_us)}
        subtitle="worst case"
      />
      <.metric_card
        label="Ticks/sec"
        value={Float.round(@metrics.tick.ticks_per_second * 1.0, 1)}
        subtitle="throughput"
      />
      <.metric_card
        label="Agents"
        value={@metrics.agents.total}
        subtitle={agent_breakdown(@metrics.agents.counts)}
      />
      <.metric_card
        label="Stalled"
        value={length(@metrics.agents.stalled)}
        subtitle="queue > 100"
        alert={@metrics.agents.stalled != []}
      />
      <.metric_card
        label="Flush"
        value={format_us(@metrics.persistence.last_flush_duration_us)}
        subtitle={"#{@metrics.persistence.dirty_count} dirty"}
      />
    </div>

    <%!-- Memory breakdown --%>
    <div class="mt-3">
      <h3 class="text-xs uppercase tracking-wider text-base-content/50 mb-1">Memory by Agent Type</h3>
      <div class="flex flex-wrap gap-2">
        <span
          :for={{type, mem} <- @metrics.agents.memory_by_type}
          class="badge badge-sm badge-outline font-mono"
        >
          {type}: {format_bytes(mem.total_bytes)}
        </span>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :subtitle, :string, default: ""
  attr :alert, :boolean, default: false

  defp metric_card(assigns) do
    ~H"""
    <div class={[
      "stat p-2 rounded-lg bg-base-200",
      @alert && "ring-2 ring-error"
    ]}>
      <div class="stat-title text-xs">{@label}</div>
      <div class="stat-value text-lg font-mono">{@value}</div>
      <div class="stat-desc text-xs">{@subtitle}</div>
    </div>
    """
  end

  defp event_log_panel(assigns) do
    ~H"""
    <div class="h-48 overflow-y-auto text-xs font-mono space-y-0.5">
      <div :if={@events == []} class="text-base-content/40 italic">No events yet...</div>
      <div :for={event <- @events} class="flex gap-2 py-0.5 border-b border-base-200">
        <span class="text-base-content/40 w-12 shrink-0">T{event.tick}</span>
        <span class={[
          "badge badge-xs shrink-0",
          event_badge_class(event.event)
        ]}>
          {event.event}
        </span>
        <span class="truncate">{event.summary}</span>
      </div>
    </div>
    """
  end

  defp event_badge_class(:shortage_alert), do: "badge-error"
  defp event_badge_class(:crew_complaint), do: "badge-warning"
  defp event_badge_class(:ship_arrived), do: "badge-info"
  defp event_badge_class(:ship_departed), do: "badge-info"
  defp event_badge_class(:trade_executed), do: "badge-success"
  defp event_badge_class(_), do: "badge-ghost"

  defp inspector_drawer(%{agent: nil} = assigns) do
    ~H"""
    """
  end

  defp inspector_drawer(assigns) do
    ~H"""
    <div class="fixed inset-y-0 right-0 w-96 bg-base-100 shadow-2xl z-50 overflow-y-auto border-l border-base-300">
      <div class="p-4">
        <div class="flex items-center justify-between mb-4">
          <h2 class="text-lg font-bold">{@agent[:name] || @agent[:label] || @agent[:id]}</h2>
          <button phx-click="close_inspector" class="btn btn-sm btn-ghost">✕</button>
        </div>

        <div class="badge badge-primary mb-3">{@agent[:__agent_type__]}</div>

        <div class="space-y-3">
          <.inspector_section
            :for={{section, fields} <- inspector_sections(@agent)}
            title={section}
            fields={fields}
          />
          <%!-- Docked ships for facilities --%>
          <%= if @agent[:docked_ships] && @agent[:docked_ships] != [] do %>
            <div class="collapse collapse-open bg-base-200 rounded-lg">
              <div class="collapse-title text-xs font-bold uppercase tracking-wider py-2 min-h-0">
                Docked Ships ({"#{length(@agent.docked_ships)}"})
              </div>
              <div class="collapse-content text-xs">
                <div
                  :for={ship_id <- @agent.docked_ships}
                  phx-click="inspect_agent"
                  phx-value-id={ship_id}
                  class="flex items-center justify-between py-1 border-b border-base-300 cursor-pointer hover:bg-base-300 px-1 rounded"
                >
                  <span class="font-mono text-info">{ship_id}</span>
                  <span class="text-base-content/40">&rarr;</span>
                </div>
              </div>
            </div>
          <% end %>
          <%!-- Crew complement summary --%>
          <%= if @agent[:crew] do %>
            <% crew = @agent.crew %>
            <div class="collapse collapse-open bg-base-200 rounded-lg">
              <div class="collapse-title text-xs font-bold uppercase tracking-wider py-2 min-h-0">
                Crew ({"#{crew.size}"} members)
              </div>
              <div class="collapse-content text-xs font-mono">
                <div class="flex justify-between py-0.5 border-b border-base-300">
                  <span class="text-base-content/60">hunger</span>
                  <span>{"#{round(crew.hunger)}"}</span>
                </div>
                <div class="flex justify-between py-0.5 border-b border-base-300">
                  <span class="text-base-content/60">fatigue</span>
                  <span>{"#{round(crew.fatigue)}"}</span>
                </div>
                <div class="flex justify-between py-0.5 border-b border-base-300">
                  <span class="text-base-content/60">morale</span>
                  <span>{"#{round(crew.morale)}"}</span>
                </div>
                <div class="flex justify-between py-0.5 border-b border-base-300">
                  <span class="text-base-content/60">health</span>
                  <span>{"#{round(crew.health)}"}</span>
                </div>
                <div class="flex justify-between py-0.5 border-b border-base-300">
                  <span class="text-base-content/60">task</span>
                  <span>{crew.current_task}</span>
                </div>
                <div class="flex justify-between py-0.5">
                  <span class="text-base-content/60">roles</span>
                  <span>{Enum.join(crew.roles, ", ")}</span>
                </div>
              </div>
            </div>
          <% end %>
          <%!-- Activity History (loaded on click, not every refresh) --%>
          <div class="collapse collapse-open bg-base-200 rounded-lg">
            <div class="collapse-title text-xs font-bold uppercase tracking-wider py-2 min-h-0">
              Recent Activity
            </div>
            <div class="collapse-content text-xs space-y-1">
              <%= if @history == [] do %>
                <div class="py-1 text-base-content/40 italic">No recent activity</div>
              <% else %>
                <div :for={evt <- @history} class="py-1 border-b border-base-300 last:border-0">
                  <span class="badge badge-xs badge-outline mr-1">{evt.event}</span>
                  <span class="text-base-content/60">{event_summary(evt.event, evt.payload)}</span>
                </div>
              <% end %>
            </div>
          </div>
          <%!-- Back to parent for crew members --%>
          <%= if @agent[:assigned_to] do %>
            <button
              phx-click="inspect_agent"
              phx-value-id={@agent.assigned_to}
              class="btn btn-xs btn-ghost w-full mt-2"
            >
              &larr; Back to {@agent.assigned_to}
            </button>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :fields, :list, required: true

  defp inspector_section(assigns) do
    ~H"""
    <div class="collapse collapse-open bg-base-200 rounded-lg">
      <div class="collapse-title text-xs font-bold uppercase tracking-wider py-2 min-h-0">
        {@title}
      </div>
      <div class="collapse-content text-xs font-mono">
        <div
          :for={{key, value} <- @fields}
          class="flex justify-between py-0.5 border-b border-base-300"
        >
          <span class="text-base-content/60">{key}</span>
          <span class="text-right max-w-48 truncate">{format_value(value)}</span>
        </div>
      </div>
    </div>
    """
  end

  # --- Helpers ---

  defp build_event_log do
    Events.recent_log(50)
    |> Enum.map(fn %{event: event, payload: payload, timestamp: ts} ->
      %{
        tick: Map.get(payload, :tick, 0),
        event: event,
        summary: event_summary(event, payload),
        timestamp: ts
      }
    end)
  end

  defp event_summary(:ship_arrived, p), do: "#{p[:ship_id]} arrived at #{p[:location]}"
  defp event_summary(:ship_departed, p), do: "#{p[:ship_id]} departed #{p[:from]} → #{p[:to]}"

  defp event_summary(:trade_executed, p),
    do: "#{p[:buyer_id]} bought #{p[:quantity]} #{p[:commodity]}"

  defp event_summary(:shortage_alert, p), do: "SHORTAGE: #{p[:commodity]} at #{p[:facility_id]}"

  defp event_summary(:ship_decommissioned, p),
    do: "#{p[:name]} decommissioned → #{p[:new_location]}"

  defp event_summary(:goal_changed, p),
    do: "#{p[:name]} goal: #{p[:from_goal]} → #{p[:to_goal]}"

  defp event_summary(:contract_accepted, p),
    do: "accepted #{p[:commodity]} contract → #{p[:destination]}"

  defp event_summary(:construction_started, p),
    do: "#{p[:facility_type]} construction at #{p[:location]}"

  defp event_summary(:facility_constructed, p),
    do: "#{p[:facility_name]} built at #{p[:location]}"

  defp event_summary(:facility_abandoned, p),
    do: "#{p[:name]} abandoned at #{p[:location]}"

  defp event_summary(:input_shortage, p),
    do: "#{p[:facility_name]} needs #{p[:commodity]} at #{p[:location]}"

  defp event_summary(event, _p), do: to_string(event)

  defp refresh_inspector(%{assigns: %{inspected_agent: nil}} = socket), do: socket

  defp refresh_inspector(%{assigns: %{inspected_agent: agent}} = socket) do
    case fetch_agent_state(agent[:id] || agent[:__agent_id__]) do
      nil -> assign(socket, :inspected_agent, nil)
      updated -> assign(socket, :inspected_agent, updated)
    end
  end

  defp fetch_agent_state(nil), do: nil

  defp fetch_agent_state(agent_id) do
    case Simulator.Agents.Agent.whereis(agent_id) do
      {:ok, pid} ->
        try do
          GenServer.call(pid, :get_state, 2_000)
        catch
          :exit, _ -> nil
        end

      :error ->
        nil
    end
  end

  @skip_keys ~w(__agent_id__ __agent_type__ __db_id__)a

  defp inspector_sections(agent) when is_map(agent) do
    type = Map.get(agent, :__agent_type__, :unknown)
    fields = Map.drop(agent, @skip_keys)

    case type do
      :ship -> ship_sections(fields)
      :crew -> crew_sections(fields)
      :market -> market_sections(fields)
      :facility -> facility_sections(fields)
      :population -> pop_sections(fields)
      _ -> [{"State", Map.to_list(fields)}]
    end
  end

  defp ship_sections(f) do
    personality = Map.get(f, :personality, %{})

    [
      {"Identity",
       [{:id, f.id}, {:name, f.name}, {:class, f.class}, {:faction, f[:faction_id] || "—"}]},
      {"Location",
       [
         {:location, f.location || "In transit"},
         {:docked_at, f.docked_at || "—"},
         {:transit, inspect_transit(f.transit)}
       ]},
      {"Cargo & Finance",
       [
         {:credits, f.credits},
         {:fuel, Float.round(f.fuel, 1)},
         {:efficiency, Float.round(f.efficiency, 2)},
         {:cargo, f.cargo}
       ]},
      {"AI",
       [
         {:goal, f[:current_goal] || "—"},
         {:bt_step,
          if(f[:current_bt],
            do: Simulator.AI.BehaviorTree.current_action(f.current_bt),
            else: "—"
          )},
         {:tick_divisor, Simulator.Spatial.ChunkManager.tick_divisor_for(f.id)}
       ]},
      {"Personality",
       personality
       |> Enum.filter(fn {_axis, weight} -> is_number(weight) end)
       |> Enum.map(fn {axis, weight} -> {axis, Float.round(weight * 1.0, 2)} end)},
      {"Reputation",
       Enum.map(Map.get(f, :faction_reputation, %{}), fn {faction, rep} ->
         tier = Simulator.Economy.Reputation.tier(rep)
         {String.to_atom(faction), "#{rep} (#{tier})"}
       end)}
    ]
  end

  defp crew_sections(f) do
    personality = Map.get(f, :personality, %{})

    [
      {"Identity",
       [{:id, f.id}, {:name, f.name}, {:role, f.role}, {:assigned_to, f.assigned_to}]},
      {"Needs",
       [{:hunger, f.hunger}, {:fatigue, f.fatigue}, {:morale, f.morale}, {:health, f.health}]},
      {"Task", [{:current_task, f.current_task}]},
      {"Skills", Map.to_list(f.skills)},
      {"Personality",
       personality
       |> Enum.filter(fn {_axis, weight} -> is_number(weight) end)
       |> Enum.map(fn {axis, weight} -> {axis, Float.round(weight * 1.0, 2)} end)},
      {"Contract",
       [
         {:pay_owed, f.pay_owed},
         {:contract_expires, f.contract_expires_tick},
         {:home, f.home_location}
       ]}
    ]
  end

  defp market_sections(f) do
    [
      {"Identity", [{:id, f.id}, {:facility_id, f.facility_id}]},
      {"Prices", Map.to_list(f.prices)},
      {"Supply", Map.to_list(f.supply)},
      {"Demand", Map.to_list(f.demand)},
      {"Config", [{:elasticity, f.price_elasticity}, {:spread, f.spread}]},
      {"Orders",
       [
         {:pending_buys, length(f.pending_buy_orders)},
         {:pending_sells, length(f.pending_sell_orders)}
       ]}
    ]
  end

  defp facility_sections(f) do
    [
      {"Identity",
       [{:id, f.id}, {:name, f.name}, {:type, f.type}, {:faction, f[:faction_id] || "—"}]},
      {"Docking",
       [
         {:capacity, f.docking_capacity},
         {:docked, length(f.docked_ships)}
       ]},
      {"Status",
       [
         {:condition, Float.round(f.condition, 3)},
         {:reputation, f.reputation},
         {:credits, f.credits}
       ]},
      {"Reserves", Map.to_list(f.reserves)}
    ]
  end

  defp pop_sections(f) do
    [
      {"Identity", [{:id, f.id}, {:label, f.label}, {:demographic, f.demographic}]},
      {"Population", [{:count, f.population_count}, {:growth_rate, f.growth_rate}]},
      {"Sentiment",
       [
         {:overall, f.overall_sentiment},
         {:unrest, f.unrest},
         {:migration_pressure, f.migration_pressure}
       ]},
      {"Economy", [{:wealth, f.total_wealth}, {:food_satisfaction, f.food_satisfaction}]}
    ]
  end

  defp inspect_transit(nil), do: "—"
  defp inspect_transit(t), do: "#{t.from} → #{t.to}"

  defp format_value(value) when is_map(value), do: inspect(value, pretty: true, limit: 5)
  defp format_value(value) when is_list(value), do: Enum.join(value, ", ")
  defp format_value(nil), do: "—"
  defp format_value(value), do: to_string(value)

  @per_page 20

  defp assign_simulation_data(socket) do
    all_ships = Queries.all_ships() |> Enum.sort_by(& &1.name)
    all_facilities = Queries.all_facilities() |> Enum.sort_by(& &1.name)

    fleet_page = socket.assigns[:fleet_page] || 1
    facilities_page = socket.assigns[:facilities_page] || 1

    fleet_total_pages = max(ceil(length(all_ships) / @per_page), 1)
    facilities_total_pages = max(ceil(length(all_facilities) / @per_page), 1)

    # Clamp pages to valid range
    fleet_page = max(1, min(fleet_page, fleet_total_pages))
    facilities_page = max(1, min(facilities_page, facilities_total_pages))

    ships_page = all_ships |> Enum.drop((fleet_page - 1) * @per_page) |> Enum.take(@per_page)

    facilities_page_data =
      all_facilities |> Enum.drop((facilities_page - 1) * @per_page) |> Enum.take(@per_page)

    # Contracts — paginated, oldest first, optionally filtered
    all_contracts = Simulator.Economy.ContractBoard.all_contracts()

    show_completed = socket.assigns[:contracts_show_completed] || false

    filtered_contracts =
      if show_completed do
        all_contracts
      else
        Enum.filter(all_contracts, &(&1.status in ~w(posted accepted picked_up in_transit)))
      end

    contracts_page = socket.assigns[:contracts_page] || 1
    contracts_total_pages = max(ceil(length(filtered_contracts) / @per_page), 1)
    contracts_page = max(1, min(contracts_page, contracts_total_pages))

    contracts_page_data =
      filtered_contracts |> Enum.drop((contracts_page - 1) * @per_page) |> Enum.take(@per_page)

    # Market orders — paginated, oldest first
    all_orders = Queries.all_market_orders()
    orders_page = socket.assigns[:orders_page] || 1
    orders_total_pages = max(ceil(length(all_orders) / @per_page), 1)
    orders_page = max(1, min(orders_page, orders_total_pages))

    orders_page_data =
      all_orders |> Enum.drop((orders_page - 1) * @per_page) |> Enum.take(@per_page)

    socket
    |> assign(:all_ships, all_ships)
    |> assign(:ships, ships_page)
    |> assign(:ships_total, length(all_ships))
    |> assign(:fleet_page, fleet_page)
    |> assign(:fleet_total_pages, fleet_total_pages)
    |> assign(:facilities, facilities_page_data)
    |> assign(:facilities_total, length(all_facilities))
    |> assign(:facilities_page, facilities_page)
    |> assign(:facilities_total_pages, facilities_total_pages)
    |> assign(:markets, Queries.all_markets())
    |> assign(:contracts, contracts_page_data)
    |> assign(:contracts_total, length(filtered_contracts))
    |> assign(:contracts_page, contracts_page)
    |> assign(:contracts_total_pages, contracts_total_pages)
    |> assign(:orders, orders_page_data)
    |> assign(:orders_total, length(all_orders))
    |> assign(:orders_page, orders_page)
    |> assign(:orders_total_pages, orders_total_pages)
  end

  defp system_offset(system_id) do
    Simulator.World.Registry.universe_offset(system_id)
  end

  # Build a single body position map across all systems in universe coordinates.
  # Keys are body_id strings, values are {x, y} with system offsets applied.
  defp universe_body_positions(all_systems) do
    Enum.reduce(all_systems, %{}, fn {system_id, sys}, acc ->
      {ox, oy} = system_offset(system_id)

      Enum.reduce(sys.bodies, acc, fn {body_id, body}, inner ->
        Map.put(inner, body_id, %{x: ox + body.x, y: oy + body.y, name: body.name})
      end)
    end)
  end

  # Ship position in universe coordinates — works for inter-system transit.
  defp universe_ship_position(ship, universe_bodies, tick) do
    cond do
      is_binary(ship.location) ->
        {x, y} = universe_location_position(ship.location, universe_bodies)

        if x == 0.0 and y == 0.0 do
          nil
        else
          {x + 0.2, y}
        end

      ship.transit != nil ->
        {from_x, from_y} = universe_location_position(ship.transit.from, universe_bodies)
        {to_x, to_y} = universe_location_position(ship.transit.to, universe_bodies)

        duration = max(ship.transit.arrival_tick - ship.transit.departure_tick, 1)
        elapsed = tick - ship.transit.departure_tick
        t = min(max(elapsed / duration, 0.0), 1.0)

        {from_x + (to_x - from_x) * t, from_y + (to_y - from_y) * t}

      true ->
        nil
    end
  end

  # Resolve a location name to universe {x, y} via body lookup.
  defp universe_location_position(location, universe_bodies) do
    case location_body_id(location) do
      nil ->
        {0.0, 0.0}

      body_id ->
        case Map.get(universe_bodies, body_id) do
          %{x: x, y: y} -> {x, y}
          _ -> {0.0, 0.0}
        end
    end
  end

  defp assign_all_systems(socket) do
    systems =
      for system_id <- Simulator.World.Registry.system_ids(), into: %{} do
        case Simulator.Agents.Agent.whereis(system_id) do
          {:ok, pid} ->
            state = Simulator.World.System.get_state(pid)

            bodies =
              Map.new(state.bodies, fn {id, body} ->
                {id,
                 %{
                   name: body.name,
                   radius: body.orbit_radius,
                   x: body.orbit_radius * :math.cos(body.current_angle * :math.pi() / 180),
                   y: body.orbit_radius * :math.sin(body.current_angle * :math.pi() / 180)
                 }}
              end)

            star_color = system_star_color(system_id)

            {system_id,
             %{
               name: state.name,
               bodies: bodies,
               star_color: star_color
             }}

          :error ->
            {system_id, %{name: system_id, bodies: %{}, star_color: "#6b7280"}}
        end
      end

    socket
    |> assign(:all_systems, systems)
    |> assign(:chunk_grid, Simulator.Spatial.ChunkManager.get_chunk_grid())
  end

  defp observer_radius(observers) do
    case Enum.find(observers, &(&1.id == "default")) do
      %{radius: r} -> r
      _ -> 5.0
    end
  end

  defp divisor_color(1), do: "#22c55e"
  defp divisor_color(d) when d <= 5, do: "#84cc16"
  defp divisor_color(d) when d <= 15, do: "#eab308"
  defp divisor_color(d) when d <= 30, do: "#f97316"
  defp divisor_color(_), do: "#ef4444"

  defp body_color("earth"), do: "#3b82f6"
  defp body_color("mars"), do: "#ef4444"
  defp body_color("belt"), do: "#a3a3a3"
  defp body_color(_), do: "#6b7280"

  # Uses WorldRegistry for location→body resolution (no hardcoded map)

  # Star colors — could come from faction data eventually
  defp system_star_color("system-sol"), do: "#f59e0b"
  defp system_star_color("system-alpha-centauri"), do: "#f472b6"
  defp system_star_color("system-tau-ceti"), do: "#facc15"
  defp system_star_color(_), do: "#6b7280"

  defp location_body_id(location) do
    Simulator.World.Registry.body_id_for_location(location)
  end

  defp short_faction(nil), do: "—"
  defp short_faction("terran-authority"), do: "Terran"
  defp short_faction("mars-syndicate"), do: "Mars"
  defp short_faction("belt-coalition"), do: "Belt"
  defp short_faction("frontier-ventures"), do: "Frontier"
  defp short_faction("crucible-mining"), do: "Crucible"
  defp short_faction("independent"), do: "Indie"
  defp short_faction(id), do: id

  defp format_commodity(c) do
    c |> to_string() |> String.capitalize() |> String.slice(0..5)
  end

  defp format_price(prices, commodity) do
    case Map.get(prices, commodity) || Map.get(prices, to_string(commodity)) do
      nil -> "—"
      price -> :erlang.float_to_binary(price / 1, decimals: 1)
    end
  end

  defp format_int(map, key) do
    case Map.get(map, key) || Map.get(map, to_string(key)) do
      nil -> "—"
      val -> Integer.to_string(round(val))
    end
  end

  defp format_us(us) when is_number(us) and us >= 1000, do: "#{Float.round(us / 1000, 1)}ms"
  defp format_us(us) when is_number(us), do: "#{round(us)}µs"
  defp format_us(_), do: "—"

  defp format_bytes(bytes) when bytes >= 1_048_576, do: "#{Float.round(bytes / 1_048_576, 1)}MB"
  defp format_bytes(bytes) when bytes >= 1024, do: "#{Float.round(bytes / 1024, 1)}KB"
  defp format_bytes(bytes), do: "#{bytes}B"

  defp agent_breakdown(counts) do
    Enum.map_join(counts, ", ", fn {type, count} -> "#{count} #{type}" end)
  end

  defp short_location(nil), do: "—"

  defp short_location(facility_id) do
    facility_id
    |> to_string()
    |> String.replace("-station", "")
    |> String.replace("-outpost", "")
    |> String.capitalize()
  end

  defp format_number(n) when is_integer(n) and n >= 1_000_000,
    do: "#{Float.round(n / 1_000_000, 1)}M"

  defp format_number(n) when is_integer(n) and n >= 1_000, do: "#{Float.round(n / 1_000, 1)}K"
  defp format_number(n) when is_number(n), do: to_string(n)
  defp format_number(n), do: inspect(n)
end
