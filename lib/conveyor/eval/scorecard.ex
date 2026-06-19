defmodule Conveyor.Eval.Scorecard do
  @moduledoc """
  Versioned, deterministic projection that aggregates every eval suite's metrics
  into one glanceable, CI-gating report (idea #9). Mirrors
  `Conveyor.Battery.ReleaseReport`: a map carrying a `"schema_version"` token plus
  a structured `"canonical_blockers"` list so a prose summary can never hide a
  blocker.

  Each eval suite writes its metrics (`conveyor.eval_metric@1`) to
  `eval/scorecards/inputs/*.json`; `build/2` ingests them into one
  `conveyor.eval_scorecard@1` doc, content-addressed via
  `Conveyor.CanonicalJson.digest/1`. Pure — no Repo/clock/RNG; the git revision is
  passed in (`:revision`).
  """

  alias Conveyor.CanonicalJson
  alias Conveyor.Eval.Schema

  @schema_version "conveyor.eval_scorecard@1"
  @inputs_dir "eval/scorecards/inputs"

  @doc "The default directory eval suites write their metric inputs to."
  @spec inputs_dir() :: String.t()
  def inputs_dir, do: @inputs_dir

  @doc """
  Write a suite's metrics (`conveyor.eval_metric@1` maps) to
  `eval/scorecards/inputs/<name>.json` (canonical JSON). Returns the path.
  """
  @spec write_input!(String.t(), [map()]) :: String.t()
  def write_input!(name, metrics) when is_list(metrics) do
    File.mkdir_p!(@inputs_dir)
    path = Path.join(@inputs_dir, name <> ".json")
    File.write!(path, CanonicalJson.encode(metrics))
    path
  end

  @doc """
  Aggregate eval metric maps (`conveyor.eval_metric@1`) into one deterministic
  scorecard. `opts[:revision]` (the git sha) is required and recorded as
  `generated_for`. Same inputs + revision → byte-identical output.
  """
  @spec build([map()], keyword()) :: map()
  def build(metrics, opts) when is_list(metrics) do
    normalized = metrics |> Enum.map(&normalize_metric/1) |> Enum.sort_by(& &1["key"])
    blockers = Enum.filter(normalized, &(&1["status"] == "blocking"))

    base = %{
      "schema_version" => @schema_version,
      "generated_for" => Keyword.fetch!(opts, :revision),
      "metrics" => normalized,
      "canonical_blockers" => blockers,
      "healthy?" => blockers == []
    }

    Map.put(base, "scorecard_digest", CanonicalJson.digest(base))
  end

  @doc """
  Build a `conveyor.eval_metric@1` map. Status is derived from `value` vs `target`
  unless given explicitly: equal → `"ok"`; otherwise `"blocking"` if `blocking:`
  else `"warn"`. Opts: `:blocking` (bool), `:status`, `:detail`, `:ci`.
  """
  @spec metric(
          String.t(),
          String.t(),
          number() | String.t() | boolean(),
          number() | String.t() | boolean(),
          keyword()
        ) ::
          map()
  def metric(key, suite, value, target, opts \\ []) do
    blocking = Keyword.get(opts, :blocking, false)

    status =
      cond do
        opts[:status] -> opts[:status]
        value == target -> "ok"
        blocking -> "blocking"
        true -> "warn"
      end

    %{
      "schema_version" => "conveyor.eval_metric@1",
      "key" => key,
      "suite" => suite,
      "value" => value,
      "target" => target,
      "blocking" => blocking,
      "status" => status
    }
    |> put_optional("detail", opts[:detail])
    |> put_optional("ci", opts[:ci])
  end

  @doc "Whether the scorecard has no blocking metric (the `--gate` predicate)."
  @spec healthy?(map()) :: boolean()
  def healthy?(scorecard), do: scorecard["healthy?"] == true

  @doc """
  Load metric inputs (`conveyor.eval_metric@1` JSON files) from `dir`, sorted by
  filename for determinism. A missing directory yields `[]` (degrades gracefully
  to an empty, healthy scorecard).
  """
  @spec load_inputs(String.t()) :: [map()]
  def load_inputs(dir) do
    case File.ls(dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".json"))
        |> Enum.sort()
        |> Enum.flat_map(&decode_metrics(Path.join(dir, &1)))

      {:error, _} ->
        []
    end
  end

  defp decode_metrics(path) do
    case path |> File.read!() |> Jason.decode!() do
      list when is_list(list) -> list
      map when is_map(map) -> [map]
    end
  end

  @doc "Validate a scorecard map against `conveyor.eval_scorecard@1` (jsv)."
  @spec validate(map()) :: :ok | {:error, term()}
  def validate(scorecard), do: Schema.validate(scorecard, @schema_version)

  defp normalize_metric(m) do
    %{
      "key" => m["key"],
      "suite" => m["suite"],
      "value" => m["value"],
      "target" => m["target"],
      "blocking" => m["blocking"] == true,
      "status" => m["status"] || "ok"
    }
    |> put_optional("detail", m["detail"])
    |> put_optional("ci", m["ci"])
  end

  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)
end
