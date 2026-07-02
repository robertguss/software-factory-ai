defmodule Mix.Tasks.Conveyor.Digest do
  @moduledoc """
  Headless Morning Digest (a3hf.1.1.3) — the cron/email/Slack sibling of the cockpit digest
  route. Folds the run ledger into a `Conveyor.Digest.Summary` and renders it.

      mix conveyor.digest [--since ISO8601] [--format md|html|json]

  `--since` (optional) filters to runs started at/after an ISO8601 timestamp; without it, every
  recorded run is included. `--format` defaults to `md`. Output is deterministic (runs sorted
  by id) so the Markdown is golden-file-stable.
  """

  use Mix.Task

  alias Conveyor.CLI.ExitCodes
  alias Conveyor.Digest.Render
  alias Conveyor.Digest.Summary
  alias Conveyor.Factory
  alias Conveyor.Factory.LedgerEvent
  alias Conveyor.RunReadModel

  @shortdoc "Render the Morning Digest from the run ledger"

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _rest, _invalid} = OptionParser.parse(argv, strict: [since: :string, format: :string])

    digest =
      opts[:since]
      |> since_run_ids()
      |> Enum.map(&RunReadModel.summarize/1)
      |> Summary.build()

    digest |> render(opts[:format] || "md") |> IO.puts()
    exit_fun().(ExitCodes.fetch!(:success))
  end

  defp since_run_ids(since) do
    cutoff = parse_since(since)

    LedgerEvent
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.type == "run.started" and at_or_after?(&1.occurred_at, cutoff)))
    |> Enum.map(& &1.payload["run_id"])
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp parse_since(nil), do: nil

  defp parse_since(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, datetime, _offset} -> datetime
      _ -> Mix.raise("--since must be an ISO8601 timestamp, got: #{iso}")
    end
  end

  defp at_or_after?(_occurred_at, nil), do: true
  defp at_or_after?(occurred_at, cutoff), do: DateTime.compare(occurred_at, cutoff) != :lt

  defp render(digest, "json"), do: Render.to_json(digest)
  defp render(digest, "html"), do: Render.to_html(digest)
  defp render(digest, _markdown), do: Render.to_markdown(digest)

  defp exit_fun, do: Process.get(:conveyor_digest_exit_fun, &System.halt/1)
end
