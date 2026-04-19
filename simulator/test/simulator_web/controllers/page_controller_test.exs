defmodule SimulatorWeb.PageControllerTest do
  use SimulatorWeb.ConnCase

  test "GET / renders dashboard", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Mission Control"
  end
end
