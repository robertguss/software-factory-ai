defmodule Conveyor.Planning.PlanLintCLI do
  @moduledoc false

  alias Conveyor.CLI.ExitCodes

  @spec parse_format(String.t() | nil) :: {:ok, :human | :json | :sarif} | {:error, String.t()}
  def parse_format(nil), do: {:ok, :human}
  def parse_format("human"), do: {:ok, :human}
  def parse_format("json"), do: {:ok, :json}
  def parse_format("sarif"), do: {:ok, :sarif}
  def parse_format(_other), do: {:error, "--format must be human, json, or sarif"}

  @spec load_contract(Path.t()) :: {:ok, map()} | {:error, String.t()}
  def load_contract(path) do
    path = Path.expand(path)

    with {:ok, content} <- File.read(path),
         {:ok, body, format} <- contract_body(path, content),
         {:ok, contract} <- decode(body, format) do
      {:ok, contract}
    else
      {:error, reason} when is_atom(reason) -> {:error, "could not read #{path}: #{reason}"}
      {:error, reason} -> {:error, reason}
      :error -> {:error, "missing JSON/YAML conveyor-plan@1 block in #{path}"}
    end
  end

  @spec print_result(map() | String.t(), atom()) :: :ok
  def print_result(rendered, :human) when is_binary(rendered) do
    Mix.shell().info(rendered)
  end

  def print_result(rendered, _format) when is_map(rendered) do
    rendered
    |> Jason.encode!()
    |> Mix.shell().info()
  end

  @spec exit_code(map()) :: non_neg_integer()
  def exit_code(%{status: :passed}), do: ExitCodes.fetch!(:success)
  def exit_code(%{status: "passed"}), do: ExitCodes.fetch!(:success)
  def exit_code(_result), do: ExitCodes.fetch!(:plan_or_readiness_blocked)

  @spec malformed_exit_code() :: non_neg_integer()
  def malformed_exit_code, do: ExitCodes.fetch!(:malformed_artifact_or_schema_failure)

  defp contract_body(path, content) do
    case Path.extname(path) do
      ".json" -> {:ok, content, :json}
      ".yaml" -> {:ok, content, :yaml}
      ".yml" -> {:ok, content, :yaml}
      _other -> fenced_contract(content)
    end
  end

  defp fenced_contract(markdown) do
    fence = ~r/^```(?<info>[^\n`]*)\n(?<body>.*?)(?:\n|\r\n)```/ms

    fence
    |> Regex.scan(markdown, capture: :all_names)
    |> Enum.find_value(:error, &fenced_contract_match/1)
  end

  defp fenced_contract_match([body, info]) do
    if info =~ "conveyor-plan@1" do
      {:ok, body, if(info =~ "json", do: :json, else: :yaml)}
    end
  end

  defp decode(content, :json) do
    case Jason.decode(content) do
      {:ok, contract} when is_map(contract) -> {:ok, contract}
      {:ok, _other} -> {:error, "plan lint input must decode to an object"}
      {:error, error} -> {:error, Exception.message(error)}
    end
  end

  defp decode(content, :yaml) do
    case YamlElixir.read_from_string(content) do
      {:ok, contract} when is_map(contract) -> {:ok, contract}
      {:ok, _other} -> {:error, "plan lint input must decode to an object"}
      {:error, error} -> {:error, Exception.message(error)}
    end
  end
end
