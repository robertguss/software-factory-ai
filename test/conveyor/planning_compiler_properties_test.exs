defmodule Conveyor.PlanningCompilerPropertiesTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Conveyor.Planning.ArtifactInputIndex
  alias Conveyor.Planning.GraphAnalyses
  alias Conveyor.Planning.InterfaceGraph
  alias Conveyor.Planning.PassRegistry
  alias Conveyor.Planning.SliceDependency
  alias Conveyor.Planning.StableIdentity
  alias Conveyor.Planning.StaticDecisionPackage
  alias Conveyor.Planning.StructuralDryRun

  property "generated compiler chains preserve structural invariants" do
    check all count <- integer(1..5) do
      slices = Enum.map(1..count, &slice/1)
      edges = Enum.map(edge_indexes(count), &dependency/1)

      dependency_graph = SliceDependency.analyze(%{slices: slices, dependencies: edges})
      assert dependency_graph.status == :valid

      %{candidate: first_identity} = StableIdentity.reconcile(%{candidate_key: "primary", slices: slices})
      %{candidate: reordered_identity} = StableIdentity.reconcile(%{candidate_key: "primary", slices: Enum.reverse(slices)})
      assert MapSet.new(first_identity.slices, & &1.stable_key) == MapSet.new(reordered_identity.slices, & &1.stable_key)

      assert InterfaceGraph.analyze(%{contracts: [contract()], bindings: [provider_binding() | consumer_bindings(count)]}).status ==
               :ready

      analysis = GraphAnalyses.run(graph_fixture(count, dependency_graph.work_edges))
      assert analysis.status == :passed
      assert analysis.scope_delta == :scope_preserved

      dry_run = StructuralDryRun.run(%{slices: slices, work_edges: dependency_graph.work_edges})
      assert List.first(dry_run.waves) == ["SLC-1"]
      assert dry_run.cost_time_estimate == :insufficient_history

      index = ArtifactInputIndex.build(%{emitted_artifacts: artifact_inputs(count), created_at: "2026-06-19T00:00:00Z"})
      changed = [%{subject_kind: "plan_revision", subject_id: "plan-1"}]
      assert [%{consumer_artifact_id: "artifact:SLC-1"}] = ArtifactInputIndex.preview_changed(index, changed)

      package = StaticDecisionPackage.build(package_input())
      assert package.authority_effect == :none
      assert package.creates_contract_lock? == false
    end
  end

  property "pass cache reuses identical inputs and misses changed authority digest" do
    check all version <- integer(1..3) do
      registry =
        PassRegistry.new()
        |> PassRegistry.register(%{
          pass_key: "property-pass",
          version: Integer.to_string(version),
          input_stage: :plan,
          output_stage: :graph,
          selectors: ["value"],
          cache_policy: :reusable,
          authority_effect: :none,
          run: fn context -> PassRegistry.read!(context, "value") end
        })

      inputs = %{"value" => "stable", "semantic_digest" => digest("semantic"), "authority_digest" => digest("authority")}
      first = PassRegistry.run(registry, "property-pass", inputs)
      second = PassRegistry.run(first.registry, "property-pass", inputs)
      changed = PassRegistry.run(second.registry, "property-pass", %{inputs | "authority_digest" => digest("changed-authority")})

      assert first.cache_status == :miss
      assert second.cache_status == :hit
      assert changed.cache_status == :miss
    end
  end

  defp slice(index) do
    %{
      stable_key: "SLC-#{index}",
      proposal_key: "slice-#{index}",
      archetype_key: "generated",
      change_class: "behavior_changing",
      status: "active",
      requirement_refs: ["REQ-#{index}"],
      acceptance_refs: ["AC-#{index}"],
      authorized_change_globs: ["app/**"],
      oracle_feasible?: true,
      risk_domains: ["api"]
    }
  end

  defp dependency(index) do
    %{
      from: "SLC-#{index}",
      to: "SLC-#{index + 1}",
      kind: "execution_hard",
      rationale: "Generated chain order",
      source_anchor_refs: ["SRC-#{index}"],
      origin: "deterministic_derived",
      confidence: 1.0
    }
  end

  defp edge_indexes(1), do: []
  defp edge_indexes(count), do: 1..(count - 1)

  defp contract do
    %{
      interface_key: "iface.generated",
      kind: "api",
      stability: "internal_cross_slice",
      lock_level: "review_required",
      compatibility_policy: "compatible_superset",
      owner_slice_key: "SLC-1",
      version: "1"
    }
  end

  defp provider_binding, do: %{slice_key: "SLC-1", interface_key: "iface.generated", direction: "provides"}

  defp consumer_bindings(count) do
    Enum.map(1..count, fn index ->
      %{slice_key: "SLC-#{index}", interface_key: "iface.generated", direction: "requires", required_version_range: ">=1 <2"}
    end)
  end

  defp graph_fixture(count, work_edges) do
    %{
      approved_scope_globs: ["app/**"],
      requirements: Enum.map(1..count, &%{key: "REQ-#{&1}"}),
      acceptance_criteria: Enum.map(1..count, &%{key: "AC-#{&1}", requirement_ref: "REQ-#{&1}"}),
      obligations: Enum.map(1..count, &%{"acceptance_ref" => "AC-#{&1}"}),
      slices: Enum.map(1..count, &slice/1),
      atomicity_groups: [%{key: "ATOMIC-GEN", member_keys: Enum.map(1..count, &"SLC-#{&1}")}],
      work_dependencies: work_edges
    }
  end

  defp artifact_inputs(count) do
    Enum.map(1..count, fn index ->
      %{
        artifact_id: "artifact:SLC-#{index}",
        inputs: [
          %{subject_kind: "plan_revision", subject_id: "plan-#{index}", role: "semantic", digest: digest("plan-#{index}")}
        ]
      }
    end)
  end

  defp package_input do
    %{
      normalized_plan: %{},
      claims: [],
      constraints: [],
      candidate_comparison: [],
      work_graph: %{},
      interfaces: [],
      decisions: [],
      derivation_graph: [],
      structural_dry_run: %{},
      scope_delta: :scope_preserved,
      oracle_warnings: []
    }
  end

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
