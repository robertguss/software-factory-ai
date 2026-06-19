defmodule Mix.Tasks.Conveyor.QualificationBundle do
  @moduledoc """
  Builds an offline-verifiable qualification bundle.

      mix conveyor.qualification_bundle --input artifacts.json --format json
  """

  use Mix.Task

  alias Conveyor.CLI.ExitCodes
  alias Conveyor.Qualification.Bundle

  @shortdoc "Build a qualification bundle"

  @impl Mix.Task
  def run(args) do
    {opts, rest, invalid} = OptionParser.parse(args, strict: [input: :string, format: :string])

    with [] <- invalid,
         [] <- rest,
         {:ok, input_path} <- Keyword.fetch(opts, :input),
         {:ok, format} <- parse_format(Keyword.get(opts, :format, "human")),
         {:ok, payload} <- load_payload(input_path) do
      bundle = Bundle.build(payload)
      Mix.shell().info(render(bundle, format))
      exit_fun().(ExitCodes.fetch!(:success))
    else
      {:error, error} ->
        Mix.shell().error(error)
        exit_fun().(ExitCodes.fetch!(:malformed_artifact_or_schema_failure))

      _ ->
        Mix.raise(
          "usage: mix conveyor.qualification_bundle --input artifacts.json [--format human|json]"
        )
    end
  end

  defp parse_format(format) when format in ["human", "json"], do: {:ok, String.to_atom(format)}
  defp parse_format(_format), do: {:error, "--format must be human or json"}

  defp render(bundle, :json), do: Jason.encode!(bundle)

  defp render(bundle, :human) do
    [
      "qualification_bundle: built",
      "Grant: #{bundle["grant_id"]}",
      "Offline verifiable: #{bundle["offline_verifiable?"]}"
    ]
    |> Enum.join("\n")
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

  defp exit_fun do
    Process.get(:conveyor_qualification_bundle_exit_fun, &System.halt/1)
  end
end
