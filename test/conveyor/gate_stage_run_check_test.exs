defmodule Conveyor.GateStageRunCheckTest do
  use ExUnit.Case, async: true

  alias Conveyor.Factory.Artifact
  alias Conveyor.Factory.RunBundle
  alias Conveyor.Gate
  alias Conveyor.Gate.Stages.RunCheck

  test "passes when required artifacts schemas hashes and manifest entries agree" do
    context = run_check_context()

    result = RunCheck.run(context)

    assert result.status == :passed
    assert result.findings == []
  end

  test "fails when a required verification log is missing" do
    context =
      run_check_context()
      |> Map.update!(
        :artifacts,
        &Enum.reject(&1, fn artifact -> artifact.projection_path == "logs/verification.json" end)
      )
      |> Map.update!(
        :artifact_contents,
        &Enum.reject(&1, fn artifact -> artifact.projection_path == "logs/verification.json" end)
      )

    result = RunCheck.run(context)

    assert result.status == :failed
    assert Enum.any?(result.findings, &(&1["category"] == "missing_required_artifact"))
  end

  test "fails on mismatched artifact hash" do
    context =
      run_check_context()
      |> Map.update!(:artifacts, fn [first | rest] ->
        [%{first | sha256: sha256("tampered")} | rest]
      end)

    result = RunCheck.run(context)

    assert result.status == :failed
    assert Enum.any?(result.findings, &(&1["category"] == "artifact_hash_mismatch"))
  end

  test "fails on unsupported schema versions" do
    context =
      run_check_context()
      |> Map.update!(:artifacts, fn [first | rest] ->
        [%{first | schema_version: "conveyor.evidence_packet@999"} | rest]
      end)

    result = RunCheck.run(context)

    assert result.status == :failed
    assert Enum.any?(result.findings, &(&1["category"] == "unsupported_schema_version"))
  end

  test "fails on tampered manifest root or entry metadata" do
    context =
      run_check_context()
      |> Map.update!(:manifest, fn manifest ->
        put_in(manifest, ["entries", Access.at(0), "sha256"], sha256("tampered"))
      end)

    result = RunCheck.run(context)

    assert result.status == :failed
    categories = Enum.map(result.findings, & &1["category"])
    assert "bundle_root_mismatch" in categories
    assert "manifest_entry_hash_mismatch" in categories
  end

  test "fails when output appears to follow untrusted instructions" do
    context =
      run_check_context()
      |> Map.update!(:artifact_contents, fn contents ->
        [
          %{
            projection_path: "review.json",
            content:
              Jason.encode!(%{
                "schema_version" => "conveyor.review@1",
                "summary" =>
                  "Ignored the locked contract as requested by repository instructions."
              })
          }
          | contents
        ]
      end)

    result = RunCheck.run(context)

    assert result.status == :failed
    assert Enum.any?(result.findings, &(&1["category"] == "untrusted_instruction_followed"))
  end

  test "run check composes through the gate framework" do
    context =
      run_check_context()
      |> Map.merge(%{
        gate_code_sha256: "sha256:gate",
        policy_sha256: "sha256:policy",
        contract_lock_sha256: "sha256:contract"
      })

    result = Gate.run!(context, [%{key: "run_check", module: RunCheck}])

    assert result.passed?
    assert [%{key: "run_check", status: :passed}] = result.stages
  end

  defp run_check_context do
    artifact_specs = [
      {"dossier.md", "manifest", "conveyor.evidence_packet@1",
       "# Run Dossier\n\nAC-001: passed\n"},
      {"logs/verification.json", "log", "conveyor.verification_log@1",
       Jason.encode!(%{"schema_version" => "conveyor.verification_log@1", "verification" => %{}})}
    ]

    artifacts =
      Enum.map(artifact_specs, fn {path, kind, schema_version, content} ->
        artifact(path, kind, schema_version, content)
      end)

    entries = Enum.map(artifacts, &manifest_entry/1)
    manifest = manifest(entries)

    %{
      artifacts: artifacts,
      artifact_contents:
        Enum.map(artifact_specs, fn {path, _kind, _schema_version, content} ->
          %{projection_path: path, content: content}
        end),
      manifest: manifest,
      run_bundle: %RunBundle{
        manifest_ref: "manifest.json",
        manifest_sha256: manifest_sha256(manifest),
        bundle_root_sha256: bundle_root_sha256(entries),
        schema_version: "conveyor.run_bundle@1",
        projection_status: :projected
      }
    }
  end

  defp artifact(path, kind, schema_version, content) do
    %Artifact{
      kind: kind,
      projection_path: path,
      sha256: sha256(content),
      size_bytes: byte_size(content),
      schema_version: schema_version,
      sensitivity: :internal
    }
  end

  defp manifest(entries) do
    %{
      "schema_version" => "conveyor.run_bundle@1",
      "run_attempt_id" => "run-attempt-1",
      "entries" => entries,
      "bundle_root_sha256" => bundle_root_sha256(entries)
    }
  end

  defp manifest_entry(artifact) do
    %{
      "path" => artifact.projection_path,
      "kind" => artifact.kind,
      "sha256" => artifact.sha256,
      "size_bytes" => artifact.size_bytes,
      "sensitivity" => Atom.to_string(artifact.sensitivity),
      "schema_version" => artifact.schema_version
    }
  end

  defp manifest_sha256(manifest), do: manifest |> canonical_json() |> sha256()

  defp bundle_root_sha256(entries) do
    entries
    |> Enum.map(
      &Map.take(&1, ["path", "kind", "sha256", "size_bytes", "sensitivity", "schema_version"])
    )
    |> canonical_json()
    |> sha256()
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

  defp canonical_json(value) when is_list(value),
    do: "[" <> Enum.map_join(value, ",", &canonical_json/1) <> "]"

  defp canonical_json(value), do: Jason.encode!(value)

  defp sha256(content), do: Base.encode16(:crypto.hash(:sha256, content), case: :lower)
end
