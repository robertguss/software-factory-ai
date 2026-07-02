defmodule Conveyor.Digest.Render do
  @moduledoc """
  Renders a `Conveyor.Digest.Summary` into the operator-facing formats the headless
  `mix conveyor.digest` emits (a3hf.1.1.3): Markdown (email/Slack/file), JSON (the
  DigestSummary structure), and a standalone HTML document.

  Rendering is pure and deterministic — runs are sorted by `run_id` — so the Markdown is
  golden-file-stable and safe to diff across nightly digests.
  """

  @disposition_columns [:merged, :parked, :skipped, :failed]

  @spec to_markdown(map()) :: String.t()
  def to_markdown(digest) do
    totals = digest.totals

    [
      "# Morning Digest",
      "",
      "**Runs:** #{totals.runs} · **Slices:** #{totals.slice_count} · " <>
        "**Needs judgment:** #{totals.needs_judgment}",
      "",
      "## Runs",
      "",
      "| Run | Status | Merged | Parked | Skipped | Failed | Needs judgment |",
      "| --- | --- | --- | --- | --- | --- | --- |",
      Enum.map_join(sorted_runs(digest), "\n", &run_row/1),
      "",
      "## Cost",
      "",
      cost_line(digest.cost),
      remaining_line(digest.cost)
    ]
    |> Enum.join("\n")
  end

  @spec to_json(map()) :: String.t()
  def to_json(digest), do: Jason.encode!(digest)

  @spec to_html(map()) :: String.t()
  def to_html(digest) do
    """
    <!DOCTYPE html>
    <html><head><meta charset="utf-8"><title>Morning Digest</title></head>
    <body>
    <pre>
    #{digest |> to_markdown() |> html_escape()}
    </pre>
    </body></html>
    """
  end

  defp sorted_runs(digest), do: Enum.sort_by(digest.runs, & &1.run_id)

  defp run_row(run) do
    counts = Enum.map_join(@disposition_columns, " | ", &"#{run.dispositions[&1]}")
    "| #{run.run_id} | #{run.status} | #{counts} | #{run.needs_judgment} |"
  end

  defp cost_line(cost) do
    t = cost.totals

    "**Tokens:** #{t.tokens} · **Cost (est):** $#{:erlang.float_to_binary(t.cost_usd * 1.0, decimals: 2)}"
  end

  defp remaining_line(%{remaining: nil}), do: "Remaining: no budget envelope set."

  defp remaining_line(%{remaining: remaining}) do
    status = if remaining.over_budget?, do: "OVER BUDGET", else: "budget ok"
    "Remaining: #{remaining.tokens} tokens (#{status})"
  end

  defp html_escape(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end
end
