defmodule Conveyor.Jobs.RunGateCanary do
  @moduledoc """
  Runs the gate-canary fixture suite through the gate-only path.
  """

  use Oban.Worker, queue: :gate, max_attempts: 1

  alias Conveyor.Artifacts.BlobStore
  alias Conveyor.Factory
  alias Conveyor.Factory.Artifact
  alias Conveyor.Jobs.RunGate

  @schema_version "conveyor.gate_canary_run@1"
  @default_manifest "samples/tasks_service/.conveyor/canary/mutants.json"

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    run!(Map.new(args || %{}))
    :ok
  end

  @spec run!(map() | keyword()) :: map()
  def run!(opts \\ []) do
    opts = Map.new(opts)

    manifest_path =
      Map.get(opts, :manifest_path, Map.get(opts, "manifest_path", @default_manifest))

    manifest = load_manifest!(manifest_path)
    stages = Map.get(opts, :stages, Map.get(opts, "stages", []))
    gate_opts = Map.get(opts, :gate_opts, Map.get(opts, "gate_opts", []))
    base_context = Map.get(opts, :context, Map.get(opts, "context", %{}))

    known_good = run_case!(manifest["known_good"], :known_good, base_context, stages, gate_opts)

    mutants =
      manifest
      |> Map.fetch!("mutants")
      |> Enum.filter(& &1["enabled"])
      |> Enum.map(&run_case!(&1, :mutant, base_context, stages, gate_opts))

    summary = summary(manifest, manifest_path, known_good, mutants)
    artifact = maybe_write_artifact(summary, opts)

    summary
    |> Map.put("artifact_ref", value(artifact, :projection_path))
    |> Map.put("blob_ref", value(artifact, :blob_ref))
  end

  defp run_case!(fixture, kind, base_context, stages, gate_opts) do
    expected = fixture["expected_catch"] || %{}

    context =
      base_context
      |> Map.put(:patch_set, %{
        source: :canary,
        kind: kind,
        id: fixture["id"],
        patch_ref: fixture["patch_ref"],
        expected_catch: expected,
        valid_stricter_categories: fixture["valid_stricter_categories"] || []
      })
      |> Map.put(:canary_fixture, fixture)

    result = RunGate.run_gate_only!(context, stages, gate_opts)
    case_summary(fixture, kind, result)
  end

  defp case_summary(fixture, :known_good, result) do
    %{
      "id" => fixture["id"],
      "kind" => "known_good",
      "patch_ref" => fixture["patch_ref"],
      "gate_passed" => result.passed?,
      "outcome" => if(result.passed?, do: "passed", else: "false_positive"),
      "matched_expected" => result.passed?,
      "expected_catch" => nil,
      "stages" => stage_maps(result.stages),
      "findings" => result.findings
    }
  end

  defp case_summary(fixture, :mutant, result) do
    expected = fixture["expected_catch"]
    matched? = not result.passed? and expected_match?(result, expected, fixture)

    outcome =
      cond do
        result.passed? -> "false_negative"
        matched? -> "rejected_expected"
        true -> "rejected_unexpected"
      end

    %{
      "id" => fixture["id"],
      "kind" => "mutant",
      "patch_ref" => fixture["patch_ref"],
      "gate_passed" => result.passed?,
      "outcome" => outcome,
      "matched_expected" => matched?,
      "expected_catch" => expected,
      "stages" => stage_maps(result.stages),
      "findings" => result.findings
    }
  end

  defp expected_match?(result, expected, fixture) do
    categories = Enum.map(result.findings, & &1["category"])
    stage_keys = Enum.map(result.stages, & &1.key)
    stricter = fixture["valid_stricter_categories"] || []

    expected["category"] in categories or
      expected["stage"] in stage_keys or
      Enum.any?(stricter, &(&1 in categories))
  end

  defp summary(manifest, manifest_path, known_good, mutants) do
    %{
      "schema_version" => @schema_version,
      "suite_version" => manifest["suite_version"],
      "manifest_ref" => manifest_path,
      "project_key" => manifest["project_key"],
      "known_good" => known_good,
      "mutants" => mutants,
      "case_count" => 1 + length(mutants),
      "false_positive_count" => if(known_good["outcome"] == "false_positive", do: 1, else: 0),
      "false_negative_count" => Enum.count(mutants, &(&1["outcome"] == "false_negative")),
      "unexpected_rejection_count" =>
        Enum.count(mutants, &(&1["outcome"] == "rejected_unexpected")),
      "passed" =>
        known_good["outcome"] == "passed" and
          Enum.all?(mutants, &(&1["outcome"] == "rejected_expected"))
    }
  end

  defp maybe_write_artifact(summary, opts) do
    run_attempt_id = value(opts, :run_attempt_id)
    blob_root = value(opts, :blob_root)

    if run_attempt_id && blob_root do
      content = Jason.encode!(summary, pretty: true)
      blob = BlobStore.write!(content, blob_root: blob_root)

      Ash.create!(
        Artifact,
        %{
          run_attempt_id: run_attempt_id,
          kind: "canary_run",
          media_type: "application/json",
          projection_path: "canary/mutants.json",
          blob_ref: blob.ref,
          sha256: blob.sha256,
          raw_sha256: blob.sha256,
          size_bytes: blob.size_bytes,
          subject_kind: "gate_canary",
          producer: inspect(__MODULE__),
          schema_version: @schema_version,
          sensitivity: :public
        },
        domain: Factory
      )
    end
  end

  defp load_manifest!(manifest_path) do
    manifest_path
    |> File.read!()
    |> Jason.decode!()
  end

  defp stage_maps(stages) do
    Enum.map(stages, fn stage ->
      %{
        "key" => stage.key,
        "status" => Atom.to_string(stage.status),
        "required" => stage.required?,
        "findings" => stage.findings
      }
    end)
  end

  defp value(nil, _key), do: nil

  defp value(map, key) when is_map(map),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp value(_value, _key), do: nil
end
