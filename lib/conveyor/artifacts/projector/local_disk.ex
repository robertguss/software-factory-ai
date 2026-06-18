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

  @schema_version "conveyor.run_bundle@1"
  @manifest_entry_kinds ~w(evidence review gate manifest pr_body provenance log diff)

  @impl Projector
  def project_run!(%RunAttempt{} = run_attempt, opts \\ []) do
    blob_root = opts |> Keyword.get(:blob_root, ".conveyor/blobs") |> Path.expand()
    projection_root = opts |> Keyword.get(:projection_root, ".conveyor/runs") |> Path.expand()
    run_dir = Path.join(projection_root, run_attempt.id)

    artifacts = artifacts_for(run_attempt.id)
    projectable_artifacts = Enum.reject(artifacts, &restricted_sensitivity?/1)
    verified = Enum.map(projectable_artifacts, &verify_artifact_blob!(&1, blob_root))
    entries = manifest_entries(projectable_artifacts)
    bundle_root_sha256 = bundle_root_sha256(entries)
    manifest = manifest(run_attempt, entries, bundle_root_sha256)
    manifest_json = canonical_json(manifest)
    manifest_sha256 = sha256(manifest_json)

    write_projection!(run_dir, verified, manifest_json)
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

  defp manifest(run_attempt, entries, bundle_root_sha256) do
    %{
      "schema_version" => @schema_version,
      "run_attempt_id" => run_attempt.id,
      "entries" => entries,
      "bundle_root_sha256" => bundle_root_sha256
    }
  end

  defp manifest_entries(artifacts) do
    Enum.map(artifacts, fn artifact ->
      %{
        "path" => artifact.projection_path,
        "kind" => manifest_kind(artifact),
        "sha256" => raw_sha256(artifact.sha256),
        "size_bytes" => artifact.size_bytes,
        "sensitivity" => Atom.to_string(artifact.sensitivity),
        "schema_version" => artifact.schema_version
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

  defp write_projection!(run_dir, verified_artifacts, manifest_json) do
    parent = Path.dirname(run_dir)

    stage_dir =
      Path.join(parent, ".#{Path.basename(run_dir)}.tmp-#{System.unique_integer([:positive])}")

    File.rm_rf!(stage_dir)
    File.mkdir_p!(stage_dir)

    try do
      Enum.each(verified_artifacts, fn %{artifact: artifact, content: content} ->
        destination = safe_join!(stage_dir, artifact.projection_path, "projection_path")
        File.mkdir_p!(Path.dirname(destination))
        File.write!(destination, content)
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
