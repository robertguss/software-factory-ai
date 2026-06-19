defmodule Conveyor.ControlPlaneHardeningTest do
  use ExUnit.Case, async: true

  alias Conveyor.AdapterHealth
  alias Conveyor.BudgetReservations
  alias Conveyor.ControlPlaneCanaries
  alias Conveyor.EmergencyStop
  alias Conveyor.Retention
  alias Conveyor.SealedRecorder

  test "retention GC preserves active authority and emits erasure tombstones" do
    artifacts = [
      %{
        id: "active-approval",
        retention_class: :audit,
        availability: :available,
        holds: [],
        active_authority?: true
      },
      %{
        id: "expired-log",
        retention_class: :ephemeral,
        availability: :available,
        holds: [],
        active_authority?: false
      },
      %{
        id: "legal-hold",
        retention_class: :ephemeral,
        availability: :available,
        holds: [:legal],
        active_authority?: false
      }
    ]

    plan = Retention.gc_plan(artifacts, mode: :dry_run)

    assert Enum.map(plan.erase, & &1.id) == ["expired-log"]
    assert Enum.map(plan.keep, & &1.id) == ["active-approval", "legal-hold"]
    assert [%{id: "expired-log", availability: :erased, tombstone?: true}] = plan.tombstones
  end

  test "redaction scan runs before sealing reusable recordings" do
    assert {:ok, sealed} = SealedRecorder.seal("token=sk-SECRETSECRET", policy: :redact)
    refute sealed.content =~ "sk-SECRETSECRET"
    assert sealed.sensitivity == :redacted

    assert {:error, blocked} = SealedRecorder.seal("AWS_SECRET=abc123", policy: :block)
    assert blocked.blocked?
  end

  test "emergency stop blocks new effects and requires human decision to clear" do
    engaged =
      EmergencyStop.engage(:project, "project-1",
        actor: "operator",
        reason: "runaway",
        trace_id: "trace-stop"
      )

    assert EmergencyStop.blocks?(engaged, :effect)
    assert EmergencyStop.blocks?(engaged, :budget_reservation)

    assert_raise ArgumentError, ~r/HumanDecision/, fn ->
      EmergencyStop.clear(engaged, actor: "operator")
    end

    assert %{status: :clear} =
             EmergencyStop.clear(engaged, actor: "operator", human_decision_id: "hd-1")
  end

  test "budget reservations are required before spend and rolling circuits stop runaway graphs" do
    envelope =
      BudgetReservations.envelope(
        scope_id: "project-1",
        token_limit: 100,
        cost_limit: 10.0,
        concurrency_limit: 1
      )

    assert {:ok, reservation} =
             BudgetReservations.reserve(envelope, %{tokens: 50, cost: 4.0},
               trace_id: "trace-budget"
             )

    assert {:ok, committed} = BudgetReservations.commit(reservation, %{tokens: 45, cost: 3.5})
    assert committed.status == :committed

    assert {:deny, :reservation_required} = BudgetReservations.before_spend(nil)
    assert {:deny, :token_limit} = BudgetReservations.reserve(envelope, %{tokens: 101, cost: 1.0})

    assert {:deny, :concurrency_limit} =
             BudgetReservations.reserve(%{envelope | active_reservations: 1}, %{
               tokens: 1,
               cost: 1.0
             })
  end

  test "adapter health opens on protocol failures but not coding quality misses" do
    closed = AdapterHealth.new("provider-x")

    assert %{state: :closed} = AdapterHealth.record_failure(closed, :coding_quality_miss)

    opened =
      closed
      |> AdapterHealth.record_failure(:transport_failure)
      |> AdapterHealth.record_failure(:capability_drift)

    assert opened.state == :open
    assert AdapterHealth.admission_permit_status(opened) == :denied

    assert %{state: :half_open} = AdapterHealth.ready_to_probe(opened)
  end

  test "control-plane canary suite names all required canaries" do
    expected = [
      "gc-cannot-erase-active-authority",
      "erased-incomparable",
      "stop-blocks-new-effects",
      "reservation-required-before-spend",
      "runaway-opens-circuit",
      "adapter-health-narrows-authority"
    ]

    manifest =
      "docs/phase-1.5/p15-a4/control-plane-canaries.json"
      |> File.read!()
      |> Jason.decode!()

    assert ControlPlaneCanaries.required_keys() == expected
    assert Enum.map(manifest["canaries"], & &1["key"]) == expected
  end
end
