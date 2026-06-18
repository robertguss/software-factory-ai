defmodule Conveyor.Gate.Stages.BuildInstall do
  @moduledoc """
  Gate stage 6: verifies the target environment can build/install/import the app.
  """

  @behaviour Conveyor.Gate.Stage

  alias Conveyor.Gate.StageResult

  @impl true
  def run(context, _opts \\ []) do
    result = build_result(context)
    findings = findings(result)

    %StageResult{
      key: "build_install",
      status: status(findings),
      required?: true,
      findings: findings,
      evidence_refs: evidence_refs(result),
      input_digests: %{
        "build_result_sha256" => digest(result)
      }
    }
  end

  defp build_result(context) do
    cond do
      result = value(context, :build_install_result) ->
        normalize_result(result)

      commands = value(context, :build_install_commands) ->
        run_commands(commands, value(context, :build_install_runner) || value(context, :runner))

      true ->
        %{"status" => "missing", "commands" => []}
    end
  end

  defp run_commands(commands, runner) when is_list(commands) and is_function(runner, 1) do
    command_results =
      Enum.map(commands, fn command ->
        result = runner.(command)

        %{
          "key" => value(command, :key) || command_text(command),
          "argv" => value(command, :argv),
          "exit_code" => result_value(result, :exit_code),
          "stdout" => result_value(result, :stdout, ""),
          "stderr" => result_value(result, :stderr, "")
        }
      end)

    %{
      "status" =>
        if(Enum.all?(command_results, &(&1["exit_code"] == 0)), do: "passed", else: "failed"),
      "commands" => command_results
    }
  end

  defp run_commands(_commands, _runner), do: %{"status" => "missing_runner", "commands" => []}

  defp normalize_result(%{status: _status} = result), do: stringify_keys(result)
  defp normalize_result(%{"status" => _status} = result), do: result

  defp normalize_result(result) do
    %{"status" => stringify(value(result, :status) || "missing"), "commands" => []}
  end

  defp findings(%{"status" => status} = result)
       when status in ["passed", "passed_with_warning"] do
    command_findings(result)
  end

  defp findings(%{"status" => "missing"}) do
    [
      finding(
        "missing_build_install_evidence",
        "Build/install evidence is required before tests run."
      )
    ]
  end

  defp findings(%{"status" => "missing_runner"}) do
    [
      finding(
        "missing_build_install_runner",
        "Build/install commands were provided without a runner."
      )
    ]
  end

  defp findings(result) do
    [
      finding(
        "build_install_failed",
        "Build/install/import command evidence did not pass."
      )
      | command_findings(result)
    ]
  end

  defp command_findings(result) do
    result
    |> value(:commands)
    |> List.wrap()
    |> Enum.filter(&(value(&1, :exit_code) not in [0, nil]))
    |> Enum.map(fn command ->
      finding(
        "build_install_command_failed",
        "Build/install/import command exited non-zero.",
        command
      )
    end)
  end

  defp finding(category, message, command \\ nil) do
    %{
      "category" => category,
      "severity" => "blocking",
      "message" => message,
      "command" => command_text(command),
      "exit_code" => value(command, :exit_code)
    }
  end

  defp status([]), do: :passed
  defp status(_findings), do: :failed

  defp evidence_refs(result) do
    result
    |> value(:artifact_refs)
    |> List.wrap()
    |> Kernel.++(List.wrap(value(result, :log_ref)))
    |> Enum.reject(&is_nil/1)
  end

  defp command_text(nil), do: nil
  defp command_text(%{"argv" => argv}) when is_list(argv), do: Enum.join(argv, " ")
  defp command_text(%{argv: argv}) when is_list(argv), do: Enum.join(argv, " ")
  defp command_text(command), do: value(command, :key)

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), stringify_nested(value)} end)
  end

  defp stringify_nested(value) when is_map(value), do: stringify_keys(value)
  defp stringify_nested(value) when is_list(value), do: Enum.map(value, &stringify_nested/1)
  defp stringify_nested(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify_nested(value), do: value

  defp digest(value) do
    "sha256:" <>
      (:sha256
       |> :crypto.hash(:erlang.term_to_binary(value))
       |> Base.encode16(case: :lower))
  end

  defp result_value(result, key, default \\ nil) when is_map(result) do
    Map.get(result, key, Map.get(result, Atom.to_string(key), default))
  end

  defp stringify(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify(value), do: to_string(value)

  defp value(nil, _key), do: nil

  defp value(map, key) when is_map(map),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
