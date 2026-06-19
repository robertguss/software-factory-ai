defmodule Conveyor.CassettesTest do
  use ExUnit.Case, async: true

  alias Conveyor.Cassettes

  @series_attrs %{
    spec_kind: :run_spec,
    spec_digest: "sha256:1111111111111111111111111111111111111111111111111111111111111111",
    role: "implementer",
    adapter: "primary-live",
    agent_profile_snapshot_digest:
      "sha256:2222222222222222222222222222222222222222222222222222222222222222",
    capability_snapshot_digest:
      "sha256:3333333333333333333333333333333333333333333333333333333333333333",
    generation_environment_fingerprint_digest:
      "sha256:4444444444444444444444444444444444444444444444444444444444444444",
    generation_freshness_digest:
      "sha256:5555555555555555555555555555555555555555555555555555555555555555",
    created_at: "2026-06-19T00:00:00Z"
  }

  test "CassetteSeries identity is deterministic for one role/spec/adapter generation surface" do
    first = Cassettes.new_series!(@series_attrs)
    second = Cassettes.new_series!(@series_attrs)
    other_adapter = Cassettes.new_series!(%{@series_attrs | adapter: "secondary-live"})

    assert first["schema_version"] == "conveyor.cassette_series@1"
    assert first["id"] == second["id"]
    assert first["id"] != other_adapter["id"]
    assert first["adapter"] == "primary-live"
  end

  test "recording seals only after redaction and stamps exact provider identity" do
    series = Cassettes.new_series!(@series_attrs)

    assert {:ok, cassette} =
             Cassettes.record(series,
               recording_no: 1,
               provider: %{
                 model_id: "provider-model",
                 model_revision: "rev-2026-06-19",
                 request_id: "req-1"
               },
               provider_parameters: %{"temperature" => 0.1},
               agent_event_stream: [%{"event_type" => "message_completed"}],
               tool_transcript: [%{"tool" => "shell", "result" => "ok"}],
               primary_outputs: ["token=sk-SECRETSECRET"],
               retention_class: "qualification",
               recorded_at: "2026-06-19T00:01:00Z",
               redaction_policy: :redact
             )

    assert cassette["schema_version"] == "conveyor.agent_cassette@1"
    assert cassette["cassette_series_id"] == series["id"]
    assert cassette["seal_status"] == "sealed"
    assert cassette["provider_identity_confidence"] == "exact"
    assert cassette["provider_model_revision"] == "rev-2026-06-19"
    assert ["token=[REDACTED:openai_api_key:" <> _rest] = cassette["primary_outputs"]
    assert [%{"category" => "secret_exposure"}] = cassette["redaction_report"]["findings"]

    # The sealed cassette must actually conform to the schema it stamps (inline shape).
    schema =
      "docs/schemas/conveyor.agent_cassette@1.json"
      |> File.read!()
      |> Jason.decode!()
      |> JSV.build!()

    assert {:ok, _validated} = JSV.validate(cassette, schema)
  end

  test "blocked redaction or missing integrity input rejects a cassette instead of sealing it" do
    series = Cassettes.new_series!(@series_attrs)

    assert {:error, blocked} =
             Cassettes.record(series,
               recording_no: 1,
               provider: %{model_id: "provider-model"},
               agent_event_stream: [%{"event_type" => "message_completed"}],
               tool_transcript: [],
               primary_outputs: ["AWS_SECRET=abc123"],
               recorded_at: "2026-06-19T00:01:00Z",
               redaction_policy: :block
             )

    assert blocked["seal_status"] == "rejected"
    assert blocked["invalidation_reason"] == "redaction_blocked"
    assert blocked["provider_identity_confidence"] == "declared_only"

    assert {:error, integrity} =
             Cassettes.record(series,
               recording_no: 2,
               provider: %{model_family: "provider-family"},
               primary_outputs: ["ok"],
               recorded_at: "2026-06-19T00:02:00Z"
             )

    assert integrity["seal_status"] == "rejected"
    assert integrity["invalidation_reason"] == "missing_agent_event_stream"
    assert integrity["provider_identity_confidence"] == "family_only"
  end
end
