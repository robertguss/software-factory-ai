defmodule Mix.Tasks.Conveyor.Triage do
  @moduledoc """
  The operator's terminal triage surface: the needs-a-human queue and its dispositions.

      mix conveyor.triage                                # list, least-trusted first (uevc.1)
      mix conveyor.triage approve SLICE --actor A [--note N]   # human-override -> integrated (uevc.2)
      mix conveyor.triage rework  SLICE --actor A [--note N]   # re-run with the note -> needs_rework
      mix conveyor.triage reject  SLICE --actor A [--note N]   # terminal park, recorded rejected

  The no-arg list emits `conveyor.triage_queue@1`; a disposition emits `conveyor.triage_disposition@1`.
  Machine JSON goes to **stdout**; the human table/errors to **stderr**, so JSON pipes cleanly. An
  empty queue exits 0. Each disposition is an exactly-once, event-sourced closer (Triage.Disposition).
  """

  use Mix.Task

  alias Conveyor.CLI.ExitCodes
  alias Conveyor.ParkedQueue
  alias Conveyor.Triage.Disposition

  @shortdoc "Triage the needs-a-human queue: list, or approve|rework|reject a parked slice"

  @dispositions %{"approve" => :approve, "rework" => :rework, "reject" => :reject}

  @impl Mix.Task
  def run([subcommand, slice_id | rest]) when is_map_key(@dispositions, subcommand) do
    Mix.Task.run("app.start")
    dispose(Map.fetch!(@dispositions, subcommand), slice_id, parse_opts!(rest))
  end

  def run([subcommand | _]) when is_map_key(@dispositions, subcommand) do
    Mix.raise(usage())
  end

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

  defp dispose(type, slice_id, opts) do
    case apply(Disposition, type, [slice_id, opts]) do
      {:ok, result} ->
        result |> disposition_json(type, slice_id) |> Jason.encode!() |> Mix.shell().info()
        exit_fun().(ExitCodes.fetch!(:success))

      {:error, {:patch_conflict, reason}} ->
        IO.puts(
          :stderr,
          "approve failed: patch does not apply cleanly (#{inspect(reason)}). Try: mix conveyor.triage rework #{slice_id}"
        )

        exit_fun().(ExitCodes.fetch!(:usage))

      {:error, reason} ->
        IO.puts(:stderr, "disposition failed: #{inspect(reason)}")
        exit_fun().(ExitCodes.fetch!(:usage))
    end
  end

  defp disposition_json(result, type, slice_id) do
    %{
      "schema_version" => "conveyor.triage_disposition@1",
      "slice_id" => slice_id,
      "disposition" => Atom.to_string(type),
      "status" => Atom.to_string(Map.get(result, :status, :applied)),
      "terminal_state" => result |> Map.get(:terminal_state) |> atom_or_nil(),
      "ledger_event_id" => result |> Map.get(:ledger_event) |> id_or_nil(),
      "human_approval_id" => result |> Map.get(:human_approval) |> id_or_nil()
    }
  end

  defp atom_or_nil(nil), do: nil
  defp atom_or_nil(atom), do: Atom.to_string(atom)
  defp id_or_nil(nil), do: nil
  defp id_or_nil(%{id: id}), do: id

  defp parse_opts!(args) do
    {opts, rest, invalid} = OptionParser.parse(args, strict: [actor: :string, note: :string])
    if rest != [] or invalid != [], do: Mix.raise(usage())
    if opts[:actor] in [nil, ""], do: Mix.raise(usage())
    opts
  end

  defp usage do
    """
    usage:
      mix conveyor.triage                                   # list the needs-a-human queue
      mix conveyor.triage approve SLICE_ID --actor A [--note N]
      mix conveyor.triage rework  SLICE_ID --actor A [--note N]
      mix conveyor.triage reject  SLICE_ID --actor A [--note N]
    """
    |> String.trim()
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
