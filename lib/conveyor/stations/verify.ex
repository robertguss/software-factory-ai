defmodule Conveyor.Stations.Verify do
  @moduledoc "Station wrapper for running locked verification commands."

  use Conveyor.Station, station: "verify"

  alias Conveyor.Eval.{ToolchainRunner, Workspace}
  alias Conveyor.Gate.IntegrityEvidence

  @impl Conveyor.Station
  def run(input, _context) do
    workspace_path = get(input, "workspace_path")
    plan = YamlElixir.read_from_file!(get(input, "plan_path"))

    verification_result =
      ToolchainRunner.verification_result(
        workspace_path,
        plan,
        Keyword.merge(Workspace.venv_opts(), test_refs: get(input, "test_refs") || [])
      )

    artifact = %{
      kind: "verification_result",
      media_type: "application/json",
      projection_path: "verify/result.json",
      content: Jason.encode!(verification_result)
    }

    {:ok,
     %{
       "verification_result" => verification_result,
       "verification_status" => verification_result["status"],
       "integrity_verdict" =>
         IntegrityEvidence.verdict(integrity_observations(verification_result)),
       artifacts: [artifact]
     }}
  end

  # ADR-23: the IntegritySentinel verdict flows verify -> output ->
  # `Conveyor.Gate.TrustEvidence` -> the gate. The path is live, but the verify
  # station has no *truthful* probe observations to supply yet, so the verdict is
  # `not_assessed` (which TrustEvidence treats as non-blocking — no false abstain).
  #
  # Populating real signal is a deliberate instrumentation effort: each
  # IntegritySentinel probe needs an observation that matches its exact expectation
  # — hermeticity wants 6 pinned controls (the toolchain only honestly pins
  # network/clock/rng/locale, not ordering/shared_state, and only blocks the
  # network under the docker backend); source-mutation/mount-boundary need the
  # sandbox to report writes; falsifier survival needs the contract's seeds run.
  # Claiming any of these without the instrumentation would overclaim, so they are
  # omitted (-> not_assessed) until their producers exist.
  defp integrity_observations(_verification_result), do: %{}

  defp get(input, key), do: Map.get(input, key) || Map.get(input, String.to_atom(key))
end
