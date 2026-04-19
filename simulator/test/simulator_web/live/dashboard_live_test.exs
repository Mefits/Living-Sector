defmodule SimulatorWeb.DashboardLiveTest do
  use SimulatorWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  describe "dashboard" do
    test "renders the dashboard page", %{conn: conn} do
      {:ok, view, html} = live(conn, "/dashboard")

      assert html =~ "Mission Control"
      assert html =~ "Star Map"
      assert html =~ "Markets"
      assert html =~ "Fleet"
      assert has_element?(view, "button", "Play") or has_element?(view, "button", "Pause")
    end

    test "shows tick counter", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/dashboard")

      assert html =~ "TICK"
    end
  end
end
