defmodule Mix.Tasks.Conveyor.Eval.Scorecard do
  @shortdoc "Aggregate eval metrics into a scorecard; optionally gate CI"

  @moduledoc """
  Build the `conveyor.eval_scorecard@1` doc from `eval/scorecards/inputs/*.json`.

      mix conveyor.eval.scorecard [--gate] [--format human|json] [--inputs DIR] [--out PATH] [--revision SHA]

  `--gate` exits non-zero (eval false-negative code) when any blocking metric is
  present. Pure and DB-free: it does not start the app, so it runs in CI without a
  database.
  """

  use Mix.Task

  alias Conveyor.CanonicalJson
  alias Conveyor.CLI.ExitCodes
  alias Conveyor.Eval.Scorecard

  @default_inputs "eval/scorecards/inputs"

  @impl Mix.Task
  def run(args) do
    {:ok, _} = Application.ensure_all_started(:jsv)
    opts = parse_opts!(args)

    inputs_dir = Keyword.get(opts, :inputs, @default_inputs)
    revision = Keyword.get_lazy(opts, :revision, &git_revision/0)

    scorecard =
      inputs_dir
      |> Scorecard.load_inputs()
      |> Scorecard.build(revision: revision)

    case Scorecard.validate(scorecard) do
      :ok ->
        :ok

      {:error, error} ->
        Mix.raise("scorecard failed conveyor.eval_scorecard@1 validation: #{inspect(error)}")
    end

    if path = opts[:out], do: File.write!(path, CanonicalJson.encode(scorecard))

    scorecard
    |> render(Keyword.get(opts, :format, "json"))
    |> Mix.shell().info()

    exit_fun().(exit_code(scorecard, opts))
  end

  defp parse_opts!(args) do
    {opts, rest, invalid} =
      OptionParser.parse(args,
        strict: [
          gate: :boolean,
          format: :string,
          inputs: :string,
          out: :string,
          revision: :string
        ]
      )

    if rest != [] or invalid != [], do: Mix.raise(@moduledoc)
    opts
  end

  defp exit_code(scorecard, opts) do
    if Keyword.get(opts, :gate, false) and not Scorecard.healthy?(scorecard),
      do: ExitCodes.fetch!(:canary_or_eval_false_negative),
      else: ExitCodes.fetch!(:success)
  end

  defp render(scorecard, "human") do
    blockers = scorecard["canonical_blockers"]

    header =
      "eval scorecard @ #{scorecard["generated_for"]} — " <>
        if(scorecard["healthy?"], do: "HEALTHY", else: "BLOCKED (#{length(blockers)})")

    lines =
      Enum.map(scorecard["metrics"], fn m ->
        "  [#{m["status"]}] #{m["suite"]}/#{m["key"]} = #{inspect(m["value"])} (target #{inspect(m["target"])})"
      end)

    Enum.join([header | lines], "\n")
  end

  defp render(scorecard, _json), do: CanonicalJson.encode(scorecard)

  defp git_revision do
    case System.cmd("git", ["rev-parse", "HEAD"], stderr_to_stdout: true) do
      {sha, 0} -> String.trim(sha)
      _ -> "unknown"
    end
  end

  defp exit_fun, do: Process.get(:conveyor_eval_scorecard_exit_fun, &System.halt/1)
end
