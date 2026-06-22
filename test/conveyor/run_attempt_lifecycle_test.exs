defmodule Conveyor.RunAttemptLifecycleTest do
  use Conveyor.DataCase, async: false

  import Conveyor.FactoryFixtures

  alias Conveyor.RunAttemptLifecycle

  # Regression for the M1 live-run bug: the SerialDriver/Finalizer can hold a STALE
  # run_attempt struct (its in-memory :status predates the stations that advanced the
  # persisted record). AshStateMachine validates a transition against the struct's
  # state, so `:gate` fired on a stale :planned struct raised NoMatchingTransition
  # ("planned -> gated"). transition!/3 must re-load and transition from persisted truth.
  test "transition! operates on persisted state, not a caller's stale struct" do
    fixture = create_artifact_run!(blob_root: temp_dir!("run-attempt-lifecycle"))
    stale = fixture.run_attempt
    assert stale.status == :planned

    # Advance the PERSISTED record while deliberately keeping the original `stale`
    # struct (still :planned in memory) — mirroring the live path where stations move
    # the DB record forward but the driver's local var is not refreshed.
    RunAttemptLifecycle.transition!(stale, :start)
    RunAttemptLifecycle.transition!(stale, :record_evidence)

    # Passing the stale :planned struct: before the fix this raised
    # NoMatchingTransition (the :record_evidence step above already would). With the
    # re-load, each transition fires from the current persisted state.
    updated = RunAttemptLifecycle.transition!(stale, :gate, attrs: %{outcome: :accepted})

    assert updated.status == :gated
    assert updated.outcome == :accepted
  end
end
