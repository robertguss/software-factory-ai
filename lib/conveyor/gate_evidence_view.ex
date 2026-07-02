defmodule Conveyor.GateEvidenceView do
  @moduledoc """
  a3hf.1.2.1: a read-only projection of a recorded `GateResult` into the Trust-Evidence "Why"
  view-model — the auditable reasoning behind a verdict. For each gate it exposes:

    * `stages` — every gate stage's key + pass/fail + whether it was required;
    * `signals` — each calibrated trust signal's value (its normalized component score), static
      weight, and contribution (value × weight) — the per-signal breakdown behind the score;
    * `score` / `band` — the calibrated TrustScore and the accept/abstain band it fell into;
    * `park_reason` — the typed reason when a passed gate abstained and parked.

  Projection only — it derives nothing new, reads no live gate state, and never writes. It reads
  what the gate already recorded (`GateResult.stages` + `GateResult.trust_score` +
  `GateResult.park_reason`), so it works post-hoc from any persisted verdict. A stage-failure gate
  (no trust verdict) still projects: its stages carry the failure and `signals` is empty.
  """

  alias Conveyor.Factory.GateResult
  alias Conveyor.Gate.TrustScore

  # Rendered in this fixed order so the Why panel is stable across verdicts.
  @signal_order [:integrity, :calibration, :baseline, :replay, :corpus]

  @type signal :: %{
          name: atom(),
          value: float() | nil,
          weight: float() | nil,
          contribution: float() | nil
        }

  @type view :: %{
          passed: boolean(),
          band: atom() | nil,
          score: float() | nil,
          thresholds: map() | nil,
          park_reason: String.t() | nil,
          stages: [map()],
          signals: [signal()]
        }

  @spec project(GateResult.t()) :: view()
  def project(%GateResult{} = gate_result) do
    trust = gate_result.trust_score

    %{
      passed: gate_result.passed,
      band: band(trust),
      score: get(trust, "score"),
      thresholds: get(trust, "thresholds"),
      park_reason: gate_result.park_reason,
      stages: Enum.map(gate_result.stages, &stage_view/1),
      signals: signals(trust)
    }
  end

  defp band(nil), do: nil

  defp band(trust) do
    case get(trust, "band") do
      value when is_binary(value) -> String.to_existing_atom(value)
      value when is_atom(value) -> value
      _ -> nil
    end
  end

  defp stage_view(stage) do
    %{
      key: get(stage, "key"),
      status: get(stage, "status"),
      required: get(stage, "required?") || get(stage, "required")
    }
  end

  defp signals(nil), do: []

  defp signals(trust) do
    components = get(trust, "components") || %{}
    weights = TrustScore.default_weights()

    Enum.map(@signal_order, fn name ->
      value = component_value(components, name)
      weight = Map.get(weights, name)

      %{name: name, value: value, weight: weight, contribution: contribution(value, weight)}
    end)
  end

  defp component_value(components, name), do: get(components, Atom.to_string(name))

  defp contribution(value, weight) when is_number(value) and is_number(weight), do: value * weight
  defp contribution(_value, _weight), do: nil

  # Persisted `:map` attributes are string-keyed; an in-memory (test-built) map may be atom-keyed.
  defp get(nil, _key), do: nil

  defp get(map, key) when is_map(map) and is_binary(key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, safe_atom(key))
    end
  end

  defp safe_atom(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end
end
