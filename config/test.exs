import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :conveyor, Conveyor.Repo,
  username: System.get_env("PGUSER", "postgres"),
  password: System.get_env("PGPASSWORD", "postgres"),
  hostname: System.get_env("PGHOST", "localhost"),
  port: String.to_integer(System.get_env("PGPORT", "5432")),
  database: System.get_env("PGDATABASE", "conveyor_test#{System.get_env("MIX_TEST_PARTITION")}"),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :conveyor, ConveyorWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "0msPFxBAq6Vz1CJc+FBgqz4pXeNSLolxZvJK238NAzoKpVgJ2AcpJnRaTknsekU3",
  server: false

config :conveyor, Oban, testing: :manual, queues: false, plugins: false

# Disable the SerialDriver wall-clock reaper in tests: existing driver tests inject
# self()-sending closures and assert_received, which only works when the slice runs inline
# (no Task boundary). Reaper-specific tests opt in explicitly via per-call opts.
config :conveyor,
  serial_driver_slice_wall_clock_ms: nil,
  serial_driver_run_wall_clock_ms: nil

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime
