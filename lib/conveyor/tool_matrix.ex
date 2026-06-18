defmodule Conveyor.ToolMatrix do
  @moduledoc """
  Tested Phase 0/1 runtime and dependency matrix.

  This is the code-level companion to the versions recorded in every RunSpec and
  Evidence artifact. Dependency requirements stay in `mix.exs`; this module
  gives doctor/run code one stable place to read the expected matrix.
  """

  @type version_requirement :: String.t()
  @type toolchain_image :: %{
          required(:ref) => String.t(),
          required(:digest) => String.t(),
          required(:sbom_ref) => String.t()
        }

  @latest_tested_versions %{
    elixir: "~> 1.20",
    otp: ">= 27",
    phoenix: "~> 1.8.8",
    ash: "~> 3.29",
    ash_postgres: "~> 2.10",
    oban: "~> 2.23",
    postgrex: "~> 0.22",
    postgres: "16",
    docker_engine: ">= 24.0"
  }

  @sandbox_runner_version "conveyor.sandbox_runner.docker@0.1.0"
  @agent_adapter_versions %{
    pi: "conveyor.agent_runner.pi@0.1.0"
  }

  @default_toolchain_image %{
    ref: "ghcr.io/conveyor/sample-python-runner:2026-06-17",
    digest: "sha256:18be896c98e13585f4d2701490a5be39126ec1b14d429f72b5707b99516b5548",
    sbom_ref: "toolchains/sample-python-runner/sbom.cyclonedx.json"
  }

  @spec latest_tested_versions() :: %{atom() => version_requirement()}
  def latest_tested_versions, do: @latest_tested_versions

  @spec sandbox_runner_version() :: String.t()
  def sandbox_runner_version, do: @sandbox_runner_version

  @spec agent_adapter_version(atom()) :: String.t()
  def agent_adapter_version(adapter), do: Map.fetch!(@agent_adapter_versions, adapter)

  @spec default_toolchain_image() :: toolchain_image()
  def default_toolchain_image, do: @default_toolchain_image
end
