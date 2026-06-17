# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :conveyor,
  ecto_repos: [Conveyor.Repo],
  generators: [timestamp_type: :utc_datetime]

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
  live_view: [signing_salt: "fcEZTPl6"]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
