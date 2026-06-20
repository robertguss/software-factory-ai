defmodule Conveyor.Stations.RecordEvidence do
  @moduledoc "Station wrapper for recording machine evidence from agent and verification output."

  use Conveyor.Station, station: "record_evidence"

  alias Conveyor.Evidence.Recorder
  alias Conveyor.Factory
  alias Conveyor.Factory.{AgentBrief, PatchSet}

  @impl Conveyor.Station
  def run(input, context) do
    patch_set = patch_set!(get(input, "patch_set_id"))
    verification_result = get(input, "verification_result") || %{}

    result =
      Recorder.record!(
        context.run_attempt,
        patch_set,
        acceptance_criteria(context.run_attempt.slice_id),
        verification_result,
        blob_root: get(input, "blob_root") || ".conveyor/blobs"
      )

    {:ok,
     %{
       "evidence_id" => result.evidence.id,
       "projection_path" => result.projection.projection_path,
       "security_findings" => result.security_findings
     }}
  end

  defp patch_set!(nil), do: raise(ArgumentError, "record_evidence requires patch_set_id")

  defp patch_set!(id) do
    PatchSet
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == id)) ||
      raise ArgumentError, "PatchSet #{id} was not found"
  end

  defp acceptance_criteria(slice_id) do
    AgentBrief
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.slice_id == slice_id))
    |> Enum.sort_by(&{&1.version, DateTime.to_unix(&1.locked_at, :microsecond)}, :desc)
    |> List.first()
    |> case do
      %AgentBrief{} = brief -> brief.acceptance_criteria
      nil -> []
    end
  end

  defp get(input, key), do: Map.get(input, key) || Map.get(input, String.to_atom(key))
end
