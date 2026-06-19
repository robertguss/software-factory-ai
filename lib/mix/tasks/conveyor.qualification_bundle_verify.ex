defmodule Mix.Tasks.Conveyor.QualificationBundleVerify do
  @moduledoc """
  Verifies a qualification bundle without the live database.

      mix conveyor.qualification_bundle_verify --offline bundle.json --format json
  """

  use Mix.Task

  alias Conveyor.CLI.ExitCodes
  alias Conveyor.Qualification.Bundle

  @shortdoc "Verify a qualification bundle offline"

  @impl Mix.Task
  def run(args) do
    {opts, rest, invalid} = OptionParser.parse(args, strict: [offline: :boolean, format: :string])

    with [] <- invalid,
         true <- Keyword.get(opts, :offline, false),
         [bundle_path] <- rest,
         {:ok, format} <- parse_format(Keyword.get(opts, :format, "human")),
         {:ok, bundle} <- load_payload(bundle_path) do
      case Bundle.verify_offline(bundle) do
        {:ok, verification} ->
          Mix.shell().info(render(verification, format))
          exit_fun().(ExitCodes.fetch!(:success))

        {:error, error} ->
          Mix.shell().info(render(error_result(error), format))
          exit_fun().(ExitCodes.fetch!(:plan_or_readiness_blocked))
      end
    else
      {:error, error} ->
        Mix.shell().error(error)
        exit_fun().(ExitCodes.fetch!(:malformed_artifact_or_schema_failure))

      _ ->
        Mix.raise(
          "usage: mix conveyor.qualification_bundle_verify --offline bundle.json [--format human|json]"
        )
    end
  end

  defp parse_format(format) when format in ["human", "json"], do: {:ok, String.to_atom(format)}
  defp parse_format(_format), do: {:error, "--format must be human or json"}

  defp render(result, :json), do: Jason.encode!(stringify_map(result))

  defp render(result, :human) do
    result = stringify_map(result)

    [
      "qualification_bundle_verify: #{result["status"]}",
      "Grant: #{result["grant_id"] || "unknown"}",
      "Reason: #{result["reason"] || "none"}"
    ]
    |> Enum.join("\n")
  end

  defp error_result(error) do
    %{
      "schema_version" => "conveyor.qualification_bundle_verification@1",
      "status" => "blocked",
      "reason" => Map.get(error, :reason, Map.get(error, "reason"))
    }
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

  defp stringify_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), stringify_value(value)} end)
  end

  defp stringify_value(value) when is_map(value), do: stringify_map(value)
  defp stringify_value(values) when is_list(values), do: Enum.map(values, &stringify_value/1)
  defp stringify_value(value) when is_boolean(value), do: value
  defp stringify_value(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify_value(value), do: value

  defp exit_fun do
    Process.get(:conveyor_qualification_bundle_verify_exit_fun, &System.halt/1)
  end
end
