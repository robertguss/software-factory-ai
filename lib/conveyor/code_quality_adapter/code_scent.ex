defmodule Conveyor.CodeQualityAdapter.CodeScent do
  @moduledoc """
  Optional CodeScent adapter for before/after quality baselines.

  CodeScent is intentionally not required by the default demo path. When this
  adapter is explicitly selected, missing tooling produces a structured blocked
  result instead of raising.
  """

  @behaviour Conveyor.CodeQualityAdapter

  alias Conveyor.CodeQualityAdapter
  alias Conveyor.CodeQualityAdapter.Result

  @adapter_name "CodeQualityAdapter.CodeScent"
  @baseline_ref "codescent/before.json"
  @default_executable "codescent"
  @default_scan_args ["ci", "--format", "json"]
  @version_args ["--version"]

  @impl true
  def adapter_name, do: @adapter_name

  @impl true
  def adapter_contract do
    %{
      "deterministic_output" => true,
      "version_command" => [@default_executable | @version_args],
      "scan_command" => [@default_executable | @default_scan_args],
      "result_schema" => Result.schema_version(),
      "fixture_suite" => "codescent_adapter_conformance",
      "threshold_policy" => %{"new_high_risk_findings" => 0},
      "baseline_artifact" => @baseline_ref,
      "gate_blocking_when_selected" => true,
      "advisory_only" => false
    }
  end

  @impl true
  def scan(project, opts \\ []) do
    executable = Keyword.get(opts, :executable, @default_executable)

    case find_executable(executable, opts) do
      nil ->
        missing_tool_result(project, executable, opts)

      _path ->
        scan_with_tool(project, executable, opts)
    end
  end

  @spec baseline_ref() :: String.t()
  def baseline_ref, do: @baseline_ref

  @spec baseline!(struct() | Ecto.UUID.t(), keyword()) :: struct()
  def baseline!(project_or_id, opts \\ []) do
    CodeQualityAdapter.run!(
      project_or_id,
      __MODULE__,
      Keyword.put_new(opts, :baseline_ref, @baseline_ref)
    )
  end

  defp scan_with_tool(project, executable, opts) do
    runner = Keyword.get(opts, :runner, &System.cmd/3)
    scan_args = Keyword.get(opts, :scan_args, @default_scan_args)
    version = run_command(runner, executable, @version_args, project.local_path)
    scan = run_command(runner, executable, scan_args, project.local_path)
    payload = decode_payload(scan.output)
    findings = normalized_findings(payload)

    Result.new!(
      adapter: @adapter_name,
      profile: Keyword.get(opts, :profile, project.code_quality_profile),
      status: status_for(scan.exit_status),
      findings: findings,
      findings_summary: findings_summary(payload, findings),
      new_high_risk_findings: new_high_risk_findings(payload, findings),
      risks: risks(payload, scan.exit_status),
      suggested_validation: suggested_validation(payload, project.command_specs),
      metadata: %{
        "adapter_contract" => adapter_contract(),
        "baseline_artifact" => @baseline_ref,
        "project_id" => project.id,
        "project_path" => project.local_path,
        "version" => String.trim(version.output),
        "version_exit_status" => version.exit_status,
        "scan_command" => [executable | scan_args],
        "scan_exit_status" => scan.exit_status,
        "decoded_output" => payload
      }
    )
  rescue
    error ->
      failed_result(project, opts, executable, Exception.message(error))
  end

  defp missing_tool_result(project, executable, opts) do
    Result.new!(
      adapter: @adapter_name,
      profile: Keyword.get(opts, :profile, project.code_quality_profile),
      status: :blocked,
      findings_summary: Result.empty_summary(),
      new_high_risk_findings: 0,
      risks: [
        "CodeScent executable #{inspect(executable)} was not found; install CodeScent or select the Noop/LocalPython adapter."
      ],
      suggested_validation: command_lines(project.command_specs),
      metadata: %{
        "adapter_contract" => adapter_contract(),
        "baseline_artifact" => @baseline_ref,
        "project_id" => project.id,
        "project_path" => project.local_path,
        "tooling" => "missing",
        "executable" => executable
      }
    )
  end

  defp failed_result(project, opts, executable, reason) do
    Result.new!(
      adapter: @adapter_name,
      profile: Keyword.get(opts, :profile, project.code_quality_profile),
      status: :failed,
      findings_summary: Result.empty_summary(),
      new_high_risk_findings: 0,
      risks: ["CodeScent adapter failed before producing a valid result: #{reason}"],
      suggested_validation: command_lines(project.command_specs),
      metadata: %{
        "adapter_contract" => adapter_contract(),
        "baseline_artifact" => @baseline_ref,
        "project_id" => project.id,
        "project_path" => project.local_path,
        "tooling" => "failed",
        "executable" => executable,
        "error" => reason
      }
    )
  end

  defp find_executable(executable, opts) do
    find_fun = Keyword.get(opts, :find_executable, &System.find_executable/1)
    find_fun.(executable)
  end

  defp run_command(runner, executable, args, project_root) do
    {output, exit_status} = runner.(executable, args, cd: project_root, stderr_to_stdout: true)
    %{output: output, exit_status: exit_status}
  end

  defp decode_payload(output) do
    case Jason.decode(output) do
      {:ok, %{} = payload} -> payload
      {:ok, value} -> %{"value" => value}
      {:error, _reason} -> %{"raw_output" => output}
    end
  end

  defp normalized_findings(%{"findings" => findings}) when is_list(findings) do
    Enum.filter(findings, &is_map/1)
  end

  defp normalized_findings(_payload), do: []

  defp findings_summary(payload, findings) do
    payload["findings_summary"] || payload["summary"] || Result.summary_from_findings(findings)
  end

  defp new_high_risk_findings(%{"new_high_risk_findings" => count}, _findings)
       when is_integer(count) and count >= 0 do
    count
  end

  defp new_high_risk_findings(_payload, findings) do
    Enum.count(findings, fn finding ->
      (finding["severity"] || finding[:severity]) in ["critical", "high", :critical, :high]
    end)
  end

  defp risks(%{"risks" => risks}, _exit_status) when is_list(risks) do
    Enum.filter(risks, &is_binary/1)
  end

  defp risks(_payload, 0) do
    ["CodeScent findings are quality signals; tests and RunCheck remain required proof."]
  end

  defp risks(_payload, exit_status) do
    ["CodeScent exited with status #{exit_status}; treat the quality stage as failed."]
  end

  defp suggested_validation(%{"suggested_validation" => commands}, project_commands)
       when is_list(commands) do
    commands
    |> Enum.filter(&is_binary/1)
    |> Kernel.++(command_lines(project_commands))
    |> Enum.uniq()
  end

  defp suggested_validation(_payload, project_commands), do: command_lines(project_commands)

  defp status_for(0), do: :succeeded
  defp status_for(_exit_status), do: :failed

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
