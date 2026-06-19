defmodule Conveyor.Gate.Stages.PolicyCompliance do
  @moduledoc """
  Gate stage 4: verifies command-policy records and protected policy files.
  """

  @behaviour Conveyor.Gate.Stage

  alias Conveyor.Gate.StageResult

  @default_policy_path_globs [
    "policies/**",
    ".conveyor/policies/**",
    "config/policies/**",
    "priv/conveyor/templates/policies/**",
    "lib/conveyor/policy/**",
    "lib/conveyor/factory/policy.ex"
  ]

  @impl true
  def run(context, _opts \\ []) do
    patch_set = value(context, :patch_set)
    policy_path_globs = value(context, :policy_path_globs) || @default_policy_path_globs
    tool_invocations = value(context, :tool_invocations) || []
    findings = findings(patch_set, policy_path_globs, tool_invocations)

    %StageResult{
      key: "policy_compliance",
      status: status(findings),
      required?: true,
      findings: findings,
      evidence_refs: evidence_refs(patch_set, tool_invocations),
      input_digests: %{
        "patch_sha256" => value(patch_set, :patch_sha256),
        "tool_invocation_count" => length(tool_invocations),
        "policy_path_globs_sha256" => digest(policy_path_globs)
      }
    }
  end

  defp findings(nil, _policy_path_globs, _tool_invocations) do
    [finding("missing_patch_set", "PatchSet is required for policy compliance.", [])]
  end

  defp findings(patch_set, policy_path_globs, tool_invocations) do
    policy_file_findings(patch_set, policy_path_globs) ++ invocation_findings(tool_invocations)
  end

  defp policy_file_findings(patch_set, policy_path_globs) do
    changed_files = value(patch_set, :changed_files) || []
    policy_files = Enum.filter(changed_files, &matches_any?(&1, policy_path_globs))

    if policy_files == [] do
      []
    else
      [
        finding(
          "policy_file_change",
          "Changed files include policy definitions or policy-engine code.",
          policy_files
        )
      ]
    end
  end

  defp invocation_findings(tool_invocations) do
    tool_invocations
    |> Enum.filter(&blocked_invocation?/1)
    |> Enum.map(fn invocation ->
      finding(
        "policy_invocation_blocked",
        "ToolInvocation records a blocked or denied policy decision.",
        [],
        invocation
      )
    end)
  end

  defp blocked_invocation?(invocation) do
    value(invocation, :policy_decision) in [:blocked, :denied, "blocked", "denied"] or
      value(invocation, :status) in [:blocked, "blocked"]
  end

  defp finding(category, message, paths, invocation \\ nil) do
    base = %{
      "category" => category,
      "severity" => "blocking",
      "message" => message,
      "paths" => paths
    }

    if invocation do
      Map.merge(base, %{
        "tool_invocation_id" => value(invocation, :id),
        "tool_name" => value(invocation, :tool_name),
        "command" => command_text(value(invocation, :command_spec)),
        "policy_decision" => stringify(value(invocation, :policy_decision)),
        "status" => stringify(value(invocation, :status))
      })
    else
      base
    end
  end

  defp command_text(%{"argv" => argv}) when is_list(argv), do: Enum.join(argv, " ")
  defp command_text(%{argv: argv}) when is_list(argv), do: Enum.join(argv, " ")
  defp command_text(_command_spec), do: nil

  defp status([]), do: :passed
  defp status(_findings), do: :failed

  defp evidence_refs(patch_set, tool_invocations) do
    patch_refs = Enum.reject([value(patch_set, :patch_ref)], &is_nil/1)

    invocation_refs =
      tool_invocations
      |> Enum.map(&value(&1, :id))
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&"tool-invocations/#{&1}")

    patch_refs ++ invocation_refs
  end

  defp matches_any?(_path, []), do: false
  defp matches_any?(path, globs), do: Enum.any?(globs, &glob_match?(path, &1))

  defp glob_match?(path, glob) do
    glob
    |> Regex.escape()
    |> String.replace("\\*\\*", ".*")
    |> String.replace("\\*", "[^/]*")
    |> then(&Regex.compile!("^#{&1}$"))
    |> Regex.match?(path)
  end

  defp digest(value), do: Conveyor.CanonicalJson.digest(value)

  defp stringify(nil), do: nil
  defp stringify(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify(value), do: to_string(value)

  defp value(nil, _key), do: nil

  defp value(map, key) when is_map(map),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
