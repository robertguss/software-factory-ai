defmodule Conveyor.Stations.Verify do
  @moduledoc "Station wrapper for running locked verification commands."

  use Conveyor.Station, station: "verify"

  alias Conveyor.Eval.{ToolchainRunner, Workspace}
  alias Conveyor.Factory
  alias Conveyor.Factory.Policy
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Factory.ToolchainProfile
  alias Conveyor.Gate.IntegrityEvidence
  alias Conveyor.Verification.CommandSuiteRunner
  alias Conveyor.Verification.EngineDispatch

  @impl Conveyor.Station
  def run(input, context) do
    backend = backend(get(input, "backend"))

    verification_result = verification_result(input, context)

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

  # tt6v.1/tt6v.2: the verify station runs verification through one of two engines behind the same
  # station output, chosen by the toolchain profile's language (EngineDispatch). python (and the
  # absent/default case) use the pytest-specific ToolchainRunner — the sample-python path is
  # unchanged; any other language uses the generic CommandSuiteRunner, which executes the slice's
  # locked command_specs via the trusted CommandRunner/ToolExecutor policy path.
  defp verification_result(input, context) do
    case EngineDispatch.engine_for(language_for(input, context)) do
      :command -> generic_verification_result(input, context)
      :pytest -> pytest_verification_result(input)
    end
  end

  # Language resolves from an explicit input override (tests / assembly), else the profile linked to
  # the run (run_attempt -> run_spec -> toolchain_profile), else python.
  defp language_for(input, context) do
    get(input, "language") || profile_language(context) || "python"
  end

  defp profile_language(%{run_attempt: %{run_spec_id: run_spec_id}})
       when is_binary(run_spec_id) do
    with %RunSpec{toolchain_profile_id: profile_id} when is_binary(profile_id) <-
           get_record(RunSpec, run_spec_id),
         %ToolchainProfile{language: language} <- get_record(ToolchainProfile, profile_id) do
      language
    else
      _ -> nil
    end
  end

  defp profile_language(_context), do: nil

  defp get_record(resource, id) do
    case Ash.get(resource, id, domain: Factory) do
      {:ok, record} -> record
      _ -> nil
    end
  end

  defp pytest_verification_result(input) do
    ToolchainRunner.verification_result(
      get(input, "workspace_path"),
      get(input, "plan"),
      runner_opts(input)
    )
  end

  defp generic_verification_result(input, context) do
    workspace_path = get(input, "workspace_path")
    policy = get(input, "policy") || resolve_policy!(context)
    commands = (get(input, "plan") || %{})["verification_commands"] || []

    CommandSuiteRunner.verification_result(
      commands,
      workspace_path,
      policy,
      command_opts(input, context)
    )
  end

  defp command_opts(input, context) do
    [
      blob_root: get(input, "blob_root"),
      run_attempt_id: run_attempt_id(context),
      project_id: get(input, "project_id")
    ]
    |> maybe_put(:exec, get(input, "exec"))
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end

  # The verify profile's Policy loaded for this run (fail closed — generic verification cannot run
  # without a policy to check its argv against). Tests pass `policy` directly in the input.
  defp resolve_policy!(_context) do
    Policy
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.profile == :verify)) ||
      raise ArgumentError, "no :verify Policy loaded for generic verification (tt6v.1)"
  end

  defp run_attempt_id(%{run_attempt: %{id: id}}), do: id
  defp run_attempt_id(_context), do: nil

  # Backend/network/docker_image/source_root flow from the station input so the
  # production loop stays :local by default (unchanged) and the live demo can opt
  # into the hermetic docker backend.
  defp runner_opts(input) do
    input
    |> get("workspace_path")
    |> venv_opts_for()
    |> Keyword.merge(test_refs: get(input, "test_refs") || [])
    |> maybe_put(:backend, backend(get(input, "backend")))
    |> maybe_put(:network, get(input, "network"))
    |> maybe_put(:docker_image, get(input, "docker_image"))
    |> maybe_put(:source_root, get(input, "source_root"))
  end

  # 8hx7 (hermeticity): resolve the pytest venv from the slice's OWN workspace, not the
  # foreign samples/tasks_service default — the gate must not depend on a sibling sample's
  # venv. nil workspace -> no venv_bin (matches the station's nil-as-absent style and keeps
  # resolution hermetic; the default would re-introduce the foreign-sample dependency).
  @doc false
  def venv_opts_for(nil), do: []
  def venv_opts_for(workspace_path), do: Workspace.venv_opts(workspace_path)

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
