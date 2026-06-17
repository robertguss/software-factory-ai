defmodule Conveyor.PlanAuditReport do
  @moduledoc """
  Human-readable readiness report for normalized plan audits.
  """

  @score_labels [
    {"clarity", "Clarity"},
    {"acceptance_coverage", "Acceptance coverage"},
    {"testability", "Testability"},
    {"traceability", "Requirement traceability"},
    {"architecture", "Architecture decisions"},
    {"autonomy_readiness", "Autonomy readiness"}
  ]

  @spec format(Conveyor.PlanAuditor.Result.t()) :: String.t()
  def format(%Conveyor.PlanAuditor.Result{} = result) do
    [
      "Plan audit: #{decision_label(result.decision)}",
      score_lines(result.scores),
      "Decision: #{decision_label(result.decision)}",
      findings(result.findings)
    ]
    |> List.flatten()
    |> Enum.join("\n")
  end

  defp score_lines(scores) do
    Enum.map(@score_labels, fn {key, label} ->
      "#{label}: #{Map.fetch!(scores, key)}%"
    end)
  end

  defp findings([]), do: ["Findings: none"]

  defp findings(findings) do
    ["Blocking findings:" | Enum.flat_map(findings, &finding_lines/1)]
  end

  defp finding_lines(finding) do
    next_actions =
      finding
      |> Map.get("next_actions", [])
      |> Enum.map(fn action ->
        command = Map.get(action, "command")
        suffix = if command, do: " (#{command})", else: ""
        "  NextAction: #{Map.fetch!(action, "label")}#{suffix}"
      end)

    ["- #{Map.fetch!(finding, "message")}" | next_actions]
  end

  defp decision_label(:ready), do: "handoff_ready"
  defp decision_label(:needs_clarification), do: "needs_clarification"
  defp decision_label(:blocked), do: "blocked"
end
