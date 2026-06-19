defmodule Conveyor.Eval.VerifyStation do
  @moduledoc """
  Verification station for the Golden Thread (B2): runs the sample's pytest in the
  (now agent-patched) workspace via `Conveyor.Eval.ToolchainRunner` and emits the
  real `verification_result` the gate consumes — honest evidence, no injected
  fixture. The station always succeeds (it produces evidence); the gate, run by the
  harness, decides PASS/FAIL.
  """

  use Conveyor.Station, station: "verify"

  alias Conveyor.Eval.{ToolchainRunner, Workspace}

  @impl Conveyor.Station
  def run(input, _context) do
    workspace_path = get(input, "workspace_path")
    plan = YamlElixir.read_from_file!(get(input, "plan_path"))

    verification_result =
      ToolchainRunner.verification_result(workspace_path, plan, Workspace.venv_opts())

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
       artifacts: [artifact]
     }}
  end

  defp get(input, key), do: Map.get(input, key) || Map.get(input, String.to_atom(key))
end
