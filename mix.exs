defmodule Conveyor.MixProject do
  use Mix.Project

  def project do
    [
      app: :conveyor,
      version: "0.1.0",
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      dialyzer: [
        ignore_warnings: ".dialyzer_ignore.exs",
        plt_add_apps: [:ex_unit, :mix]
      ],
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Conveyor.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8.8"},
      {:phoenix_live_view, "~> 1.2"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_ecto, "~> 4.7"},
      {:ecto_sql, "~> 3.14"},
      {:postgrex, "~> 0.22"},
      {:ash, "~> 3.29"},
      {:ash_postgres, "~> 2.10"},
      {:ash_state_machine, "~> 0.2.13"},
      {:oban, "~> 2.23"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:toml_elixir, "~> 3.1"},
      {:jsv, "~> 0.19.5"},
      {:dns_cluster, "~> 0.1.1"},
      {:bandit, "~> 1.12"},
      {:inertia, "~> 2.6"},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:lazy_html, ">= 0.1.0", only: :test},
      # Direct dep (was transitive via Ash): property-based eval tests must not
      # rely on a transitive dependency. No `:only` restriction — Ash depends on
      # stream_data unconditionally (all envs), so an env-scoped decl diverges.
      # See docs/3_evals/IMPLEMENTATION-PLAN-RUNGS-0-1.md (F0).
      {:stream_data, "~> 1.0"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      # `ecto.setup` precedes `assets.setup` so DB provisioning never depends on a
      # successful `npm install` (offline / no-Node machines still get a usable DB).
      setup: ["deps.get", "ecto.setup", "assets.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      # The esbuild binary bundles from assets/node_modules but does not create
      # it, so `npm install` runs alongside the binary install.
      "assets.setup": ["esbuild.install --if-missing", "cmd --cd assets npm install"],
      "assets.build": ["esbuild conveyor"],
      "assets.deploy": ["cmd --cd assets npm install", "esbuild conveyor --minify", "phx.digest"]
    ]
  end
end
