defmodule SimulatorWeb.PageController do
  use SimulatorWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
