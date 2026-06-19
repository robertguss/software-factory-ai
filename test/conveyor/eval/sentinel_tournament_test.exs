defmodule Conveyor.Eval.SentinelTournamentTest do
  use ExUnit.Case, async: true

  alias Conveyor.Eval.{SentinelFixtures, SentinelTournament}
  alias Conveyor.Verification.IntegritySentinel

  @moduletag :eval
  @evaluated_at "2026-06-19T00:00:00Z"

  test "clean observations are trustworthy with no test_integrity findings (passing fixture)" do
    run =
      IntegritySentinel.run(SentinelFixtures.spec_attrs(), SentinelFixtures.clean_observations(),
        evaluated_at: @evaluated_at
      )

    assert run["verdict"] == "trustworthy"

    refute Enum.any?(run["findings"], fn f ->
             String.starts_with?(f["rule_key"], "test_integrity")
           end)
  end

  # One tripping fixture per rule_key: planting the vacuity must fire exactly that
  # rule_key and reach the expected verdict.
  for c <- SentinelFixtures.trip_cases() do
    test "tripping fixture fires #{c.rule_key}" do
      obs = put_in(SentinelFixtures.clean_observations(), unquote(c.path), unquote(c.trip))

      run =
        IntegritySentinel.run(SentinelFixtures.spec_attrs(), obs, evaluated_at: @evaluated_at)

      assert run["verdict"] == unquote(c.verdict)
      assert Enum.any?(run["findings"], &(&1["rule_key"] == unquote(c.rule_key)))
    end
  end

  test "tournament: zero evasions and full probe coverage" do
    report = SentinelTournament.run(evaluated_at: @evaluated_at)

    assert report["evasion_rate"] == 0.0
    assert report["evasions"] == []
    assert report["probe_coverage"] == 1.0
    assert report["caught"] == report["rule_key_count"]
  end

  test "metrics: evasion_rate is blocking@0, coverage@1" do
    report = SentinelTournament.run(evaluated_at: @evaluated_at)
    [evasion, coverage] = SentinelTournament.metrics(report)

    assert evasion["key"] == "sentinel_evasion_rate"
    assert evasion["blocking"] == true
    assert evasion["status"] == "ok"

    assert coverage["key"] == "sentinel_probe_coverage"
    assert coverage["status"] == "ok"
  end
end
