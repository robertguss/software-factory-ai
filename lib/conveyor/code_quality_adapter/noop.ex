defmodule Conveyor.CodeQualityAdapter.Noop do
  @moduledoc """
  Advisory adapter for demos that have no optional quality tooling installed.
  """

  @behaviour Conveyor.CodeQualityAdapter

  alias Conveyor.CodeQualityAdapter.Result

  @adapter_name "CodeQualityAdapter.Noop"

  @impl true
  def adapter_name, do: @adapter_name

  @impl true
  def adapter_contract do
    %{
      "deterministic_output" => true,
      "version_command" => [],
      "result_schema" => Result.schema_version(),
      "fixture_suite" => "quality_adapter_conformance",
      "threshold_policy" => %{"new_high_risk_findings" => 0},
      "advisory_only" => true
    }
  end

  @impl true
  def scan(project, opts \\ []) do
    Result.new!(
      adapter: @adapter_name,
      profile: Keyword.get(opts, :profile, project.code_quality_profile),
      status: :succeeded,
      findings_summary: Result.empty_summary(),
      new_high_risk_findings: 0,
      risks: [],
      suggested_validation: command_lines(project.command_specs),
      metadata: %{
        "adapter_contract" => adapter_contract(),
        "project_id" => project.id,
        "project_path" => project.local_path,
        "tooling" => "none"
      }
    )
  end

  defp command_lines(commands) do
    commands
    |> Enum.map(&command_line/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp command_line(%{"argv" => argv}) when is_list(argv), do: Enum.join(argv, " ")
  defp command_line(%{argv: argv}) when is_list(argv), do: Enum.join(argv, " ")
  defp command_line(_command), do: ""
end
