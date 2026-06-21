defmodule ConveyorWeb.ParkedQueueLive do
  @moduledoc """
  The "needs-a-human" inbox (ADR-23 raw-leverage payoff): a real-time view of the
  runs that passed their gate but abstained — the only work the operator must
  triage — least-trusted first. Refreshes as runs complete (ledger events).
  """

  use ConveyorWeb, :live_view

  alias Conveyor.ParkedQueue

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Conveyor.PubSub, "ledger_events")

    {:ok,
     socket
     |> assign(:page_title, "Needs a human")
     |> assign_entries()}
  end

  @impl true
  def handle_info({:ledger_event, _message}, socket), do: {:noreply, assign_entries(socket)}
  def handle_info(_message, socket), do: {:noreply, socket}

  defp assign_entries(socket), do: assign(socket, :entries, ParkedQueue.abstained())

  @impl true
  def render(assigns) do
    ~H"""
    <h1>Needs a human <span id="parked-count">(<%= length(@entries) %>)</span></h1>

    <p :if={@entries == []} id="parked-empty">
      Nothing parked — the factory is confident in everything it shipped.
    </p>

    <ul :if={@entries != []} id="parked-queue">
      <li :for={entry <- @entries} id={"parked-#{entry.run_attempt_id}"} class="parked-entry">
        <span class="slice"><%= entry.slice_title || entry.slice_id %></span>
        <span class="band"><%= entry.band %></span>
        <span class="score"><%= format_score(entry.score) %></span>
      </li>
    </ul>
    """
  end

  defp format_score(nil), do: "—"

  defp format_score(score) when is_number(score),
    do: :erlang.float_to_binary(score / 1, decimals: 2)
end
