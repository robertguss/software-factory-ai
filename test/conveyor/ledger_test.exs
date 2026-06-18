defmodule Conveyor.LedgerTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.Factory
  alias Conveyor.Factory.LedgerEvent
  alias Conveyor.Factory.Project
  alias Conveyor.Ledger

  setup do
    project =
      Ash.create!(
        Project,
        %{
          name: "Ledger sample",
          local_path: "/tmp/ledger-sample",
          default_branch: "main"
        },
        domain: Factory
      )

    %{project: project}
  end

  test "write is idempotent by idempotency_key", %{project: project} do
    attrs = %{
      project_id: project.id,
      idempotency_key: "ledger:#{project.id}:idempotent",
      type: "project.observed",
      payload: %{"project_id" => project.id},
      occurred_at: DateTime.utc_now(:microsecond)
    }

    first = Ledger.write!(attrs)
    second = Ledger.write!(Map.put(attrs, :payload, %{"changed" => true}))

    assert second.id == first.id
    assert second.payload == first.payload
    assert [event] = Ash.read!(LedgerEvent, domain: Factory)
    assert event.id == first.id
  end

  test "ledger events are append-only", %{project: project} do
    event =
      Ledger.write!(%{
        project_id: project.id,
        idempotency_key: "ledger:#{project.id}:append-only",
        type: "project.observed",
        payload: %{"project_id" => project.id}
      })

    assert_raise Ash.Error.Unknown, fn ->
      Ash.update!(event, %{trace_id: "changed"}, domain: Factory)
    end

    assert_raise Ash.Error.Unknown, fn ->
      Ash.destroy!(event, domain: Factory)
    end
  end

  test "tombstones carry artifact deletion provenance", %{project: project} do
    event =
      Ledger.tombstone!(%{
        project_id: project.id,
        idempotency_key: "ledger:#{project.id}:artifact-deleted",
        artifact_id: "artifact-123",
        prior_sha256: digest("artifact-123"),
        actor: "operator",
        reason: "retention policy expired"
      })

    assert event.type == "artifact.deleted"

    assert event.payload == %{
             "actor" => "operator",
             "artifact_id" => "artifact-123",
             "prior_sha256" => digest("artifact-123"),
             "reason" => "retention policy expired"
           }
  end

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
