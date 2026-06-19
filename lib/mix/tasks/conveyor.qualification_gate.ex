defmodule Mix.Tasks.Conveyor.QualificationGate do
  @moduledoc """
  Runs the public P15-B qualification gate for a project and requested scope.

      mix conveyor.qualification_gate PROJECT_ID --scope adapter=primary,archetype=planning --input package.json
  """

  use Mix.Task

  alias Conveyor.CLI.ExitCodes
  alias Conveyor.Qualification.Gate
  alias Conveyor.Qualification.Grants

  @shortdoc "Run the scoped Conveyor qualification gate"

  @impl Mix.Task
  def run(args) do
    {opts, rest, invalid} =
      OptionParser.parse(args, strict: [scope: :string, input: :string, format: :string])

    with [] <- invalid,
         [project_id] <- rest,
         {:ok, scope} <- fetch_scope(opts),
         {:ok, input_path} <- Keyword.fetch(opts, :input),
         {:ok, package} <- load_payload(input_path),
         {:ok, format} <- parse_format(Keyword.get(opts, :format, "human")) do
      result =
        package
        |> Map.put("project_id", project_id)
        |> Map.put("requested_scope", scope)
        |> Gate.evaluate()
        |> maybe_issue_grant(package)
        |> serializable_result()

      Mix.shell().info(render(result, format))
      exit_fun().(exit_code(result))
    else
      {:error, error} ->
        Mix.shell().error(error)
        exit_fun().(ExitCodes.fetch!(:malformed_artifact_or_schema_failure))

      _ ->
        Mix.raise(
          "usage: mix conveyor.qualification_gate PROJECT_ID --scope k=v[,k=v] --input package.json [--format human|json]"
        )
    end
  end

  defp fetch_scope(opts) do
    opts
    |> Keyword.fetch(:scope)
    |> case do
      {:ok, raw_scope} -> parse_scope(raw_scope)
      :error -> {:error, "--scope is required"}
    end
  end

  defp parse_scope(raw_scope) do
    scope =
      raw_scope
      |> String.split(",", trim: true)
      |> Enum.reduce_while(%{}, fn part, acc ->
        case String.split(part, "=", parts: 2) do
          [key, value] when key != "" and value != "" ->
            {:cont, Map.put(acc, key, value)}

          _ ->
            {:halt, :invalid}
        end
      end)

    case scope do
      :invalid -> {:error, "--scope must use k=v[,k=v] syntax"}
      scope when map_size(scope) == 0 -> {:error, "--scope must include at least one key"}
      scope -> {:ok, scope}
    end
  end

  defp parse_format(format) when format in ["human", "json"], do: {:ok, String.to_atom(format)}
  defp parse_format(_format), do: {:error, "--format must be human or json"}

  defp load_payload(path) do
    with {:ok, body} <- File.read(path),
         {:ok, payload} <- Jason.decode(body) do
      {:ok, payload}
    else
      {:error, %Jason.DecodeError{} = error} -> {:error, Exception.message(error)}
      {:error, reason} -> {:error, "could not read #{path}: #{inspect(reason)}"}
    end
  end

  defp maybe_issue_grant(%{status: :passed} = result, package) do
    if has_grant_inputs?(package) do
      grant_input =
        package
        |> Map.put("project_id", result.project_id)
        |> Map.put("requested_scope", result.requested_scope)
        |> Map.put("gate_result", result)

      case Grants.issue(grant_input) do
        {:ok, grant_artifacts} ->
          Map.put(result, :grant_artifacts, grant_artifacts)

        {:deny, denial} ->
          finding = %{
            rule_key: "qualification_gate_grant_denied",
            severity: :blocking,
            subject_key: "qualification_grant",
            message: "requested scope is not covered by supported evidence"
          }

          result
          |> Map.put(:status, :blocked)
          |> Map.put(:authority_effect, :none)
          |> Map.put(:grant_denial, denial)
          |> Map.update!(:findings, &(&1 ++ [finding]))
          |> Map.update!(:finding_keys, &Enum.uniq(&1 ++ [finding.rule_key]))
      end
    else
      result
    end
  end

  defp maybe_issue_grant(result, _package), do: result

  defp has_grant_inputs?(package) do
    Map.has_key?(package, "supported_scope") or Map.has_key?(package, "scope_lattice") or
      Map.has_key?(package, :supported_scope) or Map.has_key?(package, :scope_lattice)
  end

  defp serializable_result(result) do
    base = %{
      "schema_version" => "conveyor.qualification_gate_result@1",
      "project_id" => result.project_id,
      "requested_scope" => stringify_map(result.requested_scope),
      "status" => Atom.to_string(result.status),
      "authority_effect" => Atom.to_string(result.authority_effect),
      "findings" => Enum.map(result.findings, &stringify_map/1),
      "finding_keys" => result.finding_keys,
      "live_sample_policy" => stringify_map(result.live_sample_policy)
    }

    base
    |> put_optional("grant_artifacts", Map.get(result, :grant_artifacts))
    |> put_optional("grant_denial", Map.get(result, :grant_denial))
  end

  defp render(result, :json), do: Jason.encode!(result)

  defp render(result, :human) do
    [
      "qualification_gate: #{result["status"]}",
      "Authority: #{result["authority_effect"]}",
      findings(result["findings"])
    ]
    |> Enum.join("\n")
  end

  defp findings([]), do: "Findings: none"

  defp findings(findings) do
    body =
      findings
      |> Enum.map(&"- #{&1["rule_key"]}: #{&1["subject_key"]} #{Map.get(&1, "message", "")}")
      |> Enum.join("\n")

    "Findings:\n" <> body
  end

  defp exit_code(%{"status" => "passed"}), do: ExitCodes.fetch!(:success)
  defp exit_code(%{"status" => "blocked"}), do: ExitCodes.fetch!(:plan_or_readiness_blocked)

  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, stringify_value(value))

  defp stringify_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), stringify_value(value)} end)
  end

  defp stringify_value(value) when is_map(value), do: stringify_map(value)
  defp stringify_value(values) when is_list(values), do: Enum.map(values, &stringify_value/1)
  defp stringify_value(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify_value(value), do: value

  defp exit_fun do
    Process.get(:conveyor_qualification_gate_exit_fun, &System.halt/1)
  end
end
