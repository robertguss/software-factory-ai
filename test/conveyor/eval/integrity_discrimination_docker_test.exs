defmodule Conveyor.Eval.IntegrityDiscriminationDockerTest do
  @moduledoc """
  ADR-23 — end-to-end integrity discrimination through the real Docker hermetic
  backend, the gate, and the Finalizer — at $0 (the known-good reference solution,
  no agent). Proves:

    * docker hermetic + clean   -> trustworthy   -> :accepted
    * docker network-open       -> untrustworthy -> :abstained + slice :parked
    * docker hermetic + a test that rewrites src -> untrustworthy -> :abstained

  Tagged :eval (needs Docker + the runner image; the image is built on demand).
  """
  use Conveyor.DataCase, async: false

  import Conveyor.FactoryFixtures

  alias Conveyor.Eval.ToolchainRunner
  alias Conveyor.Factory
  alias Conveyor.Factory.Slice
  alias Conveyor.Gate.Finalizer
  alias Conveyor.Gate.IntegrityEvidence
  alias Conveyor.Gate.TrustEvidence
  alias Conveyor.Jobs.RunGate

  @moduletag :eval
  @moduletag timeout: 600_000

  @sample Path.expand("../../../samples/beads_insight", __DIR__)
  @plan_path Path.join(@sample, "conveyor.plan.yml")
  @reference Path.join(@sample, ".conveyor/canary/reference_full.patch")
  @image "conveyor/beads-insight-runner:local"
  @probes ["hermeticity", "source_mutation"]
  @calibration %{status: :valid, expected_failures: ["acceptance_red_on_base"]}

  setup do
    ensure_image!()
    :ok
  end

  test "docker hermetic + clean reference -> trustworthy -> accepted" do
    result = run_case(network: "none")

    assert result.gate.passed?, inspect(result.gate.findings)
    assert result.output["integrity_verdict"] == "trustworthy"
    assert result.final.run_attempt.outcome == :accepted
  end

  test "docker with network open -> hermeticity fails -> untrustworthy -> abstained + parked" do
    result = run_case(network: "bridge")

    assert result.gate.passed?, "the suite still passes; only the integrity layer flags it"
    assert result.output["integrity_verdict"] == "untrustworthy"
    assert result.final.run_attempt.outcome == :abstained
    assert reload(Slice, result.slice_id).state == :parked
  end

  test "docker hermetic + a test that rewrites src -> untrustworthy -> abstained" do
    result = run_case(network: "none", cheat: true)

    assert result.gate.passed?
    assert result.output["integrity_verdict"] == "untrustworthy"
    assert result.final.run_attempt.outcome == :abstained
  end

  # --- pipeline -------------------------------------------------------------

  defp run_case(opts) do
    fixture = create_artifact_run!(blob_root: temp_dir!("docker-demo"))
    slice = reload(Slice, fixture.run_attempt.slice_id)

    run_attempt =
      Ash.update!(fixture.run_attempt, %{status: :reviewed, outcome: :none}, domain: Factory)

    Ash.update!(slice, %{state: :in_progress}, domain: Factory)

    ws = reference_workspace!(opts)
    plan = YamlElixir.read_from_file!(@plan_path)

    verification_result =
      ToolchainRunner.verification_result(ws, plan,
        backend: :docker,
        docker_image: @image,
        network: Keyword.fetch!(opts, :network),
        source_root: "src"
      )

    integrity_verdict =
      IntegrityEvidence.verdict(verification_result["integrity_observations"],
        required_probes: @probes
      )

    output = %{
      "verification_result" => verification_result,
      "integrity_verdict" => integrity_verdict,
      "test_pack_calibration" => %{"status" => "valid"},
      "baseline_health_status" => "passed"
    }

    context = gate_context(fixture, slice, run_attempt, verification_result)
    gate = RunGate.run_gate_only!(context, [Conveyor.Gate.Stages.TestExecution])

    final =
      Finalizer.finalize!(
        gate,
        Map.put(context, :trust_evidence, TrustEvidence.from_run_output(output)),
        actor: "docker-demo"
      )

    %{output: output, gate: gate, final: final, slice_id: slice.id}
  end

  defp gate_context(fixture, slice, run_attempt, verification_result) do
    %{
      project: fixture.project,
      slice: slice,
      run_attempt: run_attempt,
      run_attempt_id: run_attempt.id,
      gate_code_sha256: "sha256:gate",
      policy_sha256: "sha256:policy",
      contract_lock_sha256: "sha256:contract",
      canary_suite_version: "canary@1",
      patch_sha256: "sha256:patch",
      code_symbols: ["br_insight.loader.load"],
      acceptance_criteria: [
        %{
          "id" => "AC-001",
          "text" => "Loader parses the corpus.",
          "requirement_refs" => ["REQ-001"]
        }
      ],
      claims_by_pointer: %{
        "/acceptance_criteria/0" => %{origin: :deterministic, source_anchor_refs: ["REQ-001"]}
      },
      verification_result: verification_result,
      test_pack_calibration: @calibration
    }
  end

  # --- workspace / image ----------------------------------------------------

  defp reference_workspace!(opts) do
    ws = temp_dir!("docker-ref-ws")

    {_, 0} =
      System.cmd("rsync", [
        "-a",
        "--exclude",
        ".venv",
        "--exclude",
        ".pytest_cache",
        "--exclude",
        "__pycache__",
        "--exclude",
        ".git",
        @sample <> "/",
        ws <> "/"
      ])

    {_, 0} =
      System.cmd("patch", ["-p3", "-f", "-d", ws, "-i", @reference], stderr_to_stdout: true)

    if Keyword.get(opts, :cheat, false), do: plant_cheating_test!(ws)
    ws
  end

  defp plant_cheating_test!(ws) do
    File.write!(Path.join(ws, "tests/test_zz_cheat.py"), """
    def test_zz_cheat():
        with open("src/br_insight/loader.py", "a") as handle:
            handle.write("\\n# mutated during the test run\\n")
        assert True
    """)
  end

  defp ensure_image! do
    unless image_exists?() do
      dir = temp_dir!("beads-runner-build")
      File.cp!(Path.join(@sample, "requirements.lock"), Path.join(dir, "requirements.lock"))

      File.write!(Path.join(dir, "Dockerfile"), """
      FROM python:3.13-slim
      ENV PIP_DISABLE_PIP_VERSION_CHECK=1 PIP_NO_CACHE_DIR=1 PYTHONDONTWRITEBYTECODE=1
      COPY requirements.lock /opt/requirements.lock
      RUN python -m pip install --requirement /opt/requirements.lock
      WORKDIR /work
      """)

      {_, 0} = System.cmd("docker", ["build", "-t", @image, dir], stderr_to_stdout: true)
    end
  end

  defp image_exists?,
    do: match?({_, 0}, System.cmd("docker", ["image", "inspect", @image], stderr_to_stdout: true))

  defp reload(resource, id) do
    resource |> Ash.read!(domain: Factory) |> Enum.find(&(&1.id == id))
  end
end
