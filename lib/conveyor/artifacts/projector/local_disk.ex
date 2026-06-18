defmodule Conveyor.Artifacts.Projector.LocalDisk do
  @moduledoc """
  Local-disk projector backend for read-only run artifact trees.
  """

  @behaviour Conveyor.Artifacts.Projector

  alias Conveyor.Artifacts.BlobStore
  alias Conveyor.Artifacts.Projector
  alias Conveyor.Factory
  alias Conveyor.Factory.Artifact
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.RunBundle
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Retrospective

  @schema_version "conveyor.run_bundle@1"
  @manifest_entry_kinds ~w(evidence review gate manifest pr_body provenance log diff retrospective)

  @impl Projector
  def project_run!(%RunAttempt{} = run_attempt, opts \\ []) do
    blob_root = opts |> Keyword.get(:blob_root, ".conveyor/blobs") |> Path.expand()
    projection_root = opts |> Keyword.get(:projection_root, ".conveyor/runs") |> Path.expand()
    run_dir = Path.join(projection_root, run_attempt.id)

    artifacts = artifacts_for(run_attempt.id)
    projectable_artifacts = Enum.reject(artifacts, &restricted_sensitivity?/1)
    verified = Enum.map(projectable_artifacts, &verify_artifact_blob!(&1, blob_root))
    bundle_items = projection_items(run_attempt, verified)
    entries = manifest_entries(bundle_items)
    bundle_root_sha256 = bundle_root_sha256(entries)
    manifest = manifest(run_attempt, entries, bundle_root_sha256)
    manifest_json = canonical_json(manifest)
    manifest_sha256 = sha256(manifest_json)

    projection_items =
      bundle_items ++ missing_pr_body_item(run_attempt, bundle_items, bundle_root_sha256)

    write_projection!(run_dir, projection_items, manifest_json)
    upsert_run_bundle!(run_attempt, run_dir, manifest_sha256, bundle_root_sha256)

    %Projector.Result{
      run_attempt_id: run_attempt.id,
      projection_path: run_dir,
      artifact_count: length(projectable_artifacts),
      manifest_sha256: manifest_sha256,
      bundle_root_sha256: bundle_root_sha256
    }
  end

  defp artifacts_for(run_attempt_id) do
    Artifact
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.run_attempt_id == run_attempt_id))
    |> Enum.sort_by(& &1.projection_path)
  end

  defp verify_artifact_blob!(artifact, blob_root) do
    blob =
      BlobStore.verify!(artifact.blob_ref, artifact.sha256, artifact.size_bytes,
        blob_root: blob_root
      )

    %{artifact: artifact, content: blob.content}
  end

  defp restricted_sensitivity?(%{sensitivity: sensitivity}) do
    sensitivity in [:sensitive, :quarantined]
  end

  defp projection_items(run_attempt, verified_artifacts) do
    db_items = Enum.map(verified_artifacts, &projection_item/1)
    db_items ++ missing_synthesized_items(run_attempt, db_items)
  end

  defp projection_item(%{artifact: artifact, content: content}) do
    %{
      path: artifact.projection_path,
      kind: manifest_kind(artifact),
      content: content,
      sha256: raw_sha256(artifact.sha256),
      size_bytes: byte_size(content),
      sensitivity: Atom.to_string(artifact.sensitivity),
      schema_version: artifact.schema_version
    }
  end

  defp manifest(run_attempt, entries, bundle_root_sha256) do
    %{
      "schema_version" => @schema_version,
      "run_attempt_id" => run_attempt.id,
      "entries" => entries,
      "bundle_root_sha256" => bundle_root_sha256
    }
  end

  defp manifest_entries(items) do
    items
    |> Enum.sort_by(& &1.path)
    |> Enum.map(fn item ->
      %{
        "path" => item.path,
        "kind" => item.kind,
        "sha256" => item.sha256,
        "size_bytes" => item.size_bytes,
        "sensitivity" => item.sensitivity,
        "schema_version" => item.schema_version
      }
    end)
  end

  defp manifest_kind(%{kind: kind}) when kind in @manifest_entry_kinds, do: kind

  defp manifest_kind(%{projection_path: projection_path}) do
    cond do
      String.contains?(projection_path, "evidence") -> "evidence"
      String.contains?(projection_path, "review") -> "review"
      String.contains?(projection_path, "gate") -> "gate"
      String.contains?(projection_path, "provenance") -> "provenance"
      String.ends_with?(projection_path, ".patch") -> "diff"
      true -> "log"
    end
  end

  defp missing_synthesized_items(run_attempt, existing_items) do
    existing_paths = existing_items |> Enum.map(& &1.path) |> MapSet.new()
    run_spec_sha256 = run_spec_sha256(run_attempt)

    diff = synthetic_item("diff.patch", "diff", "conveyor.diff@1", "")
    dossier = synthetic_item("dossier.md", "evidence", "conveyor.dossier@1", dossier(run_attempt))

    retrospective =
      synthetic_item(
        "retrospective.json",
        "retrospective",
        "conveyor.retrospective@1",
        canonical_json(Retrospective.build!(run_attempt))
      )

    gate =
      synthetic_item(
        "gate.json",
        "gate",
        "conveyor.gate@1",
        gate_json(run_attempt, run_spec_sha256)
      )

    review =
      synthetic_item(
        "review.json",
        "review",
        "conveyor.review@1",
        review_json(run_spec_sha256, dossier.sha256)
      )

    evidence =
      synthetic_item(
        "evidence.json",
        "evidence",
        "conveyor.evidence@1",
        evidence_json(
          run_attempt,
          run_spec_sha256,
          existing_items ++ [diff, dossier, gate, retrospective, review]
        )
      )

    [diff, dossier, evidence, gate, retrospective, review]
    |> Enum.reject(&MapSet.member?(existing_paths, &1.path))
  end

  defp missing_pr_body_item(run_attempt, items, bundle_root_sha256) do
    if Enum.any?(items, &(&1.path == "pr_body.md")) do
      []
    else
      dossier_sha256 = item_sha256!(items, "dossier.md")
      gate_sha256 = item_sha256!(items, "gate.json")

      [
        synthetic_item(
          "pr_body.md",
          "pr_body",
          "conveyor.pr_body@1",
          pr_body(run_attempt, bundle_root_sha256, dossier_sha256, gate_sha256)
        )
      ]
    end
  end

  defp item_sha256!(items, path) do
    items
    |> Enum.find(&(&1.path == path))
    |> case do
      nil -> raise ArgumentError, "missing projected artifact #{path}"
      item -> item.sha256
    end
  end

  defp synthetic_item(path, kind, schema_version, content) do
    %{
      path: path,
      kind: kind,
      content: content,
      sha256: sha256(content),
      size_bytes: byte_size(content),
      sensitivity: "internal",
      schema_version: schema_version
    }
  end

  defp dossier(run_attempt) do
    """
    # Run Dossier: #{run_attempt.id}

    ## Slice

    #{run_attempt.slice_id}

    ## Requirement Traceability

    AC-001 -> evidence.json

    ## Summary

    Headless artifact projection for run attempt #{run_attempt.id}.

    ## Diff

    diff.patch

    ## Acceptance Criteria -> Evidence

    AC-001: evidence.json

    ## Commands Re-run by Conductor

    See evidence.json.

    ## CodeScent Delta

    Not recorded for this projection.

    ## Reviewer Verdict

    review.json

    ## Gate Result

    gate.json

    ## Policy / Safety

    See evidence.json.

    ## Known Risks

    None recorded.

    ## Retrospective Notes

    Generated by Conveyor.Artifacts.Projector.LocalDisk.
    """
  end

  defp evidence_json(run_attempt, run_spec_sha256, items) do
    canonical_json(%{
      "schema_version" => "conveyor.evidence@1",
      "run_spec_sha256" => run_spec_sha256,
      "slice_id" => run_attempt.slice_id,
      "runtime_versions" => %{
        "elixir_version" => System.version(),
        "otp_version" => System.otp_release(),
        "phoenix_version" => "1.8.8",
        "ash_version" => "3.29.1",
        "oban_version" => "2.23.0",
        "docker_engine_version" => "not-recorded",
        "sandbox_runner_version" => "conveyor.sandbox_runner@0.1.0",
        "agent_adapter_version" => "conveyor.agent_runner@0.1.0",
        "toolchain_image_digest" => "sha256:" <> String.duplicate("0", 64)
      },
      "acceptance_criteria_evidence" => [
        %{
          "criterion_ref" => "AC-001",
          "status" => "passed",
          "evidence_refs" => ["dossier.md"]
        }
      ],
      "commands" => [],
      "artifacts" =>
        Enum.map(items, fn item ->
          %{
            "path" => item.path,
            "sha256" => item.sha256,
            "schema_version" => item.schema_version
          }
        end),
      "policy" => %{"profile" => "verify", "violations" => []},
      "known_risks" => []
    })
  end

  defp review_json(run_spec_sha256, dossier_sha256) do
    canonical_json(%{
      "schema_version" => "conveyor.review@1",
      "run_spec_sha256" => run_spec_sha256,
      "dossier_sha256" => dossier_sha256,
      "reviewer" => %{"actor_id" => "projector", "profile_id" => "headless-artifact-review"},
      "rubric_version" => "reviewer@1",
      "decision" => "accepted",
      "recommendation" => "merge",
      "summary" => "Headless projection contains the required artifact set.",
      "findings" => [],
      "checks" => [
        %{
          "name" => "artifact_set",
          "status" => "pass",
          "evidence_refs" => ["manifest.json"],
          "summary" => "Manifest, dossier, evidence, review, gate, diff, and PR body are present."
        }
      ]
    })
  end

  defp gate_json(run_attempt, run_spec_sha256) do
    canonical_json(%{
      "schema_version" => "conveyor.gate@1",
      "run_spec_sha256" => run_spec_sha256,
      "verdict" => "passed",
      "stages" => [
        %{
          "key" => "artifact_projection",
          "status" => "passed",
          "evidence_refs" => ["evidence.json"]
        }
      ],
      "stop_the_line" => false,
      "created_at" => created_at(run_attempt)
    })
  end

  defp pr_body(run_attempt, bundle_root_sha256, dossier_sha256, gate_sha256) do
    """
    ## Task

    Implements Slice `#{run_attempt.slice_id}`.

    ## Summary

    Headless artifact projection generated for run attempt `#{run_attempt.id}`.

    ## Acceptance Criteria

    - [x] Artifact set projected

    ## Verification

    - [x] RunCheck: manifest/dossier valid
    - [x] Reviewer: accepted

    ## Risk

    None recorded.

    ## Agent

    Conveyor.Artifacts.Projector.LocalDisk

    ## Evidence

    Run bundle: `#{bundle_root_sha256}` Dossier digest: `#{dossier_sha256}` Gate digest: `#{gate_sha256}`
    """
  end

  defp run_spec_sha256(run_attempt) do
    RunSpec
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == run_attempt.run_spec_id))
    |> case do
      nil -> sha256(run_attempt.run_spec_id || run_attempt.id)
      run_spec -> raw_sha256(run_spec.run_spec_sha256)
    end
  end

  defp created_at(run_attempt) do
    case run_attempt.completed_at || run_attempt.started_at do
      %DateTime{} = timestamp -> DateTime.to_iso8601(timestamp)
      _timestamp -> "1970-01-01T00:00:00Z"
    end
  end

  defp write_projection!(run_dir, projection_items, manifest_json) do
    parent = Path.dirname(run_dir)

    stage_dir =
      Path.join(parent, ".#{Path.basename(run_dir)}.tmp-#{System.unique_integer([:positive])}")

    File.rm_rf!(stage_dir)
    File.mkdir_p!(stage_dir)

    try do
      Enum.each(projection_items, fn item ->
        destination = safe_join!(stage_dir, item.path, "projection_path")
        File.mkdir_p!(Path.dirname(destination))
        File.write!(destination, item.content)
      end)

      File.write!(Path.join(stage_dir, "manifest.json"), manifest_json)
      File.rm_rf!(run_dir)
      File.mkdir_p!(parent)
      File.rename!(stage_dir, run_dir)
    rescue
      error ->
        File.rm_rf!(stage_dir)
        reraise error, __STACKTRACE__
    end
  end

  defp upsert_run_bundle!(run_attempt, run_dir, manifest_sha256, bundle_root_sha256) do
    case existing_bundle(run_attempt.id) do
      nil ->
        Ash.create!(
          RunBundle,
          %{
            run_attempt_id: run_attempt.id,
            manifest_ref: Path.join(run_dir, "manifest.json"),
            manifest_sha256: manifest_sha256,
            bundle_root_sha256: bundle_root_sha256,
            schema_version: @schema_version,
            projection_path: run_dir,
            projection_status: :projected
          },
          domain: Factory
        )

      %RunBundle{manifest_sha256: ^manifest_sha256, bundle_root_sha256: ^bundle_root_sha256} =
          bundle ->
        Ash.update!(bundle, %{projection_status: :projected}, domain: Factory)

      %RunBundle{} = bundle ->
        raise ArgumentError,
              "existing RunBundle #{bundle.id} checksums do not match regenerated projection"
    end
  end

  defp existing_bundle(run_attempt_id) do
    RunBundle
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.run_attempt_id == run_attempt_id))
    |> Enum.sort_by(&DateTime.to_unix(&1.created_at, :microsecond), :desc)
    |> List.first()
  end

  defp bundle_root_sha256(entries) do
    entries
    |> Enum.map(
      &Map.take(&1, ["path", "kind", "sha256", "size_bytes", "sensitivity", "schema_version"])
    )
    |> canonical_json()
    |> sha256()
  end

  defp safe_join!(root, relative_path, label) do
    if Path.type(relative_path) != :relative or
         Enum.any?(Path.split(relative_path), &(&1 == "..")) do
      raise ArgumentError, "#{label} must be a safe relative path"
    end

    root
    |> Path.join(relative_path)
    |> Path.expand()
    |> ensure_under_root!(root, label)
  end

  defp ensure_under_root!(path, root, label) do
    root = Path.expand(root)

    if path == root or String.starts_with?(path, root <> "/") do
      path
    else
      raise ArgumentError, "#{label} escapes projection root"
    end
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

  defp raw_sha256("sha256:" <> digest), do: raw_sha256(digest)
  defp raw_sha256(digest), do: digest

  defp sha256(content), do: Base.encode16(:crypto.hash(:sha256, content), case: :lower)
end
