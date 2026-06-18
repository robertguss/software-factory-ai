defmodule Conveyor.CodeQualityAdapter.LocalPython do
  @moduledoc """
  Read-only Python project quality signal adapter.
  """

  @behaviour Conveyor.CodeQualityAdapter

  alias Conveyor.CodeQualityAdapter.Result

  @adapter_name "CodeQualityAdapter.LocalPython"
  @excluded_dirs MapSet.new([".git", ".pytest_cache", ".venv", "__pycache__"])

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
    files = discover_files(project.local_path)
    python_files = Enum.filter(files, &python_source?/1)
    test_files = Enum.filter(files, &python_test?/1)
    findings = findings(project.local_path, python_files, test_files)

    Result.new!(
      adapter: @adapter_name,
      profile: Keyword.get(opts, :profile, project.code_quality_profile),
      status: :succeeded,
      findings: findings,
      findings_summary: Result.summary_from_findings(findings),
      new_high_risk_findings: 0,
      risks: risks(python_files, test_files),
      suggested_validation: command_lines(project.command_specs),
      metadata: %{
        "adapter_contract" => adapter_contract(),
        "project_id" => project.id,
        "project_path" => project.local_path,
        "python_files" => python_files,
        "test_files" => test_files,
        "config_files" => Enum.filter(files, &config_file?/1)
      }
    )
  end

  defp discover_files(project_root) do
    root = Path.expand(project_root)

    root
    |> walk_files()
    |> Enum.map(&Path.relative_to(&1, root))
    |> Enum.sort()
  end

  defp walk_files(path) do
    case File.ls(path) do
      {:ok, entries} ->
        entries
        |> Enum.reject(&MapSet.member?(@excluded_dirs, &1))
        |> Enum.flat_map(&walk_entry(path, &1))

      {:error, _reason} ->
        []
    end
  end

  defp walk_entry(parent_path, entry) do
    child = Path.join(parent_path, entry)

    cond do
      File.dir?(child) -> walk_files(child)
      File.regular?(child) -> [child]
      true -> []
    end
  end

  defp findings(project_root, python_files, test_files) do
    []
    |> Kernel.++(missing_tests_finding(test_files))
    |> Kernel.++(todo_findings(project_root, python_files))
  end

  defp missing_tests_finding([]) do
    [
      %{
        "severity" => "medium",
        "category" => "test_coverage",
        "message" => "No Python test files were discovered.",
        "path" => nil
      }
    ]
  end

  defp missing_tests_finding(_test_files), do: []

  defp todo_findings(project_root, python_files) do
    python_files
    |> Enum.flat_map(fn path ->
      project_root
      |> Path.join(path)
      |> File.read()
      |> todo_findings_for_file(path)
    end)
  end

  defp todo_findings_for_file({:ok, content}, path) do
    content
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.filter(fn {line, _line_no} -> Regex.match?(~r/\b(TODO|FIXME)\b/i, line) end)
    |> Enum.map(fn {_line, line_no} ->
      %{
        "severity" => "low",
        "category" => "maintainability",
        "message" => "TODO/FIXME marker found.",
        "path" => path,
        "line" => line_no
      }
    end)
  end

  defp todo_findings_for_file({:error, _reason}, _path), do: []

  defp risks(_python_files, []) do
    ["No Python tests were discovered for the local project."]
  end

  defp risks([], _test_files),
    do: ["No Python source files were discovered for the local project."]

  defp risks(python_files, test_files) do
    [
      "LocalPython found #{length(python_files)} Python source file(s) and #{length(test_files)} test file(s); treat as advisory context, not proof."
    ]
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

  defp python_source?(path), do: String.ends_with?(path, ".py") and not python_test?(path)

  defp python_test?(path) do
    String.ends_with?(path, ".py") and
      (String.starts_with?(path, "tests/") or
         String.contains?(path, "/tests/") or
         String.starts_with?(Path.basename(path), "test_"))
  end

  defp config_file?(path) do
    Path.basename(path) in ["pyproject.toml", "requirements.txt", "requirements.lock"]
  end
end
