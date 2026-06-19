defmodule Conveyor.Eval.SentinelTournament do
  @moduledoc """
  The Sentinel Evasion Tournament (E8): measures how hard it is to sneak a
  vacuous-but-passing test suite past the `IntegritySentinel`.

  For every distinct rule_key it plants a vacuity (a single perturbation of the
  all-pass `clean_observations/0`) that the sentinel *should* catch, and confirms
  it does. Any planted vacuity that yields `trustworthy` is an **evasion** — a
  verifier false-negative — and would flip `sentinel_evasion_rate` red. `falsifier_seed.dropped`
  is checked via `Verification.evaluate_falsifier_preservation/2` (obligation-level,
  distinct from the sentinel's `test_integrity.falsifier_dropped`).

  Pure / DB-free. Emits `sentinel_evasion_rate` (target 0, blocking) and
  `sentinel_probe_coverage` (target 1) to the F2 scorecard.
  """

  alias Conveyor.Eval.{Scorecard, SentinelFixtures}
  alias Conveyor.Verification
  alias Conveyor.Verification.IntegritySentinel

  @suite "sentinel_tournament"
  @evaluated_at "2026-06-19T00:00:00Z"

  @doc "Run the tournament and return its report map."
  @spec run(keyword()) :: map()
  def run(opts \\ []) do
    evaluated_at = Keyword.get(opts, :evaluated_at, @evaluated_at)
    clean = SentinelFixtures.clean_observations()
    spec = SentinelFixtures.spec_attrs()

    probe_results =
      Enum.map(SentinelFixtures.trip_cases(), fn c ->
        run =
          IntegritySentinel.run(spec, put_in(clean, c.path, c.trip), evaluated_at: evaluated_at)

        caught? =
          run["verdict"] != "trustworthy" and
            Enum.any?(run["findings"], &(&1["rule_key"] == c.rule_key))

        %{rule_key: c.rule_key, caught?: caught?, verdict: run["verdict"]}
      end)

    results = probe_results ++ [falsifier_dropped_result()]

    evasions = results |> Enum.reject(& &1.caught?) |> Enum.map(& &1.rule_key)
    total = length(results)

    covered = results |> Enum.filter(& &1.caught?) |> MapSet.new(& &1.rule_key)
    all = MapSet.new(SentinelFixtures.all_rule_keys())

    %{
      "schema_version" => "conveyor.eval_sentinel_tournament@1",
      "rule_key_count" => total,
      "caught" => total - length(evasions),
      "evasions" => evasions,
      "evasion_rate" => length(evasions) / total,
      "probe_coverage" => MapSet.size(MapSet.intersection(covered, all)) / MapSet.size(all)
    }
  end

  @doc "Map a tournament report to its `conveyor.eval_metric@1` metrics."
  @spec metrics(map()) :: [map()]
  def metrics(report) do
    [
      Scorecard.metric("sentinel_evasion_rate", @suite, report["evasion_rate"], 0,
        blocking: true,
        detail: "#{report["caught"]}/#{report["rule_key_count"]} planted vacuities caught"
      ),
      Scorecard.metric("sentinel_probe_coverage", @suite, report["probe_coverage"], 1,
        detail: "rule_keys with both pass and trip fixtures"
      )
    ]
  end

  @doc "Run the tournament and write its metrics to the scorecard inputs dir."
  @spec emit!(keyword()) :: map()
  def emit!(opts \\ []) do
    report = run(opts)
    Scorecard.write_input!(@suite, metrics(report))
    report
  end

  # falsifier_seed.dropped is obligation-level: a seed with no preservation record.
  defp falsifier_dropped_result do
    seeds = [
      %{
        "id" => "compiler_falsifier_seed:abc",
        "verification_obligation_id" => "verification_obligation:001"
      }
    ]

    report = Verification.evaluate_falsifier_preservation(seeds, [])
    findings = report["findings"] || []
    caught? = Enum.any?(findings, &(&1["rule_key"] == "falsifier_seed.dropped"))
    %{rule_key: "falsifier_seed.dropped", caught?: caught?, verdict: report["result"]}
  end
end
