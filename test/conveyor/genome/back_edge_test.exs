defmodule Conveyor.Genome.BackEdgeTest do
  use Conveyor.DataCase, async: false

  import Conveyor.FactoryFixtures

  alias Conveyor.Factory
  alias Conveyor.Factory.CodeProvenanceEdge
  alias Conveyor.Factory.GateResult
  alias Conveyor.Genome.BackEdge

  setup do
    fixture = create_artifact_run!(blob_root: temp_dir!("back-edge-blobs"))
    %{run_attempt: fixture.run_attempt}
  end

  test "re-finalizing the same logical edge under a new gate_result_id dedupes to one row", %{
    run_attempt: run_attempt
  } do
    context = logical_context(run_attempt, ["Conveyor.Demo.run/1"])

    first = gate_result!(run_attempt)
    second = gate_result!(run_attempt)
    assert first.id != second.id

    assert [edge] = BackEdge.mint!(context, first)

    # KTD-1: `gate_result_id` is excluded from `edge_sha256`, so re-finalizing the SAME
    # logical (slice, attempt, criterion, code_symbol) edge under a fresh GateResult
    # produces an identical digest. The upsert on `:unique_edge_sha256` collapses the
    # duplicate gracefully (no raise) and refreshes the row's gate_result_id to the
    # latest finalization.
    assert [reupsert] = BackEdge.mint!(context, second)
    assert reupsert.id == edge.id
    assert reupsert.edge_sha256 == edge.edge_sha256

    assert [only] = Ash.read!(CodeProvenanceEdge, domain: Factory)
    assert only.id == edge.id
    assert only.edge_sha256 == edge.edge_sha256
    # gate_result_id refreshed to the most recent finalization.
    assert only.gate_result_id == second.id
  end

  test "distinct code symbols mint distinct edges", %{run_attempt: run_attempt} do
    context = logical_context(run_attempt, ["Conveyor.Demo.a/0", "Conveyor.Demo.b/0"])

    edges = BackEdge.mint!(context, gate_result!(run_attempt))

    assert length(edges) == 2
    assert edges |> Enum.map(& &1.edge_sha256) |> Enum.uniq() |> length() == 2
    assert length(Ash.read!(CodeProvenanceEdge, domain: Factory)) == 2
  end

  test "gate_result_id is excluded from the digest but still persisted on the row", %{
    run_attempt: run_attempt
  } do
    context = logical_context(run_attempt, ["Conveyor.Demo.run/1"])
    gate_result = gate_result!(run_attempt)

    assert [edge] = BackEdge.mint!(context, gate_result)

    # Excluded from the digest INPUT, not dropped from the persisted record.
    assert edge.gate_result_id == gate_result.id
    assert Ash.get!(CodeProvenanceEdge, edge.id, domain: Factory).gate_result_id == gate_result.id
  end

  defp logical_context(run_attempt, code_symbols) do
    %{
      run_attempt: run_attempt,
      acceptance_criteria: [%{id: "AC-1", requirement_refs: ["req-1"]}],
      code_symbols: code_symbols,
      patch_sha256: digest("patch"),
      contract_lock_sha256: digest("contract-lock")
    }
  end

  defp gate_result!(run_attempt) do
    Ash.create!(
      GateResult,
      %{
        run_attempt_id: run_attempt.id,
        passed: true,
        stages: [],
        gate_version: "gate@1",
        gate_code_sha256: digest("gate-code"),
        policy_sha256: digest("policy"),
        contract_lock_sha256: digest("contract-lock"),
        canary_suite_version: "canary@1"
      },
      domain: Factory
    )
  end

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
