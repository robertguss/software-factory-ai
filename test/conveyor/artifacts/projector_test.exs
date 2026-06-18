defmodule Conveyor.Artifacts.ProjectorTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.Artifacts.BlobStore
  alias Conveyor.Artifacts.Projector
  alias Conveyor.Factory
  alias Conveyor.Factory.Artifact
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.GateResult
  alias Conveyor.Factory.Incident
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.RunBundle
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Factory.Slice
  alias Conveyor.Factory.StationRun
  alias Conveyor.Factory.ToolInvocation

  defmodule RecordingBackend do
    @moduledoc false

    @behaviour Projector

    @impl Projector
    def project_run!(run_attempt, opts) do
      test_pid = Keyword.fetch!(opts, :test_pid)
      send(test_pid, {:project_run, run_attempt.id, opts})

      %Projector.Result{
        run_attempt_id: run_attempt.id,
        projection_path: "/tmp/recorded",
        artifact_count: 0,
        manifest_sha256: "sha256:manifest",
        bundle_root_sha256: "sha256:bundle"
      }
    end
  end

  setup do
    project =
      Ash.create!(
        Project,
        %{name: "Projector sample", local_path: "/tmp/projector-sample", default_branch: "main"},
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "Projector plan",
          intent: "Regenerate artifact projections.",
          source_document: "docs/plan.md",
          normalized_contract: %{"schema_version" => "conveyor.plan@1"},
          contract_sha256: digest("plan")
        },
        domain: Factory
      )

    epic =
      Ash.create!(Epic, %{plan_id: plan.id, title: "Projector epic", description: "Artifacts."},
        domain: Factory
      )

    slice =
      Ash.create!(Slice, %{epic_id: epic.id, title: "Projector slice", position: 1},
        domain: Factory
      )

    run_spec = Ash.create!(RunSpec, run_spec_attrs(slice.id), domain: Factory)

    run_attempt =
      Ash.create!(
        RunAttempt,
        %{
          slice_id: slice.id,
          run_spec_id: run_spec.id,
          attempt_no: 1,
          base_commit: "abc123",
          status: :planned,
          outcome: :none,
          orchestrator_version: "conveyor@0.1.0",
          trace_id: "trace-projector"
        },
        domain: Factory
      )

    station_run =
      Ash.create!(
        StationRun,
        %{
          run_attempt_id: run_attempt.id,
          slice_id: slice.id,
          station: "artifact",
          attempt_no: 1,
          station_spec_sha256: digest("station"),
          idempotency_key: "#{run_attempt.id}:artifact:#{digest("station")}:1",
          input_sha256: digest("input")
        },
        domain: Factory
      )

    %{
      blob_root: temp_dir!("blobs"),
      project: project,
      projection_root: temp_dir!("projection"),
      run_attempt: run_attempt,
      slice: slice,
      station_run: station_run
    }
  end

  test "regenerates a run projection from content-addressed blobs", %{
    blob_root: blob_root,
    projection_root: projection_root,
    run_attempt: run_attempt,
    station_run: station_run
  } do
    content = "pytest passed\n"
    sha256 = digest_bytes(content)
    blob = BlobStore.write!(content, blob_root: blob_root)

    create_artifact!(
      run_attempt,
      station_run,
      blob.ref,
      sha256,
      byte_size(content),
      "logs/pytest.txt"
    )

    first =
      Projector.project_run!(run_attempt,
        blob_root: blob_root,
        projection_root: projection_root
      )

    projected_file = Path.join([projection_root, run_attempt.id, "logs/pytest.txt"])
    assert File.read!(projected_file) == content
    assert first.artifact_count == 1

    assert [bundle] = Ash.read!(RunBundle, domain: Factory)
    assert bundle.projection_status == :projected
    assert bundle.bundle_root_sha256 == first.bundle_root_sha256

    File.rm_rf!(Path.join(projection_root, run_attempt.id))

    second =
      Projector.project_run!(run_attempt,
        blob_root: blob_root,
        projection_root: projection_root
      )

    assert File.read!(projected_file) == content
    assert second.manifest_sha256 == first.manifest_sha256
    assert second.bundle_root_sha256 == first.bundle_root_sha256
  end

  test "projects complete headless artifact set with schema-valid machine artifacts", %{
    blob_root: blob_root,
    projection_root: projection_root,
    run_attempt: run_attempt
  } do
    Projector.project_run!(run_attempt,
      blob_root: blob_root,
      projection_root: projection_root
    )

    run_dir = Path.join(projection_root, run_attempt.id)

    expected_paths = [
      "diff.patch",
      "dossier.md",
      "evidence.json",
      "gate.json",
      "manifest.json",
      "pr_body.md",
      "retrospective.json",
      "review.json"
    ]

    for path <- expected_paths do
      assert File.exists?(Path.join(run_dir, path))
    end

    manifest = read_json!(Path.join(run_dir, "manifest.json"))
    entry_paths = Enum.map(manifest["entries"], & &1["path"])

    assert entry_paths == [
             "diff.patch",
             "dossier.md",
             "evidence.json",
             "gate.json",
             "retrospective.json",
             "review.json"
           ]

    assert_schema_valid!(manifest, "conveyor.run_bundle@1")
    assert_schema_valid!(read_json!(Path.join(run_dir, "evidence.json")), "conveyor.evidence@1")
    assert_schema_valid!(read_json!(Path.join(run_dir, "review.json")), "conveyor.review@1")
    assert_schema_valid!(read_json!(Path.join(run_dir, "gate.json")), "conveyor.gate@1")

    retrospective = read_json!(Path.join(run_dir, "retrospective.json"))
    assert retrospective["schema_version"] == "conveyor.retrospective@1"
    assert retrospective["run_attempt_id"] == run_attempt.id
    assert retrospective["failure_taxonomy"]["run_category"] == "none"
    assert retrospective["swarm_readiness"]["passed"] == true
    assert retrospective["rework_handoff"]["template_version"] == "conveyor.rework_handoff@1"
  end

  test "retrospective captures timings failure taxonomy and canary stats", %{
    blob_root: blob_root,
    project: project,
    projection_root: projection_root,
    run_attempt: run_attempt,
    slice: slice,
    station_run: station_run
  } do
    run_attempt =
      Ash.update!(
        run_attempt,
        %{
          status: :failed,
          failure_category: "test_failure",
          started_at: ~U[2026-06-18 01:00:00.000000Z],
          completed_at: ~U[2026-06-18 01:03:00.000000Z]
        },
        domain: Factory
      )

    Ash.update!(
      station_run,
      %{
        status: :failed,
        started_at: ~U[2026-06-18 01:00:10.000000Z],
        completed_at: ~U[2026-06-18 01:01:40.000000Z],
        error_category: "pytest_failed",
        error_message: "expected task to be listed"
      },
      domain: Factory
    )

    Ash.create!(
      ToolInvocation,
      %{
        run_attempt_id: run_attempt.id,
        station_run_id: station_run.id,
        tool_name: "pytest",
        invocation_kind: "verify",
        command_spec: command_spec("pytest"),
        policy_profile: "verify",
        cwd: ".",
        env_keys: [],
        network_mode: :none,
        started_at: ~U[2026-06-18 01:00:20.000000Z],
        completed_at: ~U[2026-06-18 01:00:35.000000Z],
        exit_code: 1,
        duration_ms: 15_000,
        policy_decision: :allowed,
        status: :failed
      },
      domain: Factory
    )

    Ash.create!(
      GateResult,
      %{
        run_attempt_id: run_attempt.id,
        passed: false,
        stages: [%{"key" => "canary", "status" => "failed", "category" => "stale_canary"}],
        false_negative: true,
        gate_version: "gate@1",
        gate_code_sha256: "sha256:gate",
        policy_sha256: "sha256:policy",
        contract_lock_sha256: "sha256:contract",
        canary_suite_version: "canary@1"
      },
      domain: Factory
    )

    Ash.create!(
      Incident,
      %{
        project_id: project.id,
        slice_id: slice.id,
        run_attempt_id: run_attempt.id,
        severity: :warning,
        category: "schema_friction",
        description: "Review schema needed an adapter patch.",
        evidence_refs: ["review.json"],
        status: :open
      },
      domain: Factory
    )

    Projector.project_run!(run_attempt,
      blob_root: blob_root,
      projection_root: projection_root
    )

    retrospective = read_json!(Path.join([projection_root, run_attempt.id, "retrospective.json"]))

    assert retrospective["timings"]["run_duration_ms"] == 180_000

    assert [
             %{
               "station" => "artifact",
               "duration_ms" => 90_000,
               "error_category" => "pytest_failed"
             }
           ] =
             retrospective["timings"]["stations"]

    assert retrospective["failure_taxonomy"]["run_category"] == "test_failure"
    assert retrospective["failure_taxonomy"]["station_categories"] == ["pytest_failed"]
    assert retrospective["adapter_friction"]["failed_tool_invocations"] == 1
    assert retrospective["cost_estimate"]["token_count"] == nil
    assert retrospective["gate_canary"]["false_negative_count"] == 1
    assert retrospective["schema_friction"]["incident_count"] == 1
    assert retrospective["rework_handoff"]["next_actions"] != []
  end

  test "generates PR body with verification checklist and evidence digests", %{
    blob_root: blob_root,
    projection_root: projection_root,
    run_attempt: run_attempt
  } do
    result =
      Projector.project_run!(run_attempt,
        blob_root: blob_root,
        projection_root: projection_root
      )

    run_dir = Path.join(projection_root, run_attempt.id)
    manifest = read_json!(Path.join(run_dir, "manifest.json"))
    pr_body = File.read!(Path.join(run_dir, "pr_body.md"))
    dossier_sha256 = entry_for!(manifest["entries"], "dossier.md")["sha256"]
    gate_sha256 = entry_for!(manifest["entries"], "gate.json")["sha256"]

    for section <- [
          "## Task",
          "## Summary",
          "## Acceptance Criteria",
          "## Verification",
          "## Risk",
          "## Agent",
          "## Evidence"
        ] do
      assert pr_body =~ section
    end

    assert pr_body =~ "- [x] RunCheck: manifest/dossier valid"
    assert pr_body =~ "- [x] Reviewer: accepted"
    assert pr_body =~ "Run bundle: `#{result.bundle_root_sha256}`"
    assert pr_body =~ "Dossier digest: `#{dossier_sha256}`"
    assert pr_body =~ "Gate digest: `#{gate_sha256}`"
  end

  test "rejects corrupted blobs before writing projection files", %{
    blob_root: blob_root,
    projection_root: projection_root,
    run_attempt: run_attempt,
    station_run: station_run
  } do
    expected_sha256 = digest_bytes("expected")
    blob_ref = BlobStore.ref_for_sha256!(expected_sha256)
    corrupt_blob!(blob_root, blob_ref, "corrupted")

    create_artifact!(
      run_attempt,
      station_run,
      blob_ref,
      expected_sha256,
      byte_size("expected"),
      "logs/bad.txt"
    )

    assert_raise ArgumentError, ~r/digest mismatch/, fn ->
      Projector.project_run!(run_attempt,
        blob_root: blob_root,
        projection_root: projection_root
      )
    end

    refute File.exists?(Path.join([projection_root, run_attempt.id, "logs/bad.txt"]))
  end

  test "delegates to the selected projector backend", %{run_attempt: run_attempt} do
    result =
      Projector.project_run!(run_attempt,
        backend: RecordingBackend,
        test_pid: self(),
        projection_root: "/unused"
      )

    assert_receive {:project_run, run_attempt_id, opts}
    assert run_attempt_id == run_attempt.id
    refute Keyword.has_key?(opts, :backend)
    assert Keyword.fetch!(opts, :projection_root) == "/unused"
    assert result.projection_path == "/tmp/recorded"
  end

  test "regenerates the same tree and checksums from the same record", %{
    blob_root: blob_root,
    projection_root: projection_root,
    run_attempt: run_attempt,
    station_run: station_run
  } do
    create_blob_artifact!(
      blob_root,
      run_attempt,
      station_run,
      "review result\n",
      "review/result.txt"
    )

    create_blob_artifact!(
      blob_root,
      run_attempt,
      station_run,
      ~s({"status":"passed"}\n),
      "gate/result.json"
    )

    first =
      Projector.project_run!(run_attempt,
        blob_root: blob_root,
        projection_root: projection_root
      )

    run_dir = Path.join(projection_root, run_attempt.id)
    first_tree = tree_snapshot(run_dir)
    File.write!(Path.join(run_dir, "stale.txt"), "stale projection data")

    second =
      Projector.project_run!(run_attempt,
        blob_root: blob_root,
        projection_root: projection_root
      )

    manifest_path = Path.join(run_dir, "manifest.json")
    manifest_json = File.read!(manifest_path)
    manifest = Jason.decode!(manifest_json)
    projection_paths = Enum.map(manifest["entries"], & &1["path"])

    assert manifest["schema_version"] == "conveyor.run_bundle@1"
    assert manifest["run_attempt_id"] == run_attempt.id

    assert projection_paths == [
             "diff.patch",
             "dossier.md",
             "evidence.json",
             "gate.json",
             "gate/result.json",
             "retrospective.json",
             "review.json",
             "review/result.txt"
           ]

    assert entry_for!(manifest["entries"], "gate/result.json")["kind"] == "gate"
    assert entry_for!(manifest["entries"], "review/result.txt")["kind"] == "review"
    assert Enum.all?(manifest["entries"], &(&1["sha256"] =~ ~r/^[0-9a-f]{64}$/))
    assert manifest["bundle_root_sha256"] == bundle_root_sha256(manifest["entries"])
    assert first.manifest_sha256 == digest_bytes(manifest_json)
    assert first_tree == tree_snapshot(run_dir)
    refute File.exists?(Path.join(run_dir, "stale.txt"))
    assert second.manifest_sha256 == first.manifest_sha256
    assert second.bundle_root_sha256 == first.bundle_root_sha256
  end

  test "projects only allowed artifact sensitivities and keeps entry identity", %{
    blob_root: blob_root,
    projection_root: projection_root,
    run_attempt: run_attempt,
    station_run: station_run
  } do
    public =
      create_blob_artifact!(
        blob_root,
        run_attempt,
        station_run,
        "public artifact\n",
        "evidence/public.txt",
        sensitivity: :public
      )

    internal =
      create_blob_artifact!(
        blob_root,
        run_attempt,
        station_run,
        "internal artifact\n",
        "gate/internal.txt",
        sensitivity: :internal
      )

    redacted =
      create_blob_artifact!(
        blob_root,
        run_attempt,
        station_run,
        "redacted artifact\n",
        "review/redacted.txt",
        sensitivity: :redacted
      )

    create_blob_artifact!(
      blob_root,
      run_attempt,
      station_run,
      "sensitive artifact\n",
      "evidence/sensitive.txt",
      sensitivity: :sensitive
    )

    create_blob_artifact!(
      blob_root,
      run_attempt,
      station_run,
      "quarantined artifact\n",
      "evidence/quarantined.txt",
      sensitivity: :quarantined
    )

    result =
      Projector.project_run!(run_attempt,
        blob_root: blob_root,
        projection_root: projection_root
      )

    run_dir = Path.join(projection_root, run_attempt.id)
    manifest = File.read!(Path.join(run_dir, "manifest.json")) |> Jason.decode!()
    entries = manifest["entries"]
    projected_paths = Enum.map(entries, & &1["path"])
    projected_sha256s = MapSet.new(Enum.map(entries, & &1["sha256"]))

    assert result.artifact_count == 3

    assert projected_paths == [
             "diff.patch",
             "dossier.md",
             "evidence.json",
             "evidence/public.txt",
             "gate.json",
             "gate/internal.txt",
             "retrospective.json",
             "review.json",
             "review/redacted.txt"
           ]

    assert File.exists?(Path.join(run_dir, public.projection_path))
    assert File.exists?(Path.join(run_dir, internal.projection_path))
    assert File.exists?(Path.join(run_dir, redacted.projection_path))
    refute File.exists?(Path.join(run_dir, "evidence/sensitive.txt"))
    refute File.exists?(Path.join(run_dir, "evidence/quarantined.txt"))

    for artifact <- [public, internal, redacted] do
      assert MapSet.member?(projected_sha256s, artifact.sha256)
      assert Enum.any?(entries, &(&1["path"] == artifact.projection_path))
    end
  end

  defp create_artifact!(
         run_attempt,
         station_run,
         blob_ref,
         sha256,
         size_bytes,
         projection_path,
         opts \\ []
       ) do
    Ash.create!(
      Artifact,
      %{
        run_attempt_id: run_attempt.id,
        station_run_id: station_run.id,
        kind: "run-log",
        media_type: "text/plain",
        projection_path: projection_path,
        blob_ref: blob_ref,
        sha256: sha256,
        size_bytes: size_bytes,
        subject_kind: "run_attempt",
        producer: "gate",
        schema_version: "conveyor.artifact@1",
        sensitivity: Keyword.get(opts, :sensitivity, :internal)
      },
      domain: Factory
    )
  end

  defp command_spec(key) do
    %{
      "key" => key,
      "argv" => ["mix", "test"],
      "cwd" => ".",
      "profile" => "verify",
      "required" => true,
      "timeout_ms" => 120_000,
      "network" => "none",
      "env_allowlist" => [],
      "output_limit_bytes" => 2_000_000,
      "repeat" => 1,
      "flake_policy" => "fail_closed",
      "infra_retry_policy" => %{"max_attempts" => 1},
      "result_format" => "junit"
    }
  end

  defp create_blob_artifact!(
         blob_root,
         run_attempt,
         station_run,
         content,
         projection_path,
         opts \\ []
       ) do
    blob = BlobStore.write!(content, blob_root: blob_root)

    create_artifact!(
      run_attempt,
      station_run,
      blob.ref,
      blob.sha256,
      blob.size_bytes,
      projection_path,
      opts
    )
  end

  defp corrupt_blob!(blob_root, blob_ref, content) do
    path = BlobStore.path_for!(blob_ref, blob_root: blob_root)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
  end

  defp temp_dir!(label) do
    path =
      Path.join(
        System.tmp_dir!(),
        "conveyor-projector-#{label}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(path)
    path
  end

  defp tree_snapshot(root) do
    root
    |> Path.join("**/*")
    |> Path.wildcard()
    |> Enum.filter(&File.regular?/1)
    |> Enum.sort()
    |> Enum.map(fn path ->
      relative_path = Path.relative_to(path, root)
      {relative_path, File.read!(path) |> digest_bytes()}
    end)
  end

  defp read_json!(path), do: path |> File.read!() |> Jason.decode!()

  defp entry_for!(entries, path), do: Enum.find(entries, &(&1["path"] == path)) || flunk(path)

  defp assert_schema_valid!(json, schema_name) do
    schema =
      ["docs/schemas", "#{schema_name}.json"]
      |> Path.join()
      |> File.read!()
      |> Jason.decode!()

    root = JSV.build!(schema, warnings: :silent)
    assert {:ok, _validated} = JSV.validate(json, root)
  end

  defp bundle_root_sha256(entries) do
    entries
    |> Enum.map(
      &Map.take(&1, ["path", "kind", "sha256", "size_bytes", "sensitivity", "schema_version"])
    )
    |> canonical_json()
    |> digest_bytes()
  end

  defp canonical_json(value) when is_map(value) do
    body =
      value
      |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
      |> Enum.map(fn {key, nested} ->
        Jason.encode!(to_string(key)) <> ":" <> canonical_json(nested)
      end)
      |> Enum.join(",")

    "{" <> body <> "}"
  end

  defp canonical_json(value) when is_list(value) do
    "[" <> Enum.map_join(value, ",", &canonical_json/1) <> "]"
  end

  defp canonical_json(value), do: Jason.encode!(value)

  defp run_spec_attrs(slice_id) do
    run_spec_sha256 = digest("run-spec-projector")

    %{
      slice_id: slice_id,
      attempt_no: 1,
      run_spec_json_ref: "artifacts/run-specs/attempt-1.json",
      run_spec_sha256: run_spec_sha256,
      base_commit: "abc123",
      contract_lock_sha256: digest("contract-lock"),
      prompt_template_version: "implementation-prompt@1",
      agent_profile_snapshot: %{"adapter" => "pi"},
      policy_sha256: digest("policy"),
      diff_policy_sha256: digest("diff-policy"),
      test_pack_sha256: digest("test-pack"),
      station_plan: %{
        "schema_version" => "conveyor.station_plan@1",
        "stations" => [
          %{
            "key" => "artifact",
            "input" => %{"run_spec_sha256" => run_spec_sha256},
            "output" => %{"run_spec_sha256" => run_spec_sha256}
          }
        ]
      },
      station_plan_sha256: digest("station-plan"),
      container_image_ref: "ghcr.io/conveyor/sample-python-runner:2026-06-01",
      container_image_digest: digest("image"),
      sandbox_profile: "verify",
      budget_sha256: digest("budget"),
      code_quality_profile: "standard",
      canary_suite_version: "canary@1"
    }
  end

  defp digest(label), do: "sha256:" <> digest_bytes(label)
  defp digest_bytes(content), do: Base.encode16(:crypto.hash(:sha256, content), case: :lower)
end
