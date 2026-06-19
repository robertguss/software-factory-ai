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
        |> Enum.map(&(dir |> Path.join(&1) |> File.read!() |> Jason.decode!()))

      {:error, _} ->
        []
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
