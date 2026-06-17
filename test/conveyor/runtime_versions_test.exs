defmodule Conveyor.RuntimeVersionsTest do
  use ExUnit.Case, async: true

  @image_digest "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

  test "captures every runtime field required by RunSpec and Evidence" do
    snapshot =
      Conveyor.RuntimeVersions.capture!(
        docker_engine_version: "28.2.2",
        sandbox_runner_version: "conveyor.sandbox_runner.docker@test",
        agent_adapter_version: "conveyor.agent_runner.pi@test",
        toolchain_image_digest: @image_digest
      )

    assert Enum.sort(Map.keys(snapshot)) == Enum.sort(Conveyor.RuntimeVersions.required_fields())
    assert snapshot.elixir_version =~ ~r/^\d+\.\d+/
    assert snapshot.otp_version =~ ~r/^\d+/
    assert snapshot.phoenix_version =~ ~r/^1\.8\./
    assert snapshot.ash_version =~ ~r/^3\./
    assert snapshot.oban_version =~ ~r/^2\./
    assert snapshot.docker_engine_version == "28.2.2"
    assert snapshot.sandbox_runner_version == "conveyor.sandbox_runner.docker@test"
    assert snapshot.agent_adapter_version == "conveyor.agent_runner.pi@test"
    assert snapshot.toolchain_image_digest == @image_digest
  end

  test "requires the toolchain image digest for every captured run" do
    assert_raise KeyError, fn ->
      Conveyor.RuntimeVersions.capture!(docker_engine_version: "28.2.2")
    end
  end

  test "publishes the tested Phase 0/1 tool matrix" do
    assert %{
             elixir: "~> 1.20",
             otp: ">= 27",
             phoenix: "~> 1.8.8",
             ash: "~> 3.29",
             ash_postgres: "~> 2.10",
             oban: "~> 2.23",
             postgrex: "~> 0.22",
             postgres: "16",
             docker_engine: ">= 24.0"
           } = Conveyor.ToolMatrix.latest_tested_versions()

    assert Conveyor.ToolMatrix.default_toolchain_image().digest =~ ~r/^sha256:[0-9a-f]{64}$/
  end
end
