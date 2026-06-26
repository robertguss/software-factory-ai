# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :conveyor,
  ash_domains: [Conveyor.Factory],
  ecto_repos: [Conveyor.Repo],
  generators: [timestamp_type: :utc_datetime],
  # M6 SerialDriver wall-clock reaper. A stuck slice (loops across rework, or a hung
  # non-agent station) is reaped at the per-slice budget; the whole unattended run is bounded
  # by the run budget. A reaped slice parks and the run advances (skip-and-continue). Set to
  # nil/false to disable. Per-call opts (:slice_wall_clock_ms / :run_wall_clock_ms) override.
  serial_driver_slice_wall_clock_ms: 3_600_000,
  serial_driver_run_wall_clock_ms: 28_800_000,
  station_modules: %{
    "context_scout" => Conveyor.Stations.ContextScout,
    "baseline_health" => Conveyor.Stations.BaselineHealth,
    "acceptance_calibration" => Conveyor.Stations.AcceptanceCalibration,
    "implement" => Conveyor.Stations.Implementer,
    "verify" => Conveyor.Stations.Verify,
    "record_evidence" => Conveyor.Stations.RecordEvidence
  }

config :conveyor, Oban,
  repo: Conveyor.Repo,
  queues: [
    default: 10,
    conductor: 5,
    gate: 5,
    maintenance: 2
  ],
  plugins: []

# Configures the endpoint
config :conveyor, ConveyorWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: ConveyorWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Conveyor.PubSub,
  live_view: [signing_salt: "fcEZTPl6"],
  session_signing_salt: System.get_env("SESSION_SIGNING_SALT") || "lF8jHNOH"

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# esbuild bundles the browser runtime in assets/ into priv/static/assets.
# `phoenix` and `phoenix_live_view` resolve from deps/ via NODE_PATH; npm
# packages (react, react-dom, cytoscape, …) resolve from assets/node_modules,
# which the `assets.setup` alias creates with `npm install` (the esbuild binary
# bundles from node_modules but does not create it). `--loader:.js=jsx` lets the
# React/JSX entrypoint and components build; `--alias:@=./js` matches jsconfig.
config :esbuild,
  version: "0.25.4",
  conveyor: [
    args:
      ~w(js/app.jsx --bundle --target=es2020 --outdir=../priv/static/assets --loader:.js=jsx --loader:.jsx=jsx --alias:@=./js --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Inertia.js: controllers return props to React pages. SSR is off (no Node
# worker pool — internal operator tool). `static_paths` drives asset-version
# busting; props stay snake_case to match the cockpit's server payloads.
config :inertia,
  endpoint: ConveyorWeb.Endpoint,
  static_paths: ["/assets/app.js"],
  default_version: "1",
  camelize_props: false,
  ssr: false

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
