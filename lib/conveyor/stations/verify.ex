defmodule Conveyor.Stations.Verify do
  @moduledoc "Station wrapper for running locked verification commands."

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
