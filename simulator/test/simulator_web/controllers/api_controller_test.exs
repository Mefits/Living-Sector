defmodule SimulatorWeb.ApiControllerTest do
  use SimulatorWeb.ConnCase, async: false

  describe "GET /api/health" do
    test "returns ok status", %{conn: conn} do
      conn = get(conn, "/api/health")
      body = json_response(conn, 200)
      assert body["status"] in ["ok", "problems"]
    end
  end

  describe "GET /api/report" do
    test "returns full simulation report", %{conn: conn} do
      conn = get(conn, "/api/report")
      body = json_response(conn, 200)

      assert is_integer(body["tick"])
      assert is_boolean(body["running"])
      assert is_list(body["markets"])
      assert is_list(body["ships"])
      assert is_list(body["facilities"])
      assert is_map(body["metrics"])
    end
  end

  describe "GET /api/markets" do
    test "returns market data", %{conn: conn} do
      conn = get(conn, "/api/markets")
      body = json_response(conn, 200)

      assert is_list(body["data"])
    end
  end

  describe "GET /api/ships" do
    test "returns ship data", %{conn: conn} do
      conn = get(conn, "/api/ships")
      body = json_response(conn, 200)

      assert is_list(body["data"])
    end
  end

  describe "GET /api/agent/:id" do
    test "returns 404 for unknown agent", %{conn: conn} do
      conn = get(conn, "/api/agent/nonexistent")
      body = json_response(conn, 404)

      assert body["error"] == "agent_not_found"
    end
  end

  describe "POST /api/sim/pause" do
    test "pauses the simulation", %{conn: conn} do
      conn = post(conn, "/api/sim/pause")
      body = json_response(conn, 200)

      assert body["status"] == "paused"
    end
  end

  describe "POST /api/sim/resume" do
    test "resumes the simulation", %{conn: conn} do
      conn = post(conn, "/api/sim/resume")
      body = json_response(conn, 200)

      assert body["status"] == "running"
    end
  end

  describe "POST /api/sim/speed" do
    test "sets tick speed", %{conn: conn} do
      conn = post(conn, "/api/sim/speed", %{interval_ms: 500})
      body = json_response(conn, 200)

      assert body["status"] == "speed_set"
      assert body["interval_ms"] == 500
    end

    test "rejects invalid speed", %{conn: conn} do
      conn = post(conn, "/api/sim/speed", %{interval_ms: "fast"})
      assert json_response(conn, 400)["error"]
    end
  end
end
