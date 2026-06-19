defmodule Conveyor.PlanningWorkGraphLoweringTest do
  use ExUnit.Case, async: true

  alias Conveyor.Planning.PlanningSpec
  alias Conveyor.Planning.WorkGraphLowering

  test "lowers a selected proposal to canonical work graph IR after digest validation" do
    spec = planning_spec()
    candidate = selected_candidate(spec.spec_digest)

    assert {:ok, graph} = WorkGraphLowering.lower(candidate, spec)

    assert graph.schema_version == "conveyor.work_graph@2"
    assert graph.plan_revision_digest == spec.plan_revision_digest
    assert graph.constraint_set_digest == spec.constraint_set_digest
    assert graph.selected_candidate_digest =~ ~r/^sha256:[0-9a-f]{64}$/
    assert graph.claim_set_ref == "blobs/sha256/claims"
    assert graph.derivation_manifest_ref == "blobs/sha256/derivation"
    assert graph.scope_delta == "scope_preserved"

    assert graph.epics == [
             %{
               key: "EPIC-TASKS",
               title: "Task query behavior",
               requirement_refs: ["REQ-001"],
               slice_keys: ["SLC-SCHEMA", "SLC-FILTER"]
             }
           ]

    assert Enum.map(graph.slices, & &1.stable_key) == ["SLC-SCHEMA", "SLC-FILTER"]
    assert Enum.map(graph.slices, & &1.proposal_key) == ["schema-proposal", "filter-proposal"]

    assert graph.atomicity_groups == [
             %{
               key: "ATOMIC-TASKS",
               policy: "same_integration_batch",
               member_keys: ["SLC-SCHEMA", "SLC-FILTER"],
               reason: "Partial integration would expose unreadable state.",
               claim_ref: "CLM-ATOMIC"
             }
           ]

    assert graph.work_dependencies == [
             %{
               from: "SLC-SCHEMA",
               to: "SLC-FILTER",
               kind: "execution_hard",
               rationale: "The query needs persisted state first.",
               source_anchor_refs: ["SRC-REQ-001"],
               claim_ref: "CLM-EDGE"
             }
           ]

    assert graph.interface_contracts == [
             %{
               interface_key: "db.tasks.completed",
               kind: "db_column",
               stability: "internal_cross_slice",
               lock_level: "review_required",
               compatibility_policy: "migration_required",
               owner_slice_key: "SLC-SCHEMA",
               version: "1"
             }
           ]

    assert graph.interface_bindings == [
             %{
               slice_key: "SLC-SCHEMA",
               interface_key: "db.tasks.completed",
               direction: "provides"
             },
             %{
               slice_key: "SLC-FILTER",
               interface_key: "db.tasks.completed",
               direction: "requires",
               required_version_range: ">=1 <2"
             }
           ]

    assert graph.decision_blocks == [
             %{
               slice_key: "SLC-FILTER",
               human_decision_ref: "DEC-API-COMPAT",
               reason: "Compatibility strategy must be chosen."
             }
           ]
  end

  test "rejects malformed proposals before work graph materialization" do
    spec = planning_spec()

    malformed =
      spec.spec_digest
      |> selected_candidate()
      |> put_in([:slices], [%{proposal_key: "missing-stable-key"}])

    assert {:error, diagnostic} = WorkGraphLowering.lower(malformed, spec)
    assert diagnostic.status == :invalid_proposal
    assert diagnostic.work_graph == nil
    assert "slices[0].stable_key is required" in diagnostic.errors

    mismatched = %{
      selected_candidate(spec.spec_digest)
      | planning_spec_digest: digest("other-spec")
    }

    assert {:error, mismatch} = WorkGraphLowering.lower(mismatched, spec)
    assert "planning_spec_digest does not match frozen PlanningSpec" in mismatch.errors
  end

  defp planning_spec do
    PlanningSpec.build!(%{
      plan_revision_digest: digest("plan-revision"),
      constraint_set_digest: digest("constraints"),
      claim_set_digest: digest("claims"),
      policy_bundle_digest: digest("policy"),
      pass_graph: [%{pass_key: "lower_work_graph", version: "1"}],
      schema_compatibility: %{unknown_schema_policy: "fail"},
      environment_fingerprint_digest: digest("env")
    })
  end

  defp selected_candidate(spec_digest) do
    %{
      schema_version: "conveyor.decomposition_candidate@1",
      candidate_key: "primary-candidate",
      planning_spec_digest: spec_digest,
      claim_set_ref: "blobs/sha256/claims",
      derivation_manifest_ref: "blobs/sha256/derivation",
      scope_delta: "scope_preserved",
      epics: [
        %{
          key: "EPIC-TASKS",
          title: "Task query behavior",
          requirement_refs: ["REQ-001"],
          slice_keys: ["SLC-SCHEMA", "SLC-FILTER"]
        }
      ],
      slices: [
        %{
          proposal_key: "schema-proposal",
          stable_key: "SLC-SCHEMA",
          title: "Add completed-state storage",
          archetype_key: "schema_migration",
          change_class: "behavior_changing",
          source_anchor_refs: ["SRC-REQ-001"],
          constraint_refs: ["CON-001"],
          why_this_slice: "One independently testable persistence behavior.",
          risk: "medium",
          proposed_autonomy_ceiling: "L1",
          likely_files: ["app/schema.py"],
          likely_symbols: ["Task.completed"],
          conflict_domains: ["task_schema"],
          authorized_change_globs: ["app/**", "tests/**"],
          verification_obligation_keys: ["VOB-001"],
          challenge_case_refs: ["CHAL-001"],
          rollout_intent: "ordinary",
          claim_refs: ["CLM-SLC-001"]
        },
        %{
          proposal_key: "filter-proposal",
          stable_key: "SLC-FILTER",
          title: "Filter completed tasks",
          archetype_key: "crud_query_filter",
          change_class: "behavior_changing",
          source_anchor_refs: ["SRC-REQ-001"],
          constraint_refs: ["CON-001"],
          why_this_slice: "One independently testable query behavior.",
          risk: "low",
          proposed_autonomy_ceiling: "L1",
          likely_files: ["app/routes.py"],
          likely_symbols: ["list_tasks"],
          conflict_domains: ["tasks_api"],
          authorized_change_globs: ["app/**", "tests/**"],
          verification_obligation_keys: ["VOB-002"],
          challenge_case_refs: ["CHAL-002"],
          rollout_intent: "ordinary",
          claim_refs: ["CLM-SLC-002"]
        }
      ],
      atomicity_groups: [
        %{
          key: "ATOMIC-TASKS",
          policy: "same_integration_batch",
          member_keys: ["SLC-SCHEMA", "SLC-FILTER"],
          reason: "Partial integration would expose unreadable state.",
          claim_ref: "CLM-ATOMIC"
        }
      ],
      work_deps: [
        %{
          from: "SLC-SCHEMA",
          to: "SLC-FILTER",
          kind: "execution_hard",
          rationale: "The query needs persisted state first.",
          source_anchor_refs: ["SRC-REQ-001"],
          claim_ref: "CLM-EDGE"
        }
      ],
      interface_contracts: [
        %{
          interface_key: "db.tasks.completed",
          kind: "db_column",
          stability: "internal_cross_slice",
          lock_level: "review_required",
          compatibility_policy: "migration_required",
          owner_slice_key: "SLC-SCHEMA",
          version: "1"
        }
      ],
      interface_bindings: [
        %{
          slice_key: "SLC-SCHEMA",
          interface_key: "db.tasks.completed",
          direction: "provides"
        },
        %{
          slice_key: "SLC-FILTER",
          interface_key: "db.tasks.completed",
          direction: "requires",
          required_version_range: ">=1 <2"
        }
      ],
      decision_blocks: [
        %{
          slice_key: "SLC-FILTER",
          human_decision_ref: "DEC-API-COMPAT",
          reason: "Compatibility strategy must be chosen."
        }
      ]
    }
  end

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
