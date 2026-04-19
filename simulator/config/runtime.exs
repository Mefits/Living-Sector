import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# The simulator ships as a bundled release spawned by the Godot client
# (see the desktop packaging plan). End users never touch env vars, so
# prod defaults the web server on, auto-persists a secret key, and picks
# a sensible SQLite path. Override via env vars for self-hosting or CI.

# Auto-spawn the simulation world on startup in dev/prod. Tests manage
# the world lifecycle themselves — leaving auto_spawn on during tests
# races the sandbox teardown and triggers cascading DB ownership errors
# across unrelated tests.
if config_env() != :test do
  config :simulator, auto_spawn: true
end

config :simulator, SimulatorWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :prod do
  # --- Server on by default for desktop bundle -----------------------
  # PHX_SERVER=false disables (e.g., for eval-only release shell tasks).
  unless System.get_env("PHX_SERVER") == "false" do
    config :simulator, SimulatorWeb.Endpoint, server: true
  end

  # --- SQLite database path ------------------------------------------
  # Default puts the DB alongside the release's writable area. Desktop
  # bundlers should pass DATABASE_PATH to point at the platform-specific
  # user-data directory instead.
  default_db_dir = Path.join(System.tmp_dir!(), "simulator")

  database_path =
    System.get_env("DATABASE_PATH") || Path.join(default_db_dir, "sim.db")

  File.mkdir_p!(Path.dirname(database_path))

  config :simulator, Simulator.Repo,
    database: database_path,
    journal_mode: :wal,
    busy_timeout: 5_000,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5")

  # --- Log to a file, not stdio -------------------------------------
  # When Godot spawns the release via OS.create_process, its pipes to
  # the child's stdout/stderr are never drained. The macOS/Linux pipe
  # buffer is ~64 KB — cold boot (migrator + seed + spawner logs) can
  # fill it in seconds, at which point any Logger.* call blocks the
  # calling process. Every ship that logs during handle_tick then
  # starves, mailboxes fill, and the sim effectively halts.
  #
  # Writing to a file decouples logging from the parent process's
  # pipe-draining behavior entirely. File lands next to the DB so
  # `<saves_dir>/` stays the one place users need to look for state.
  log_path = Path.join(Path.dirname(database_path), "simulator.log")
  File.mkdir_p!(Path.dirname(log_path))

  config :logger, :default_handler,
    config: %{
      file: String.to_charlist(log_path),
      # Rotate at 10 MB, keep 5 files — 50 MB ceiling per install.
      max_no_bytes: 10_485_760,
      max_no_files: 5,
      # Flush every 5 s so `tail -f simulator.log` stays responsive
      # without hammering fsync on the hot path.
      filesync_repeat_interval: 5_000
    }

  # Prod defaults to `:warning` — the sim is chatty at :info (every
  # seed step, trade, contract post, boot phase, etc.) which isn't
  # useful for a shipped desktop app and makes actual warnings hard
  # to spot. Override with LOG_LEVEL=info / =debug when investigating.
  log_level =
    case System.get_env("LOG_LEVEL") do
      nil -> :warning
      str -> String.to_existing_atom(str)
    end

  config :logger, level: log_level

  # --- Secret key base: auto-persist if absent -----------------------
  # The cookie-signing key doesn't need to be human-managed for a local
  # desktop sim. If SECRET_KEY_BASE isn't set, generate once and stash
  # next to the DB so it's stable across restarts.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      (
        secret_path = Path.join(Path.dirname(database_path), "secret_key_base")

        case File.read(secret_path) do
          {:ok, cached} when byte_size(cached) >= 64 ->
            String.trim(cached)

          _ ->
            generated = 64 |> :crypto.strong_rand_bytes() |> Base.encode64()
            File.mkdir_p!(Path.dirname(secret_path))
            File.write!(secret_path, generated)
            generated
        end
      )

  host = System.get_env("PHX_HOST") || "localhost"

  config :simulator, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  # Default to port 0 (OS picks a free port) so the desktop bundle
  # can't collide with whatever else the user is running locally.
  # The actual bound port is written to `<saves_dir>/port.txt` after
  # the endpoint comes up; Godot reads that file on connect.
  # Set PORT explicitly to pin a specific port (useful for curling
  # the release from a terminal).
  port = String.to_integer(System.get_env("PORT") || "0")

  # Bind loopback for desktop; exposing beyond the host is opt-in via
  # BIND_IP=0.0.0.0 for server deployments.
  bind_ip =
    case System.get_env("BIND_IP", "127.0.0.1") do
      "0.0.0.0" ->
        {0, 0, 0, 0}

      other ->
        other
        |> String.split(".")
        |> Enum.map(&String.to_integer/1)
        |> List.to_tuple()
    end

  config :simulator, SimulatorWeb.Endpoint,
    url: [host: host, port: port, scheme: "http"],
    http: [ip: bind_ip, port: port],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :simulator, SimulatorWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :simulator, SimulatorWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :simulator, Simulator.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
