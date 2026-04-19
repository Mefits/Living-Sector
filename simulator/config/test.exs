import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :simulator, Simulator.Repo,
  database:
    Path.expand(
      "../priv/sim_test#{System.get_env("MIX_TEST_PARTITION")}.db",
      __DIR__
    ),
  journal_mode: :wal,
  busy_timeout: 5_000,
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :simulator, SimulatorWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "GNepqm5kHF3AvksdU7FDuuFCaPuEJHz8w2fwGz2XFoR4JhDcYUYM7R2WuR3+tp5c",
  server: false

# In test we don't send emails
config :simulator, Simulator.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
