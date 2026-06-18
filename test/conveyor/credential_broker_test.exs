defmodule Conveyor.CredentialBrokerTest do
  use Conveyor.DataCase, async: false

  import Conveyor.FactoryFixtures

  alias Conveyor.CredentialBroker
  alias Conveyor.Factory
  alias Conveyor.Factory.CredentialLease

  test "issues a scoped expiring lease without persisting secret values" do
    fixture = create_artifact_run!(blob_root: temp_dir!("credential-broker-blobs"))
    run_spec = get_by_id!(Conveyor.Factory.RunSpec, fixture.run_attempt.run_spec_id)
    issued_at = ~U[2026-06-18 00:00:00.000000Z]

    issued =
      CredentialBroker.issue!(run_spec, "openai",
        station_run: fixture.station_run,
        env: %{"OPENAI_API_KEY" => "sk-test-secret"},
        allowed_env_keys: ["OPENAI_API_KEY"],
        issued_at: issued_at,
        ttl_seconds: 60
      )

    assert issued.env == %{"OPENAI_API_KEY" => "sk-test-secret"}
    assert issued.lease.provider == "openai"
    assert issued.lease.env_keys == ["OPENAI_API_KEY"]
    assert issued.lease.scope == "run_spec:#{run_spec.id}"
    assert issued.lease.status == :active
    assert DateTime.diff(issued.lease.expires_at, issued_at, :second) == 60

    [persisted] = Ash.read!(CredentialLease, domain: Factory)
    persisted_text = inspect(persisted)
    refute String.contains?(persisted_text, "sk-test-secret")
  end

  test "rejects env keys outside the policy allowlist" do
    fixture = create_artifact_run!(blob_root: temp_dir!("credential-policy-blobs"))
    run_spec = get_by_id!(Conveyor.Factory.RunSpec, fixture.run_attempt.run_spec_id)

    assert_raise ArgumentError, ~r/not allowed by policy/, fn ->
      CredentialBroker.issue!(run_spec, "openai",
        env: %{"OPENAI_API_KEY" => "sk-test-secret"},
        allowed_env_keys: []
      )
    end
  end

  test "revokes active leases for run completion and expires stale leases" do
    fixture = create_artifact_run!(blob_root: temp_dir!("credential-revoke-blobs"))
    run_spec = get_by_id!(Conveyor.Factory.RunSpec, fixture.run_attempt.run_spec_id)

    active =
      CredentialBroker.issue!(run_spec, "openai",
        env: %{"OPENAI_API_KEY" => "sk-active"},
        allowed_env_keys: ["OPENAI_API_KEY"]
      )

    assert [revoked] = CredentialBroker.revoke_for_run_spec!(run_spec)
    assert revoked.id == active.lease.id
    assert revoked.status == :revoked
    assert revoked.revoked_at

    expired =
      CredentialBroker.issue!(run_spec, "anthropic",
        env: %{"ANTHROPIC_API_KEY" => "sk-expired"},
        allowed_env_keys: ["ANTHROPIC_API_KEY"],
        issued_at: ~U[2026-06-18 00:00:00.000000Z],
        ttl_seconds: 1
      )

    assert [stale] = CredentialBroker.expire_stale!(now: ~U[2026-06-18 00:00:02.000000Z])
    assert stale.id == expired.lease.id
    assert stale.status == :expired
    assert stale.revoked_at
  end

  defp get_by_id!(resource, id) do
    resource
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == id))
  end
end
