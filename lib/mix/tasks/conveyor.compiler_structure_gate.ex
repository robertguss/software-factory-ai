defmodule Mix.Tasks.Conveyor.CompilerStructureGate do
  @moduledoc """
  Runs the internal, non-authorizing compiler structure gate.

      mix conveyor.compiler_structure_gate --input compiler-structure.json
  """

  use Mix.Task

  alias Conveyor.CLI.ExitCodes
  alias Conveyor.Planning.CompilerStructureGate

  @shortdoc "Run the non-authorizing compiler structure gate"

  @impl Mix.Task
  def run(args) do
    {opts, rest, invalid} = OptionParser.parse(args, strict: [input: :string])

    with [] <- invalid,
         [] <- rest,
         {:ok, path} <- Keyword.fetch(opts, :input),
         {:ok, payload} <- load_payload(path) do
      result =
        payload
        |> evaluate_payload()
        |> Map.update!(:exit_code, &stable_exit_code/1)

      Mix.shell().info(format(result))
      exit_fun().(result.exit_code)
    else
      {:error, error} ->
        Mix.shell().error(error)
        exit_fun().(ExitCodes.fetch!(:malformed_artifact_or_schema_failure))

      _ ->
        Mix.raise("usage: mix conveyor.compiler_structure_gate --input compiler-structure.json")
    end
  end

  defp load_payload(path) do
    with {:ok, body} <- File.read(path),
         {:ok, payload} <- Jason.decode(body) do
      {:ok, payload}
    else
      {:error, %Jason.DecodeError{} = error} -> {:error, Exception.message(error)}
      {:error, reason} -> {:error, "could not read #{path}: #{inspect(reason)}"}
    end
  end

  defp evaluate_payload(%{"package" => package, "findings" => findings})
       when is_map(package) and is_list(findings) do
    CompilerStructureGate.evaluate(package, findings)
  end

  defp evaluate_payload(_payload) do
    %{
      status: :blocked,
      exit_code: ExitCodes.fetch!(:malformed_artifact_or_schema_failure),
      authority_effect: :none,
      findings: [
        %{
          rule_key: "compiler_gate_malformed_input",
          severity: :blocking,
          subject_key: "input",
          message: "expected JSON object with package and findings"
        }
      ],
      finding_keys: ["compiler_gate_malformed_input"]
    }
  end

  defp stable_exit_code(0), do: ExitCodes.fetch!(:success)
  defp stable_exit_code(2), do: ExitCodes.fetch!(:plan_or_readiness_blocked)
  defp stable_exit_code(code), do: code

  defp format(result) do
    lines = [
      "compiler_structure_gate: #{result.status}",
      "Gate: internal",
      "Mode: NON-authorizing",
      "Authority: #{result.authority_effect}",
      findings(result.findings)
    ]

    Enum.join(lines, "\n")
  end

  defp findings([]), do: "Findings: none"

  defp findings(findings) do
    body =
      findings
      |> Enum.map(fn finding ->
        "- #{finding.rule_key}: #{finding.subject_key} #{Map.get(finding, :message, "")}"
      end)
      |> Enum.join("\n")

    "Findings:\n" <> body
  end

  defp exit_fun do
    Process.get(:conveyor_compiler_structure_gate_exit_fun, &System.halt/1)
  end
end
