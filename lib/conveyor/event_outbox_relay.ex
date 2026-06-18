defmodule Conveyor.EventOutboxRelay do
  @moduledoc """
  Publishes committed ledger events from the transactional outbox.
  """

  alias Conveyor.Factory
  alias Conveyor.Factory.EventOutbox

  @spec publish_pending!(keyword()) :: [struct()]
  def publish_pending!(opts \\ []) do
    pubsub = Keyword.get(opts, :pubsub, Conveyor.PubSub)

    EventOutbox
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.status == :pending))
    |> Enum.sort_by(&DateTime.to_unix(&1.inserted_at, :microsecond))
    |> Enum.map(&publish_one!(&1, pubsub))
  end

  defp publish_one!(outbox, pubsub) do
    Phoenix.PubSub.broadcast(pubsub, outbox.topic, {:ledger_event, outbox.message})

    Ash.update!(
      outbox,
      %{
        status: :published,
        attempts: outbox.attempts + 1,
        published_at: DateTime.utc_now(:microsecond)
      },
      domain: Factory
    )
  end
end
