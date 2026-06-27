defmodule ConveyorWeb.Live.Cockpit.GraphSerializer do
  @moduledoc """
  Shapes the cockpit wire payloads — `graph:init` (full snapshot) and the node
  rows in `node:patch` deltas — from a `GraphProjection` model.

  Originally lifted from the cockpit's first LiveView transport (since retired at
  the /runs cutover) so every reader shares one serializer and stays byte-for-byte
  identical. `GraphProjection.build/2` / `recompute_slice/3` remain the model
  source.
  """

  # Exactly the fields the client renders. Anything else on a model node (run
  # bookkeeping, computed reasons) stays server-side.
  @node_keys [:id, :label, :state, :epic_id, :title, :blocked_by, :starved_dependents]

  @doc """
  The `graph:init` snapshot: serialized nodes plus pass-through edges and epics.
  """
  def graph_payload(model) do
    %{
      nodes: Enum.map(model.nodes, &node_payload/1),
      edges: model.edges,
      epics: model.epics
    }
  end

  @doc "The wire shape for a single node — the fields the client renders."
  def node_payload(node), do: Map.take(node, @node_keys)
end
