defmodule Conveyor.EvidenceKernelModelsTest do
  use ExUnit.Case, async: true

  @models %{
    "station_lease_stale_epoch" => %{
      "kind" => "state-machine",
      "proves" => "station lease acquisition + stale-epoch rejection"
    },
    "effect_attempt_receipt_reconcile" => %{
      "kind" => "state-machine",
      "proves" => "effect attempt -> receipt -> reconciliation"
    },
    "admission_permit_checkpoint_renewal" => %{
      "kind" => "state-machine",
      "proves" => "AdmissionPermit checkpoint + renewal across a long attempt"
    },
    "emergency_stop_engage_resume" => %{
      "kind" => "state-machine",
      "proves" => "emergency stop engagement/resume"
    },
    "budget_reservation_lifecycle" => %{
      "kind" => "state-machine",
      "proves" => "budget reservation/commit/release/expiry"
    },
    "artifact_staged_committed_gc" => %{
      "kind" => "state-machine",
      "proves" => "artifact staged -> committed -> GC/tombstone"
    },
    "grant_active_expired_revoked" => %{
      "kind" => "state-machine",
      "proves" => "grant active -> expired/revoked/superseded"
    },
    "approval_root_invalidation" => %{
      "kind" => "state-machine",
      "proves" => "approval/root invalidation"
    },
    "run_attempt_terminal_new" => %{
      "kind" => "state-machine",
      "proves" => "RunAttempt terminal / new-attempt semantics"
    },
    "before_external_call" => %{
      "kind" => "crash-test",
      "proves" => "crash before the external call leaves a deterministic retry state"
    },
    "after_accept_before_receipt" => %{
      "kind" => "crash-test",
      "proves" => "crash after external accept before receipt is reconciled, not lost"
    },
    "after_receipt_before_pointer_commit" => %{
      "kind" => "crash-test",
      "proves" => "crash after receipt before artifact-pointer commit recovers"
    },
    "after_blob_staged_before_db_commit" => %{
      "kind" => "crash-test",
      "proves" => "crash after blob staged before DB commit is swept (no orphan)"
    },
    "after_db_commit_before_outbox" => %{
      "kind" => "crash-test",
      "proves" => "crash after DB commit before outbox publish republishes from outbox"
    },
    "after_outbox_before_ack" => %{
      "kind" => "crash-test",
      "proves" => "crash after outbox publish before worker ack is idempotent"
    },
    "after_permit_renewal_before_publish" => %{
      "kind" => "crash-test",
      "proves" => "crash after permit renewal before station publication parks safely"
    }
  }

  test "P15-A3 formal models define transitions, invariants, and counterexamples" do
    for {slug, expected} <- @models do
      model = read_json!("docs/phase-1.5/p15-a3/state-machines/#{slug}.json")

      assert model["schema_version"] == "conveyor.state_model@1"
      assert model["slug"] == slug
      assert model["kind"] == expected["kind"]
      assert model["proves"] == expected["proves"]

      assert is_list(model["states"])
      assert length(model["states"]) >= 3

      assert is_list(model["transitions"])
      assert length(model["transitions"]) >= 3

      assert Enum.all?(model["transitions"], &valid_transition?(&1, model["states"]))

      assert is_list(model["invariants"])
      assert length(model["invariants"]) >= 2

      assert is_list(model["counterexample_traces"])
      assert length(model["counterexample_traces"]) >= 1
    end
  end

  defp valid_transition?(transition, states) do
    transition["from"] in states and transition["to"] in states and
      is_binary(transition["event"]) and transition["event"] != ""
  end

  defp read_json!(path), do: path |> File.read!() |> Jason.decode!()
end
