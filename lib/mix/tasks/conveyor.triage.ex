defmodule Mix.Tasks.Conveyor.Triage do
  @moduledoc """
  The operator's terminal triage surface (uevc.1): the needs-a-human queue, least-trusted first.

      mix conveyor.triage

  Lists every parked/abstained slice with its typed park reason (the a3hf.1.3.1 taxonomy), the
  calibrated trust verdict, and the exact disposition commands to inspect or resolve it. Machine
  JSON (`conveyor.triage_queue@1`) goes to **stdout**; a human-readable table goes to **stderr**, so
  the JSON pipes cleanly. An empty queue exits 0 with an empty payload.
  """

  use Mix.Task

  alias Conveyor.CLI.ExitCodes
  alias Conveyor.ParkedQueue

  @shortdoc "Triage the needs-a-human queue: parked slices least-trusted-first with disposition"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    entries = ParkedQueue.abstained()
    rows = Enum.map(entries, &row/1)

    IO.puts(:stderr, human_table(rows))

    %{"schema_version" => "conveyor.triage_queue@1", "count" => length(rows), "parked" => rows}
    |> Jason.encode!()
    |> Mix.shell().info()

    exit_fun().(ExitCodes.fetch!(:success))
  end

  defp row(entry) do
    %{
      "slice_id" => entry.slice_id,
      "slice_title" => entry.slice_title,
      "run_attempt_id" => entry.run_attempt_id,
      "attempt_no" => entry.attempt_no,
      "park_reason" => entry.park_reason || "unclassified",
      "trust" => %{
        "band" => entry.band,
        "score" => entry.score,
        "components" => components(entry)
      },
      "diff_stat" => entry.diff_stat,
      "disposition_commands" => disposition_commands(entry)
    }
  end

  defp components(%{trust_score: trust}) when is_map(trust), do: Map.get(trust, "components")
  defp components(_entry), do: nil

  # Exact, copy-pasteable next actions: inspect the evidence, then accept-as-integrated or
  # mark-not-integrated once the human has judged the parked work.
  defp disposition_commands(entry) do
    [
      "mix conveyor.show #{entry.slice_id}",
      "mix conveyor.mark_externally_merged #{entry.run_attempt_id} --external-commit <SHA> --actor <you>",
      "mix conveyor.mark_externally_merged #{entry.run_attempt_id} --not-integrated --actor <you>"
    ]
  end

  defp human_table([]), do: "needs-a-human queue: empty — nothing parked."

  defp human_table(rows) do
    header = "needs-a-human queue (#{length(rows)}), least-trusted first:"

    lines =
      Enum.map(rows, fn row ->
        "  [#{format_score(row["trust"]["score"])}] #{row["park_reason"]}  " <>
          "#{row["slice_title"] || row["slice_id"]}  (slice #{row["slice_id"]})"
      end)

    Enum.join([header | lines], "\n")
  end

  defp format_score(nil), do: "  -  "

  defp format_score(score) when is_number(score),
    do: :erlang.float_to_binary(score * 1.0, decimals: 2)

  defp exit_fun do
    Process.get(:conveyor_triage_exit_fun, &System.halt/1)
  end
end
