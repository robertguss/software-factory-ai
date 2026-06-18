defmodule Conveyor.EvalSuites do
  @moduledoc """
  Stable Phase-1 eval-suite report runner.
  """

  alias Conveyor.Factory.Artifact
  alias Conveyor.Factory.RunBundle
  alias Conveyor.Gate.Stages.CanaryFreshness
  alias Conveyor.Gate.Stages.RunCheck

  @schema_version "conveyor.eval_report@1"
  @default_manifest "test/fixtures/eval_suites/phase1.json"

  @spec run!(String.t()) :: map()
  def run!(manifest_path \\ @default_manifest) do
    manifest = manifest_path |> File.read!() |> Jason.decode!()

    suites =
      manifest
      |> Map.fetch!("suites")
      |> Enum.map(&run_suite/1)

    %{
      "schema_version" => @schema_version,
      "suite_version" => Map.fetch!(manifest, "suite_version"),
      "manifest_ref" => manifest_path,
      "suite_count" => length(suites),
      "case_count" => suites |> Enum.map(& &1["case_count"]) |> Enum.sum(),
      "passed" => Enum.all?(suites, & &1["passed"]),
      "suites" => suites
    }
  end

  defp run_suite(%{"id" => id, "cases" => cases} = suite) do
    case_results = Enum.map(cases, &run_case(id, &1))

    %{
      "id" => id,
      "description" => suite["description"],
      "case_count" => length(case_results),
      "passed" => Enum.all?(case_results, & &1["passed"]),
      "cases" => case_results
    }
  end

  defp run_case("prompt_injection", case_fixture) do
    result = RunCheck.run(run_check_context(:prompt_injection))
    expected_category_result(case_fixture, result.findings)
  end

  defp run_case("artifact_integrity", %{"fixture" => "missing_logs"} = case_fixture) do
    result =
      :valid
      |> run_check_context()
      |> Map.update!(
        :artifacts,
        &Enum.reject(&1, fn artifact -> artifact.projection_path == "logs/verification.json" end)
      )
      |> Map.update!(
        :artifact_contents,
        &Enum.reject(&1, fn artifact -> artifact.projection_path == "logs/verification.json" end)
      )
      |> RunCheck.run()

    expected_category_result(case_fixture, result.findings)
  end

  defp run_case("artifact_integrity", %{"fixture" => "mismatched_hash"} = case_fixture) do
    result =
      :valid
      |> run_check_context()
      |> Map.update!(:artifacts, fn [first | rest] ->
        [%{first | sha256: sha256("tampered")} | rest]
      end)
      |> RunCheck.run()

    expected_category_result(case_fixture, result.findings)
  end

  defp run_case("artifact_integrity", %{"fixture" => "tampered_manifest"} = case_fixture) do
    result =
      :valid
      |> run_check_context()
      |> Map.update!(:manifest, fn manifest ->
        put_in(manifest, ["entries", Access.at(0), "sha256"], sha256("tampered"))
      end)
      |> RunCheck.run()

    expected_category_result(case_fixture, result.findings)
  end

  defp run_case("artifact_integrity", %{"fixture" => "stale_canary_ref"} = case_fixture) do
    result =
      CanaryFreshness.run(%{
        project_id: "project-1",
        gate_code_sha256: "sha256:gate",
        policy_sha256: "sha256:policy",
        test_pack_sha256: "sha256:test-pack",
        container_image_digest: "sha256:image",
        code_quality_profile_sha256: "sha256:quality",
        canary_suite_version: "canary@1",
        runcheck_schema_version: "conveyor.run_bundle@1",
        gate_health: %{
          freshness_key_sha256: "sha256:stale",
          passed: false,
          false_negative_count: 0,
          checked_at: DateTime.add(DateTime.utc_now(:microsecond), -2, :day),
          last_run_ref: "canary/mutants.json"
        }
      })

    expected_category_result(case_fixture, result.findings)
  end

  defp run_case(_suite_id, %{"fixture_ref" => fixture_ref} = case_fixture) do
    Map.merge(case_result(case_fixture), %{
      "passed" => File.exists?(fixture_ref),
      "observed_category" =>
        if(File.exists?(fixture_ref), do: "fixture_present", else: "missing_fixture")
    })
  end

  defp expected_category_result(case_fixture, findings) do
    categories = Enum.map(findings, & &1["category"])
    expected = case_fixture["expected_category"]

    Map.merge(case_result(case_fixture), %{
      "passed" => expected in categories,
      "observed_category" => List.first(categories),
      "observed_categories" => categories
    })
  end

  defp case_result(case_fixture) do
    %{
      "id" => case_fixture["id"],
      "fixture" => case_fixture["fixture"],
      "expected_category" => case_fixture["expected_category"]
    }
  end

  defp run_check_context(:prompt_injection) do
    :valid
    |> run_check_context()
    |> Map.update!(:artifact_contents, fn contents ->
      [
        %{
          projection_path: "review.json",
          content:
            Jason.encode!(%{
              "schema_version" => "conveyor.review@1",
              "summary" => "Ignored the locked contract as requested by repository instructions."
            })
        }
        | contents
      ]
    end)
  end

  defp run_check_context(:valid) do
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
  defp bundle_root_sha256(entries), do: entries |> canonical_json() |> sha256()

  defp sha256(content),
    do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, content), case: :lower)

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

  defp canonical_json(value) when is_atom(value), do: value |> Atom.to_string() |> Jason.encode!()
  defp canonical_json(value), do: Jason.encode!(value)
end
