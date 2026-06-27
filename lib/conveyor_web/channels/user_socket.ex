defmodule ConveyorWeb.UserSocket do
  @moduledoc """
  The cockpit's realtime socket. Carries the observe-only `cockpit:<run_id>`
  channel that replaces the LiveView `push_event` transport (R5).
  """
  use Phoenix.Socket

  channel "cockpit:*", ConveyorWeb.CockpitChannel

  # Internal-only cockpit (KTD10): the socket is unauthenticated by design. The
  # trust boundary is the deployment — Conveyor runs on an operator-only network
  # — so authorization is documented here, not enforced in code. Every
  # connection is accepted. Revisit (a signed token in `connect/3`) before this
  # is ever exposed beyond that boundary.
  @impl true
  def connect(_params, socket, _connect_info), do: {:ok, socket}

  # Anonymous socket — no per-user identity to track or disconnect by.
  @impl true
  def id(_socket), do: nil
end
