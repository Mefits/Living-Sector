defmodule SimulatorWeb.AdminController do
  @moduledoc """
  God-mode mutations for the Godot client.

  These endpoints spawn / destroy agents and poke at market state
  directly. They're deliberately thin — all business logic lives in
  `Simulator.Admin`. The controller's job is to decode params,
  translate errors to JSON status codes, and return the result.

      POST   /api/admin/ships                      — create ship
      DELETE /api/admin/ships/:id                  — destroy ship
      POST   /api/admin/facilities                 — create facility
      DELETE /api/admin/facilities/:id             — destroy facility
      POST   /api/admin/markets/:location/supply   — adjust commodity supply
      POST   /api/admin/save                       — flush dirty agents + WAL checkpoint
      POST   /api/admin/save-as                    — save + copy DB to a named slot
      GET    /api/admin/saves                      — list save files in the DB dir

  No auth: the Endpoint binds loopback only by default, so the admin
  surface isn't reachable off-box unless you opted into BIND_IP=0.0.0.0.
  """

  use SimulatorWeb, :controller

  alias Simulator.Admin

  # --- Ships ---

  def create_ship(conn, params) do
    case Admin.create_ship(params) do
      {:ok, ship} ->
        conn
        |> put_status(:created)
        |> json(ship)

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: format_error(reason)})
    end
  end

  def destroy_ship(conn, %{"id" => ship_id}) do
    case Admin.destroy_ship(ship_id) do
      :ok ->
        send_resp(conn, :no_content, "")

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "ship not found"})
    end
  end

  # --- Facilities ---

  def create_facility(conn, params) do
    case Admin.create_facility(params) do
      {:ok, facility} ->
        conn
        |> put_status(:created)
        |> json(facility)

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: format_error(reason)})
    end
  end

  def destroy_facility(conn, %{"id" => facility_id}) do
    case Admin.destroy_facility(facility_id) do
      :ok ->
        send_resp(conn, :no_content, "")

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "facility not found"})
    end
  end

  # --- Markets ---

  def adjust_supply(conn, %{"location" => location} = params) do
    with {:ok, commodity} <- fetch_string(params, "commodity"),
         {:ok, delta} <- fetch_number(params, "delta") do
      case Admin.adjust_supply(location, commodity, delta) do
        :ok ->
          send_resp(conn, :no_content, "")

        {:error, :not_found} ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "market not found at #{location}"})
      end
    else
      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: format_error(reason)})
    end
  end

  # --- Save games ---

  def save(conn, _params) do
    {:ok, result} = Admin.save()

    conn
    |> put_status(:ok)
    |> json(Map.put(result, :status, "saved"))
  end

  def save_as(conn, params) do
    with {:ok, name} <- fetch_string(params, "name") do
      case Admin.save_as(name) do
        {:ok, save} ->
          conn
          |> put_status(:created)
          |> json(save)

        {:error, reason} ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: format_error(reason)})
      end
    else
      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: format_error(reason)})
    end
  end

  def list_saves(conn, _params) do
    {:ok, saves} = Admin.list_saves()

    conn
    |> put_status(:ok)
    |> json(%{saves: saves})
  end

  # --- Helpers ---

  defp fetch_string(params, key) do
    case params[key] do
      v when is_binary(v) and v != "" -> {:ok, v}
      _ -> {:error, {:missing_param, key}}
    end
  end

  defp fetch_number(params, key) do
    case params[key] do
      n when is_number(n) ->
        {:ok, n}

      n when is_binary(n) ->
        case Float.parse(n) do
          {f, _} -> {:ok, f}
          _ -> {:error, {:bad_param, key}}
        end

      _ ->
        {:error, {:missing_param, key}}
    end
  end

  defp format_error({:missing_param, key}), do: "missing param: #{key}"
  defp format_error({:bad_param, key}), do: "bad param: #{key}"
  defp format_error({:unknown_ship_class, v}), do: "unknown ship class: #{inspect(v)}"
  defp format_error({:unknown_facility_type, v}), do: "unknown facility type: #{inspect(v)}"
  defp format_error({:unknown_location, v}), do: "unknown location: #{inspect(v)}"
  defp format_error({:unknown_body, v}), do: "unknown body: #{inspect(v)}"
  defp format_error(:invalid_name), do: "invalid save name"
  defp format_error(:cannot_overwrite_active_save), do: "cannot overwrite the active save"
  defp format_error(other), do: inspect(other)
end
