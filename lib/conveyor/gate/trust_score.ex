defmodule Conveyor.Gate.TrustScore do
  @moduledoc """
  ADR-23 — calibrated trust scoring for the ternary gate verdict.

  A **pure** fusion of signals Conveyor already computes (the IntegritySentinel
  verdict, acceptance calibration, baseline health, replay divergence, and the
  Genome's historical pass rate) into a calibrated estimate of whether a *passed*
  gate verdict is trustworthy, plus the band that estimate falls into:

    * `:auto_accept` — confident enough to merge unattended;
    * `:abstain`     — passed the stages but not calibrated-confident; route to
      the human (`Slice` -> `:parked`). Abstain is fail-closed; it never merges.

  TrustScore only adjudicates *passed* gates. A stage failure already produced
  `passed? == false` upstream, so there is no `fail` band here.

  ## Conservative bootstrap (ADR-23)

  Auto-accept requires BOTH (a) no untrustworthy signal — the IntegritySentinel
  must say `"trustworthy"`, calibration must be `:valid`, baseline `:green`, and
  replay non-divergent — AND (b) the weighted `score` clearing the `auto_accept`
  threshold. Anything less abstains. This is deliberately strict early; the
  threshold and weights (content-addressed in `policy_digest`) loosen as the
  corpus accrues labeled outcomes. The corpus pass rate is a positive *boost*, not
  a gate: its absence (a cold start) must never make the known-good reference
  abstain (the `loop_integrity` invariant).

  Determinism boundary: a conductor-side computation over recorded evidence with
  no I/O, clock, or RNG. No agent input enters the score.
  """

  @type band :: :auto_accept | :abstain

  @type evidence :: %{
          optional(:integrity_verdict) => String.t() | nil,
          optional(:calibration_status) => :valid | :invalid | :not_assessed,
          optional(:baseline_status) => :green | :red | :unknown,
          optional(:replay_divergence) => :none | :diverged | :baseline_absent | :unknown,
          optional(:corpus_pass_rate) => float() | nil,
          optional(:review_decision) =>
            :accepted | :not_assessed | :rejected | :needs_rework | nil
        }

  @type result :: %{
          score: float(),
          band: band(),
          components: %{
            integrity: float(),
            calibration: float(),
            baseline: float(),
            replay: float(),
            corpus: float()
          },
          thresholds: %{auto_accept: float()},
          policy_digest: String.t()
        }

  # Component weights sum to 1.0; integrity carries the most because the
  # anti-vacuity oracle is the strongest single trust signal.
  @default_weights %{
    integrity: 0.30,
    calibration: 0.20,
    baseline: 0.20,
    replay: 0.15,
    corpus: 0.15
  }
  @default_thresholds %{auto_accept: 0.9}

  @doc """
  Evaluate the calibrated trust of a passed gate verdict from recorded evidence.

  `opts` may carry `:thresholds` and `:weights` overrides; both feed the
  content-addressed `:policy_digest`. Pure: identical inputs yield identical
  output.
  """
  @spec evaluate(evidence(), keyword()) :: result()
  def evaluate(evidence, opts \\ []) when is_map(evidence) and is_list(opts) do
    weights = Keyword.get(opts, :weights, @default_weights)
    thresholds = Keyword.get(opts, :thresholds, @default_thresholds)
    auto_accept = Map.get(thresholds, :auto_accept, 0.9)

    replay = fetch(evidence, :replay_divergence)

    components = %{
      integrity: integrity_score(fetch(evidence, :integrity_verdict)),
      calibration: calibration_score(fetch(evidence, :calibration_status)),
      baseline: baseline_score(fetch(evidence, :baseline_status)),
      replay: replay_score(replay),
      corpus: corpus_score(fetch(evidence, :corpus_pass_rate))
    }

    # OD19: a replay verdict with no committed baseline (:baseline_absent) is non-blocking;
    # its weight is redistributed across the remaining (assessable) signals, so a cold-start
    # slice is not penalized for the system lacking a replay baseline yet.
    score = weighted_sum(components, effective_weights(weights, replay))
    band = if trustworthy?(evidence) and score >= auto_accept, do: :auto_accept, else: :abstain

    %{
      score: score,
      band: band,
      components: components,
      thresholds: %{auto_accept: auto_accept},
      # The policy_digest hashes the STATIC weights — the renormalization is a runtime,
      # per-evaluation rebalance, not a policy change, so the static path stays digest-stable.
      policy_digest: policy_digest(weights, auto_accept)
    }
  end

  # OD19: drop replay's weight when there is no baseline to compare against and renormalize
  # the remaining signals to sum to 1.0. Any other replay verdict keeps the static weights.
  defp effective_weights(weights, :baseline_absent) do
    dropped = Map.get(weights, :replay, 0.0)
    total = (weights |> Map.values() |> Enum.sum()) - dropped

    weights
    |> Map.new(fn {component, weight} -> {component, weight / total} end)
    |> Map.put(:replay, 0.0)
  end

  defp effective_weights(weights, _replay), do: weights

  # --- trust gate (hard requirements for auto-accept) ------------------------

  # Every non-corpus signal must be unambiguously good. The corpus pass rate is
  # intentionally excluded so a cold start (no corpus) cannot block the known-good
  # reference (loop_integrity).
  defp trustworthy?(evidence) do
    fetch(evidence, :integrity_verdict) == "trustworthy" and
      fetch(evidence, :calibration_status) == :valid and
      fetch(evidence, :baseline_status) == :green and
      replay_ok?(fetch(evidence, :replay_divergence)) and
      review_ok?(fetch(evidence, :review_decision))
  end

  # m4b2.4: the independent-review signal is OPTIONAL in the evidence — absent (nil) means review is
  # not a factor for this run (reviewer_aggregation off), so a cold-start reference is unaffected
  # (loop_integrity). When present it must be `:accepted`; any other value (an unmeasured/absent
  # review recorded as :not_assessed, or a rejection) is never laundered into a trustworthy verdict.
  defp review_ok?(nil), do: true
  defp review_ok?(:accepted), do: true
  defp review_ok?("accepted"), do: true
  defp review_ok?(_present_not_accepted), do: false

  # :none = the run matched its replay baseline; :baseline_absent = no baseline to compare
  # (OD19 — non-blocking, weight-renormalized). A real :diverged (or anything else) blocks.
  defp replay_ok?(:none), do: true
  defp replay_ok?(:baseline_absent), do: true
  defp replay_ok?(_other), do: false

  # --- component scoring ([0.0, 1.0]) ---------------------------------------

  defp integrity_score("trustworthy"), do: 1.0
  defp integrity_score("suspect"), do: 0.5
  defp integrity_score("not_assessed"), do: 0.5
  defp integrity_score(_other), do: 0.0

  defp calibration_score(:valid), do: 1.0
  defp calibration_score(:not_assessed), do: 0.5
  defp calibration_score(_other), do: 0.0

  defp baseline_score(:green), do: 1.0
  defp baseline_score(:unknown), do: 0.5
  defp baseline_score(_other), do: 0.0

  defp replay_score(:none), do: 1.0
  defp replay_score(:baseline_absent), do: 0.5
  defp replay_score(:unknown), do: 0.5
  defp replay_score(_other), do: 0.0

  defp corpus_score(rate) when is_float(rate), do: rate |> max(0.0) |> min(1.0)
  defp corpus_score(_other), do: 0.5

  defp weighted_sum(components, weights) do
    Enum.reduce(components, 0.0, fn {component, value}, acc ->
      acc + value * Map.get(weights, component, 0.0)
    end)
  end

  # --- content-addressed policy ---------------------------------------------

  defp policy_digest(weights, auto_accept) do
    "sha256:" <> hash(%{"weights" => weights, "auto_accept" => auto_accept})
  end

  defp hash(value) do
    value
    |> canonical()
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp canonical(map) when is_map(map) do
    map
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
    |> Map.new(fn {key, value} -> {to_string(key), canonical(value)} end)
  end

  defp canonical(list) when is_list(list), do: Enum.map(list, &canonical/1)
  defp canonical(value), do: value

  # Read a key whether the evidence map uses atom or string keys.
  defp fetch(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, to_string(key))
    end
  end
end
