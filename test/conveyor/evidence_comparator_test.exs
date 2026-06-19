defmodule Conveyor.EvidenceComparatorTest do
  use ExUnit.Case, async: true

  alias Conveyor.Evidence.Comparator

  test "exposes the canonical materiality vocabulary in precedence order" do
    assert Comparator.materiality_labels() == [
             "identical",
             "cosmetic",
             "context_only",
             "evidence_changing",
             "scope_added",
             "scope_removed",
             "scope_reinterpreted",
             "contract_changing",
             "acceptance_weakened",
             "acceptance_strengthened",
             "policy_weakened",
             "policy_strengthened",
             "environment_changing",
             "capability_changing",
             "approval_changing",
             "grant_changing",
             "incomparable"
           ]
  end

  test "preserves multiple materiality labels and derives deterministic precedence" do
    left = subject("policy-bundle:v1", digest: "sha256:left")
    right = subject("policy-bundle:v2", digest: "sha256:right")

    comparison =
      Comparator.compare(left, right,
        materiality_labels: [
          :cosmetic,
          :policy_strengthened,
          :grant_changing,
          :evidence_changing
        ]
      )

    assert comparison.materiality_labels == [
             "cosmetic",
             "evidence_changing",
             "policy_strengthened",
             "grant_changing"
           ]

    assert comparison.dominant_label == "grant_changing"
    assert comparison.summary_status == "materially_different"
    assert comparison.left_subject_id == "policy-bundle:v1"
    assert comparison.right_subject_id == "policy-bundle:v2"
  end

  test "unavailable or authority-invalid subjects are incomparable with the specific reason" do
    left = subject("evidence:old", digest: "sha256:left")

    cases = [
      {subject("evidence:missing", digest: "sha256:right", available?: false),
       "subject_unavailable"},
      {subject("evidence:unauthorized", digest: "sha256:right", authorized?: false),
       "subject_unauthorized"},
      {subject("evidence:erased", digest: "sha256:right", availability: :erased),
       "subject_erased"},
      {subject("evidence:digest-mismatch", digest: "sha256:right", digest_verified?: false),
       "subject_digest_mismatch"}
    ]

    for {invalid_right, expected_reason} <- cases do
      comparison = Comparator.compare(left, invalid_right)

      assert comparison.materiality_labels == ["incomparable"]
      assert comparison.dominant_label == "incomparable"
      assert comparison.summary_status == "incomparable"
      # Pin each invalid subject to its specific reason so a mis-mapped reason is caught.
      assert comparison.incomparable_reason == expected_reason
    end
  end

  defp subject(id, attrs) do
    %{
      subject_kind: :policy_bundle,
      subject_id: id,
      digest: Keyword.fetch!(attrs, :digest),
      available?: Keyword.get(attrs, :available?, true),
      authorized?: Keyword.get(attrs, :authorized?, true),
      availability: Keyword.get(attrs, :availability, :available),
      digest_verified?: Keyword.get(attrs, :digest_verified?, true)
    }
  end
end
