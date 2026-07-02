defmodule Conveyor.GateEvidenceViewTest do
  @moduledoc """
  a3hf.1.2.1: the gate-evidence read-model projects a recorded GateResult into the Why view-model.
  trust_score/stages are string-keyed maps here, mirroring the persisted (jsonb) shape. The
  comprehensive accept+park view-model e2e is the Tests-sibling a3hf.1.2.3.
  """
  use ExUnit.Case, async: true

  alias Conveyor.Factory.GateResult
  alias Conveyor.GateEvidenceView

  defp trust_score(band, score) do
    %{
      "band" => band,
      "score" => score,
      "components" => %{
        "integrity" => 1.0,
        "calibration" => 1.0,
        "baseline" => 1.0,
        "replay" => 1.0,
        "corpus" => 0.95
      },
      "thresholds" => %{"auto_accept" => 0.9}
    }
  end

  defp stages do
    [
      %{"key" => "workspace_integrity", "status" => "passed", "required?" => true},
      %{"key" => "test_execution", "status" => "passed", "required?" => true}
    ]
  end

  test "an accepted gate yields the full stages + per-signal breakdown + band" do
    gate = %GateResult{
      passed: true,
      stages: stages(),
      trust_score: trust_score("auto_accept", 0.98),
      park_reason: nil
    }

    view = GateEvidenceView.project(gate)

    assert view.passed
    assert view.band == :auto_accept
    assert view.score == 0.98
    assert view.park_reason == nil

    assert Enum.map(view.stages, & &1.key) == ["workspace_integrity", "test_execution"]
    assert Enum.all?(view.stages, &(&1.status == "passed"))

    # every trust signal carries value + weight + contribution (value * weight)
    assert Enum.map(view.signals, & &1.name) == [
             :integrity,
             :calibration,
             :baseline,
             :replay,
             :corpus
           ]

    integrity = Enum.find(view.signals, &(&1.name == :integrity))
    assert integrity.value == 1.0
    assert integrity.weight == 0.30
    assert integrity.contribution == 1.0 * 0.30

    corpus = Enum.find(view.signals, &(&1.name == :corpus))
    assert corpus.value == 0.95
    assert_in_delta corpus.contribution, 0.95 * 0.15, 1.0e-9
  end

  test "a parked (abstained) gate surfaces the band and the typed park reason" do
    gate = %GateResult{
      passed: true,
      stages: stages(),
      trust_score: trust_score("abstain", 0.42),
      park_reason: "missing_signal"
    }

    view = GateEvidenceView.project(gate)

    assert view.band == :abstain
    assert view.score == 0.42
    assert view.park_reason == "missing_signal"
    # still a complete breakdown so the operator can see WHY it abstained
    assert length(view.signals) == 5
  end

  test "a stage-failure gate (no trust verdict) still projects — stages carry the failure" do
    gate = %GateResult{
      passed: false,
      stages: [
        %{"key" => "diff_scope", "status" => "failed", "required?" => true},
        %{"key" => "test_execution", "status" => "passed", "required?" => true}
      ],
      trust_score: nil,
      park_reason: nil
    }

    view = GateEvidenceView.project(gate)

    refute view.passed
    assert view.band == nil
    assert view.score == nil
    assert view.signals == []
    assert Enum.find(view.stages, &(&1.status == "failed")).key == "diff_scope"
  end

  test "tolerates an atom-keyed trust_score (in-memory, not yet round-tripped through jsonb)" do
    gate = %GateResult{
      passed: true,
      stages: [%{key: "test_execution", status: "passed"}],
      trust_score: %{band: :auto_accept, score: 0.95, components: %{integrity: 1.0}},
      park_reason: nil
    }

    view = GateEvidenceView.project(gate)

    assert view.band == :auto_accept
    assert view.score == 0.95
    assert Enum.find(view.signals, &(&1.name == :integrity)).value == 1.0
    assert Enum.find(view.stages, & &1).key == "test_execution"
  end
end
