defmodule SimulatorWeb.Router do
  use SimulatorWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SimulatorWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", SimulatorWeb do
    pipe_through :browser

    live "/", DashboardLive
    live "/dashboard", DashboardLive
  end

  scope "/api", SimulatorWeb do
    pipe_through :api

    get "/health", ApiController, :health
    get "/report", ApiController, :report
    get "/markets", ApiController, :markets
    get "/ships", ApiController, :ships
    get "/facilities", ApiController, :facilities
    get "/populations", ApiController, :populations
    get "/factions", ApiController, :factions
    get "/positions", ApiController, :positions
    get "/agent/:id", ApiController, :agent

    post "/sim/pause", ApiController, :pause
    post "/sim/resume", ApiController, :resume
    post "/sim/speed", ApiController, :speed

    # God-mode mutations for the Godot client. Loopback-only by default.
    post "/admin/ships", AdminController, :create_ship
    delete "/admin/ships/:id", AdminController, :destroy_ship
    post "/admin/facilities", AdminController, :create_facility
    delete "/admin/facilities/:id", AdminController, :destroy_facility
    post "/admin/markets/:location/supply", AdminController, :adjust_supply

    # Save-game plumbing: force-flush, copy-to-named-slot, list-saves.
    post "/admin/save", AdminController, :save
    post "/admin/save-as", AdminController, :save_as
    get "/admin/saves", AdminController, :list_saves
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:simulator, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: SimulatorWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
