defmodule Conveyor.Events.DurableCatchUpTest do
  use ExUnit.Case, async: true

  alias Conveyor.Events.DurableCatchUp

  test "loads durable segment events after the last committed sequence" do
    manifest = %{
      "segments" => [
        %{
          "events" => [
            %{"sequence" => 1, "event_id" => "event-1"},
            %{"sequence" => 2, "event_id" => "event-2"}
          ]
        },
        %{
          "events" => [
            %{"sequence" => 3, "event_id" => "event-3"},
            %{"sequence" => 4, "event_id" => "event-4"}
          ]
        }
      ]
    }

    assert DurableCatchUp.replay_after(manifest, 2) == [
             %{"sequence" => 3, "event_id" => "event-3"},
             %{"sequence" => 4, "event_id" => "event-4"}
           ]
  end

  test "ignores duplicate and out-of-order live messages by sequence" do
    state = DurableCatchUp.new(last_sequence: 3)

    assert {:ignore, state} = DurableCatchUp.accept_live(state, %{"sequence" => 3})
    assert {:ignore, state} = DurableCatchUp.accept_live(state, %{"sequence" => 2})

    assert {:ok, state, %{"sequence" => 4}} =
             DurableCatchUp.accept_live(state, %{"sequence" => 4})

    assert {:ignore, ^state} = DurableCatchUp.accept_live(state, %{"sequence" => 4})

    assert {:ok, _state, %{"sequence" => 5}} =
             DurableCatchUp.accept_live(state, %{"sequence" => 5})
  end
end
