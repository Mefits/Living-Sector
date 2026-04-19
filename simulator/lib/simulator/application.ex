defmodule Simulator.Application do
  @moduledoc """
  OTP Application entry point for the space simulation engine.

  Starts the supervision tree including infrastructure (Repo, PubSub, Endpoint)
  and simulation-specific processes (AgentRegistry, AgentSupervisor, TickCoordinator).
  """

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        SimulatorWeb.Telemetry,
        Simulator.Repo,
        {Ecto.Migrator, repos: Application.fetch_env!(:simulator, :ecto_repos)},
        {DNSCluster, query: Application.get_env(:simulator, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Simulator.PubSub},

        # World data registry (loads from DB)
        Simulator.World.Registry,

        # Simulation infrastructure
        {Registry, keys: :duplicate, name: Simulator.AgentRegistry},
        {DynamicSupervisor, name: Simulator.AgentSupervisor, strategy: :one_for_one},
        Simulator.Simulation.PriorityManager,
        Simulator.Spatial.ChunkManager,
        Simulator.Economy.ContractBoard,
        Simulator.Economy.DemandAnalyzer,
        Simulator.TickCoordinator,
        Simulator.PersistenceManager,
        Simulator.Metrics,

        # Start to serve requests, typically the last entry
        SimulatorWeb.Endpoint
      ] ++ parent_watcher_child()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Simulator.Supervisor]
    result = Supervisor.start_link(children, opts)

    # Init ETS tables
    Simulator.Simulation.RetirementLedger.init()
    Simulator.Events.init_log()
    Simulator.Spatial.ShipMetadata.init()
    Simulator.AgentSnapshots.init()

    # Auto-start the simulation in dev (not test). auto_spawn is gated
    # off in test to avoid races with the sandbox; tests that want a
    # live world call Spawner.spawn_world/0 themselves.
    if Application.get_env(:simulator, :auto_spawn, false) do
      # First-boot hook: a freshly installed desktop bundle has the DB
      # schema (Ecto.Migrator ran above) but no world data yet. Seed
      # from the bundled JSON so the Spawner's wait_for_systems loop
      # finds something. Idempotent — a no-op on subsequent boots.
      # Gated behind auto_spawn so the test env (which manages its own
      # lifecycle) doesn't get seed data it doesn't want.
      maybe_seed_on_first_boot()

      Task.start(fn -> Simulator.Simulation.Spawner.spawn_world() end)
    end

    # Endpoint is running by the time start_link returns; write the
    # actual bound port next to the DB so Godot knows where to connect
    # even when the OS picked it (PORT=0 in prod).
    write_port_sidecar()

    log_runtime_diagnostics()

    result
  end

  # Logs scheduler + CPU info at boot. Surfaces Godot-spawn pitfalls:
  # if the BEAM sees only 1 scheduler because the parent process's
  # sandbox restricted CPU visibility, 250+ GenServers compete for
  # one thread and stalls cascade. Comparing to logical processors
  # tells us whether the VM actually picked up the machine's cores.
  defp log_runtime_diagnostics do
    require Logger

    schedulers = :erlang.system_info(:schedulers)
    schedulers_online = :erlang.system_info(:schedulers_online)
    logical = :erlang.system_info(:logical_processors)
    logical_online = :erlang.system_info(:logical_processors_online)

    Logger.info(
      "BEAM: schedulers=#{schedulers} online=#{schedulers_online} " <>
        "logical_cpus=#{logical} online=#{logical_online} " <>
        "otp=#{:erlang.system_info(:otp_release)} " <>
        "wordsize=#{:erlang.system_info(:wordsize) * 8}bit"
    )

    if schedulers_online < 2 do
      Logger.warning(
        "BEAM is running with #{schedulers_online} scheduler — this will stall under load. " <>
          "Likely cause: the parent process (Godot) limited CPU visibility. " <>
          "Set ERL_FLAGS=\"+S 4:4\" in the spawn env, or pass more cores."
      )
    end
  end

  defp write_port_sidecar do
    with {:ok, {_ip, port}} when is_integer(port) and port > 0 <-
           SimulatorWeb.Endpoint.server_info(:http),
         db_path when is_binary(db_path) <-
           Application.get_env(:simulator, Simulator.Repo)[:database] do
      dir = Path.dirname(db_path)
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "port.txt"), Integer.to_string(port))
      # BEAM pid sidecar. `mix release … daemon` uses run_erl, which
      # doesn't write a pid file anywhere predictable — Godot needs
      # this to track the real daemon process for crash detection
      # and clean shutdown (its sh-wrapper exits seconds after fork).
      File.write!(Path.join(dir, "beam.pid"), to_string(:os.getpid()))

      require Logger
      Logger.info("Simulator listening on http://127.0.0.1:#{port}")
    end
  rescue
    e ->
      require Logger
      Logger.warning("Port sidecar write failed: #{Exception.message(e)}")
  end

  # The ParentWatcher is only relevant when this release was spawned by
  # another process (Godot) that passed its own PID via PARENT_PID. No
  # env var, no watcher — so `mix phx.server` in dev and manual
  # `bin/simulator start` from a terminal are unaffected.
  defp parent_watcher_child do
    case System.get_env("PARENT_PID") do
      pid when is_binary(pid) and pid != "" ->
        [{Simulator.ParentWatcher, parent_pid: pid}]

      _ ->
        []
    end
  end

  defp maybe_seed_on_first_boot do
    unless Simulator.Release.seeded?() do
      require Logger
      Logger.info("First-boot detected — seeding world from JSON")
      Simulator.Release.seed()
      Simulator.World.Registry.reload()
    end
  rescue
    e ->
      require Logger
      Logger.error("First-boot seed failed: #{Exception.message(e)}")
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SimulatorWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
