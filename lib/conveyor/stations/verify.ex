defmodule Conveyor.Stations.Verify do
  @moduledoc "Station wrapper for running locked verification commands."

  use Conveyor.Station, station: "verify"

  alias Conveyor.Eval.{ToolchainRunner, Workspace}
  alias Conveyor.Gate.IntegrityEvidence

  @impl Conveyor.Station
  def run(input, _context) do
    workspace_path = get(input, "workspace_path")
    plan = YamlElixir.read_from_file!(get(input, "plan_path"))
    backend = backend(get(input, "backend"))

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
      |> IntegrityEvidence.verdict(required_probes: integrity_probes(backend))

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

  # ADR-23 / M4: the IntegritySentinel observations ToolchainRunner produced
  # (source-mutation always; hermeticity only under docker). On :local only
  # source_mutation is REQUIRED (see integrity_probes/1), so a clean run is genuinely
  # "trustworthy" and a real production-source mutation -> "untrustworthy" -> abstain.
  defp integrity_observations(verification_result),
    do: Map.get(verification_result, "integrity_observations", %{})

  defp backend("docker"), do: :docker
  defp backend(:docker), do: :docker
  defp backend(_other), do: nil

  # M4 (integrity un-laundering): the integrity probes REQUIRED for a "trustworthy" verdict,
  # per backend. source_mutation is backend-agnostic (always supplied); hermeticity is only
  # genuinely assessable under docker, so on :local it is NOT required (declared
  # not-assessable). A clean source_mutation alone -> "trustworthy"; a real production-source
  # mutation -> "untrustworthy". This is what lets integrity be un-laundered (TrustEvidence)
  # without parking the local-backend reference.
  defp integrity_probes(:docker), do: ["hermeticity", "source_mutation"]
  defp integrity_probes(_local), do: ["source_mutation"]

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp get(input, key), do: Map.get(input, key) || Map.get(input, String.to_atom(key))
end
