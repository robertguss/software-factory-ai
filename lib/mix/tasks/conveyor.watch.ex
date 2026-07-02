defmodule Mix.Tasks.Conveyor.Watch do
  @moduledoc """
  Tail a run's ledger event stream — station starts/finishes, attempt transitions, gate verdicts,
  parks, and sentinel/scope decisions — for an in-flight or finished run.

      mix conveyor.watch RUN_ID [--json] [--follow]

  Renders from ledger events only (no new state), so a finished run replays deterministically. By
  default it prints the whole stream once and exits. `--follow` polls for new events until
  interrupted (the attended-dogfood "watch what breaks" tool). `--json` emits the machine-readable
  `conveyor.watch@1` envelope. Read-only: it never writes or repairs the ledger.
  """

  use Mix.Task

  alias Conveyor.CLI.ExitCodes
  alias Conveyor.RunEventStream

  @shortdoc "Tail a run's ledger event stream (live or replay)"

  @poll_interval_ms 1_000

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {run_id, opts} = parse_args!(args)
    events = RunEventStream.for_run(run_id)

    if opts.json do
      Mix.shell().info(json(run_id, events))
    else
      events |> Enum.map(&human_line/1) |> Enum.each(fn line -> Mix.shell().info(line) end)
    end

    if opts.follow and not opts.json, do: follow(run_id, MapSet.new(events, & &1.id))

    exit_fun().(ExitCodes.fetch!(:success))
  end

  defp parse_args!(args) do
    case OptionParser.parse(args, strict: [json: :boolean, follow: :boolean]) do
      {opts, [run_id], []} ->
        {run_id,
         %{json: Keyword.get(opts, :json, false), follow: Keyword.get(opts, :follow, false)}}

      _ ->
        Mix.raise(usage())
    end
  end

  # --- live follow -----------------------------------------------------------

  # Poll for events not yet printed, render them, and recurse. Runs until the process is
  # interrupted — the manual attended-dogfood loop. Deterministic replay (no --follow) is what the
  # golden test exercises; the follow loop is a thin, injectable-sleep wrapper over the same render.
  defp follow(run_id, seen) do
    sleep().(@poll_interval_ms)

    {new, seen} =
      run_id
      |> RunEventStream.for_run()
      |> Enum.reject(&MapSet.member?(seen, &1.id))
      |> then(fn fresh -> {fresh, MapSet.union(seen, MapSet.new(fresh, & &1.id))} end)

    Enum.each(new, fn event -> Mix.shell().info(human_line(event)) end)

    if follow_continues?().(), do: follow(run_id, seen)
  end

  # --- rendering -------------------------------------------------------------

  defp human_line(event) do
    time = event.occurred_at |> DateTime.to_time() |> Time.truncate(:second) |> Time.to_string()
    detail = summary(event.payload)
    scope = event.slice_id && "  slice=#{short(event.slice_id)}"
    [time, "  ", pad(event.type), detail, scope] |> Enum.reject(&(&1 in [nil, ""])) |> Enum.join()
  end

  defp pad(type), do: String.pad_trailing(type, 26)

  # A concise, deterministic one-liner from the salient payload keys (whichever are present).
  @summary_keys ~w(status gate_result outcome reason park_reason violated_bound class decision
                   granted_paths offending_paths finding_categories rung)
  defp summary(payload) when is_map(payload) do
    @summary_keys
    |> Enum.flat_map(fn key ->
      case Map.get(payload, key) do
        nil -> []
        value -> ["#{key}=#{format_value(value)}"]
      end
    end)
    |> Enum.join(" ")
  end

  defp summary(_payload), do: ""

  defp format_value(value) when is_list(value), do: Enum.join(value, ",")
  defp format_value(value), do: to_string(value)

  defp short(<<head::binary-size(8), _rest::binary>>), do: head
  defp short(value), do: to_string(value)

  # --- JSON (conveyor.watch@1) ----------------------------------------------

  defp json(run_id, events) do
    %{
      "schema_version" => "conveyor.watch@1",
      "run_id" => run_id,
      "event_count" => length(events),
      "events" => Enum.map(events, &event_envelope/1)
    }
    |> Jason.encode!()
  end

  defp event_envelope(event) do
    %{
      "type" => event.type,
      "occurred_at" => DateTime.to_iso8601(event.occurred_at),
      "slice_id" => event.slice_id,
      "run_attempt_id" => event.run_attempt_id,
      "payload" => event.payload
    }
  end

  defp usage, do: "usage: mix conveyor.watch RUN_ID [--json] [--follow]"

  defp exit_fun, do: Process.get(:conveyor_watch_exit_fun, &System.halt/1)
  defp sleep, do: Process.get(:conveyor_watch_sleep_fun, &Process.sleep/1)
  defp follow_continues?, do: Process.get(:conveyor_watch_follow_continues?, fn -> true end)
end
