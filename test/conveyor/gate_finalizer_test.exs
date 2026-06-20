defmodule Conveyor.GateFinalizerTest do
  use Conveyor.DataCase, async: false

  import Conveyor.FactoryFixtures

  alias Conveyor.Factory
  alias Conveyor.Factory.Artifact
  alias Conveyor.Factory.CodeProvenanceEdge
  alias Conveyor.Factory.GateResult
  alias Conveyor.Factory.Incident
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.Slice
  alias Conveyor.Gate
  alias Conveyor.Gate.Finalizer

  defmodule PassStage do
    @behaviour Conveyor.Gate.Stage

    @impl true
    def run(_context, _opts), do: %{status: :passed, evidence_refs: ["evidence.json"]}
  end

  defmodule PolicyFailStage do
    @behaviour Conveyor.Gate.Stage

    @impl true
    def run(_context, _opts) do
      %{
        status: :failed,
        findings: [
          %{
            "category" => "policy_invocation_blocked",
            "severity" => "blocking",
            "message" => "blocked"
          }
        ]
      }
    end
  end

  defmodule ReworkFailStage do
    @behaviour Conveyor.Gate.Stage

    @impl true
    def run(_context, _opts) do
      %{
        status: :failed,
        findings: [
          %{
            "category" => "acceptance_locked_failed",
            "severity" => "blocking",
            "message" => "red"
          }
        ]
      }
    end
  end

  defmodule CanaryFailStage do
    @behaviour Conveyor.Gate.Stage

    @impl true
    def run(_context, _opts) do
      %{
        status: :failed,
        findings: [
          %{
            "category" => "stale_canary",
            "severity" => "blocking",
            "message" => "stale",
            "path" => "gate-canaries/latest.json"
          }
        ]
      }
    end
  end

  setup do
    fixture = create_artifact_run!(blob_root: temp_dir!("gate-finalizer"))
    slice = get_by_id!(Slice, fixture.run_attempt.slice_id)

    run_attempt =
      Ash.update!(
        fixture.run_attempt,
        %{status: :reviewed, outcome: :none},
        domain: Factory
      )

    slice = Ash.update!(slice, %{state: :in_progress}, domain: Factory)

    %{project: fixture.project, run_attempt: run_attempt, slice: slice}
  end

  test "persists passed GateResult and moves run attempt and slice to gated", context do
    result = Gate.run!(gate_context(context), [%{key: "pass", module: PassStage}])

    finalized = Finalizer.finalize!(result, gate_context(context))

    assert finalized.gate_result.passed
    assert get_by_id!(RunAttempt, context.run_attempt.id).status == :gated
    assert get_by_id!(RunAttempt, context.run_attempt.id).outcome == :accepted
    assert get_by_id!(Slice, context.slice.id).state == :gated
    assert [stored] = Ash.read!(GateResult, domain: Factory)
    assert stored.run_attempt_id == context.run_attempt.id

    assert [edge] = Ash.read!(CodeProvenanceEdge, domain: Factory)
    assert edge.code_symbol == "Conveyor.Tasks.complete/1"
    assert edge.acceptance_criterion_id == "AC-GATE-001"
    assert edge.role == "verified_by_gate"
    assert edge.decision == :passed
    assert edge.patch_sha256 == "sha256:patch"
    assert edge.gate_result_id == finalized.gate_result.id

    assert [artifact] =
             Artifact
             |> Ash.read!(domain: Factory)
             |> Enum.filter(&(&1.kind == "trust-bundle"))

    assert artifact.run_attempt_id == context.run_attempt.id
    assert artifact.subject_kind == "gate_result"
    assert artifact.projection_path =~ finalized.gate_result.id
  end

  test "policy failures record GateResult and policy-block the slice", context do
    result = Gate.run!(gate_context(context), [%{key: "policy", module: PolicyFailStage}])

    finalized = Finalizer.finalize!(result, gate_context(context))

    refute finalized.gate_result.passed
    assert get_by_id!(RunAttempt, context.run_attempt.id).status == :failed
    assert get_by_id!(RunAttempt, context.run_attempt.id).outcome == :policy_blocked
    assert get_by_id!(Slice, context.slice.id).state == :policy_blocked
  end

  test "ordinary gate failures request rework", context do
    result = Gate.run!(gate_context(context), [%{key: "tests", module: ReworkFailStage}])

    Finalizer.finalize!(result, gate_context(context))

    assert get_by_id!(RunAttempt, context.run_attempt.id).status == :needs_rework
    assert get_by_id!(RunAttempt, context.run_attempt.id).outcome == :needs_rework
    assert get_by_id!(Slice, context.slice.id).state == :needs_rework
  end

  test "critical canary failure fails the slice and opens stop-the-line incident", context do
    result = Gate.run!(gate_context(context), [%{key: "canary", module: CanaryFailStage}])

    finalized = Finalizer.finalize!(result, gate_context(context))

    assert get_by_id!(RunAttempt, context.run_attempt.id).status == :failed
    assert get_by_id!(Slice, context.slice.id).state == :failed
    assert finalized.incident.category == "stop_the_line"
    assert finalized.incident.severity == :critical

    assert [incident] = Ash.read!(Incident, domain: Factory)
    assert incident.run_attempt_id == context.run_attempt.id
  end

  defp gate_context(context) do
    %{
      project: context.project,
      slice: context.slice,
      run_attempt: context.run_attempt,
      run_attempt_id: context.run_attempt.id,
      gate_code_sha256: "sha256:gate",
      policy_sha256: "sha256:policy",
      contract_lock_sha256: "sha256:contract",
      canary_suite_version: "canary@1",
      patch_sha256: "sha256:patch",
      code_symbols: ["Conveyor.Tasks.complete/1"],
      acceptance_criteria: [
        %{
          "id" => "AC-GATE-001",
          "text" => "Completed tasks persist.",
          "requirement_refs" => ["REQ-GATE-001"]
        }
      ],
      claims_by_pointer: %{
        "/acceptance_criteria/0" => %{
          origin: :deterministic,
          source_anchor_refs: ["REQ-GATE-001"]
        }
      }
    }
  end

  defp get_by_id!(resource, id) do
    resource
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == id))
  end
end
