defmodule Conveyor.Factory.RunSpecTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.Factory
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Factory.Slice
  alias Conveyor.Factory.ToolchainProfile

  setup do
    project =
      Ash.create!(
        Project,
        %{
          name: "RunSpec sample",
          local_path: "/tmp/run-spec-sample",
          default_branch: "main"
        },
        domain: Factory
      )

    toolchain =
      Ash.create!(
        ToolchainProfile,
        %{
          project_id: project.id,
          key: "sample-python-runner",
          image_ref: "ghcr.io/conveyor/sample-python-runner:2026-06-01",
          image_digest: digest("image"),
          dependency_lock_refs: ["requirements.lock"],
          cache_policy: %{"mode" => "read_only"}
        },
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "RunSpec plan",
          intent: "Create immutable execution capsules.",
          source_document: "docs/plan.md",
          normalized_contract: %{"schema_version" => "conveyor.plan@1"},
          contract_sha256: digest("plan")
        },
        domain: Factory
      )

    epic =
      Ash.create!(
        Epic,
        %{plan_id: plan.id, title: "RunSpec epic", description: "RunSpec resources."},
        domain: Factory
      )

    slice =
      Ash.create!(Slice, %{epic_id: epic.id, title: "RunSpec slice", position: 1},
        domain: Factory
      )

    %{slice: slice, toolchain: toolchain}
  end

  test "creates immutable RunSpecs with a valid embedded station plan", %{
    slice: slice,
    toolchain: toolchain
  } do
    attrs = run_spec_attrs(slice.id, toolchain.id, "run-spec-1", 1)

    run_spec = Ash.create!(RunSpec, attrs, domain: Factory)
    assert run_spec.station_plan["schema_version"] == "conveyor.station_plan@1"

    assert run_spec.station_plan["stations"] |> hd() |> get_in(["input", "run_spec_sha256"]) ==
             run_spec.run_spec_sha256

    assert_raise RuntimeError,
                 "Required primary update action for Conveyor.Factory.RunSpec.",
                 fn ->
                   Ash.update!(run_spec, %{base_commit: "changed"}, domain: Factory)
                 end

    next_run_spec =
      Ash.create!(RunSpec, run_spec_attrs(slice.id, toolchain.id, "run-spec-2", 2),
        domain: Factory
      )

    assert next_run_spec.run_spec_sha256 != run_spec.run_spec_sha256
  end

  test "enforces unique run_spec_sha256", %{slice: slice, toolchain: toolchain} do
    attrs = run_spec_attrs(slice.id, toolchain.id, "duplicate", 1)

    Ash.create!(RunSpec, attrs, domain: Factory)

    assert_raise Ash.Error.Invalid, fn ->
      Ash.create!(RunSpec, attrs, domain: Factory)
    end
  end

  test "rejects station plans missing run_spec_sha256 on station outputs", %{
    slice: slice,
    toolchain: toolchain
  } do
    attrs =
      slice.id
      |> run_spec_attrs(toolchain.id, "invalid-plan", 1)
      |> put_in([:station_plan, "stations", Access.at(0), "output"], %{"artifact_refs" => []})

    assert_raise Ash.Error.Invalid, fn ->
      Ash.create!(RunSpec, attrs, domain: Factory)
    end
  end

  defp run_spec_attrs(slice_id, toolchain_profile_id, seed, attempt_no) do
    run_spec_sha256 = digest(seed)

    %{
      slice_id: slice_id,
      attempt_no: attempt_no,
      run_spec_json_ref: "artifacts/run-specs/#{seed}.json",
      run_spec_sha256: run_spec_sha256,
      base_commit: "abc123",
      contract_lock_sha256: digest("contract-lock"),
      prompt_template_version: "implementation-prompt@1",
      agent_profile_snapshot: %{"adapter" => "pi", "model" => "gpt-5"},
      policy_sha256: digest("policy"),
      diff_policy_sha256: digest("diff-policy"),
      test_pack_sha256: digest("test-pack"),
      station_plan: station_plan(run_spec_sha256),
      station_plan_sha256: digest("station-plan-#{seed}"),
      toolchain_profile_id: toolchain_profile_id,
      container_image_ref: "ghcr.io/conveyor/sample-python-runner:2026-06-01",
      container_image_digest: digest("image"),
      sandbox_profile: "verify",
      budget_sha256: digest("budget"),
      code_quality_profile: "standard",
      canary_suite_version: "canary@1"
    }
  end

  defp station_plan(run_spec_sha256) do
    %{
      "schema_version" => "conveyor.station_plan@1",
      "stations" => [
        %{
          "key" => "implement",
          "kind" => "implementer",
          "input" => %{"run_spec_sha256" => run_spec_sha256, "artifact_refs" => []},
          "output" => %{"run_spec_sha256" => run_spec_sha256, "artifact_refs" => []}
        },
        %{
          "key" => "gate",
          "kind" => "gate",
          "input" => %{"run_spec_sha256" => run_spec_sha256, "artifact_refs" => []},
          "output" => %{"run_spec_sha256" => run_spec_sha256, "artifact_refs" => []}
        }
      ]
    }
  end

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
