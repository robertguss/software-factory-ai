defmodule Conveyor.Stations.Verify do
  @moduledoc "Station wrapper for running locked verification commands."

  use Conveyor.Station, station: "verify"

  alias Conveyor.Eval.{ToolchainRunner, Workspace}
  alias Conveyor.Gate.IntegrityEvidence

  # ADR-23: the probes the verify station can supply truthful observations for.
  @integrity_probes ["hermeticity", "source_mutation"]

  @impl Conveyor.Station
  def run(input, _context) do
    workspace_path = get(input, "workspace_path")
    plan = YamlElixir.read_from_file!(get(input, "plan_path"))

    verification_result =
      ToolchainRunner.verification_result(workspace_path, plan, runner_opts(input))

    artifact = %{
      kind: "verification_result",
      media_type: "application/json",
      projection_path: "verify/result.json",
      content: Jason.encode!(verification_result)
    }

    integrity_verdict =
      verification_result
      |> integrity_observations()
      |> IntegrityEvidence.verdict(required_probes: @integrity_probes)

    {:ok,
     %{
       "verification_result" => verification_result,
       "verification_status" => verification_result["status"],
       "integrity_verdict" => integrity_verdict,
       artifacts: [artifact]
     }}
  end

  # Backend/network/docker_image/source_root flow from the station input so the
  # production loop stays :local by default (unchanged) and the live demo can opt
  # into the hermetic docker backend.
  defp runner_opts(input) do
    Workspace.venv_opts()
    |> Keyword.merge(test_refs: get(input, "test_refs") || [])
    |> maybe_put(:backend, backend(get(input, "backend")))
    |> maybe_put(:network, get(input, "network"))
    |> maybe_put(:docker_image, get(input, "docker_image"))
    |> maybe_put(:source_root, get(input, "source_root"))
  end

  # ADR-23: the IntegritySentinel observations ToolchainRunner produced
  # (source-mutation always; hermeticity only under docker). Probes with no
  # observation evaluate to not_assessed -> non-blocking, so a local-backend run
  # stays not_assessed and only a genuine probe failure abstains.
  defp integrity_observations(verification_result),
    do: Map.get(verification_result, "integrity_observations", %{})

  defp backend("docker"), do: :docker
  defp backend(:docker), do: :docker
  defp backend(_other), do: nil

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp get(input, key), do: Map.get(input, key) || Map.get(input, String.to_atom(key))
end
