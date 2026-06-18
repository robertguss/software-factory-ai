defmodule Conveyor.EventOutboxRelayTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.EventOutboxRelay
  alias Conveyor.Factory
  alias Conveyor.Factory.EventOutbox
  alias Conveyor.Factory.Project
  alias Conveyor.Ledger
  alias Conveyor.Repo

  setup do
    project =
      Ash.create!(
        Project,
        %{
          name: "Outbox sample",
          local_path: "/tmp/outbox-sample",
          default_branch: "main"
        },
        domain: Factory
      )

    Phoenix.PubSub.subscribe(Conveyor.PubSub, "ledger_events")

    %{project: project}
  end

  test "committed ledger events are published exactly once", %{project: project} do
    event =
      Ledger.write!(%{
        project_id: project.id,
        idempotency_key: "ledger:#{project.id}:committed",
        type: "project.observed",
        payload: %{"project_id" => project.id}
      })

    assert [pending] = outbox_rows()
    assert pending.status == :pending

    assert [published] = EventOutboxRelay.publish_pending!()
    assert published.status == :published
    assert published.attempts == 1

    assert_receive {:ledger_event, %{"ledger_event_id" => ledger_event_id}}
    assert ledger_event_id == event.id

    assert [] = EventOutboxRelay.publish_pending!()
    refute_receive {:ledger_event, _message}, 50
  end

  test "rolled back ledger writes publish nothing", %{project: project} do
    assert {:error, :rollback_for_test} =
             Repo.transaction(fn ->
               Ledger.write!(
                 %{
                   project_id: project.id,
                   idempotency_key: "ledger:#{project.id}:rolled-back",
                   type: "project.observed",
                   payload: %{"project_id" => project.id}
                 },
                 return_notifications?: true
               )

               Repo.rollback(:rollback_for_test)
             end)

    assert [] = outbox_rows()
    assert [] = EventOutboxRelay.publish_pending!()
    refute_receive {:ledger_event, _message}, 50
  end

  test "duplicate idempotency keys do not enqueue duplicate outbox rows", %{project: project} do
    attrs = %{
      project_id: project.id,
      idempotency_key: "ledger:#{project.id}:duplicate-outbox",
      type: "project.observed",
      payload: %{"project_id" => project.id}
    }

    first = Ledger.write!(attrs)
    second = Ledger.write!(Map.put(attrs, :payload, %{"changed" => true}))

    assert second.id == first.id
    assert [outbox] = outbox_rows()
    assert outbox.ledger_event_id == first.id
  end

  defp outbox_rows do
    Ash.read!(EventOutbox, domain: Factory)
  end
end
