defmodule ConveyorWeb.Live.Cockpit.GraphSerializerTest do
  use ExUnit.Case, async: true

  alias ConveyorWeb.Live.Cockpit.GraphSerializer

  # The wire shape the client renders — locked here so the U7 extraction and the
  # U8 Channel cannot drift from what CockpitLive emits today (R4/R5).
  @node_keys [:id, :label, :state, :epic_id, :title, :blocked_by, :starved_dependents]

  defp slice_node(overrides \\ %{}) do
    Map.merge(
      %{
        id: "a",
        label: "A",
        state: :running,
        epic_id: nil,
        title: "Slice A",
        blocked_by: [],
        starved_dependents: 0,
        # a model field that is NOT part of the wire shape; must be dropped.
        extra: "drop me"
      },
      overrides
    )
  end

  describe "node_payload/1" do
    test "keeps exactly the seven wire keys and drops everything else" do
      payload = GraphSerializer.node_payload(slice_node())
      assert Enum.sort(Map.keys(payload)) == Enum.sort(@node_keys)
      assert payload.title == "Slice A"
      refute Map.has_key?(payload, :extra)
    end

    test "is idempotent on an already-serialized node" do
      payload = GraphSerializer.node_payload(slice_node())
      assert GraphSerializer.node_payload(payload) == payload
    end
  end

  describe "graph_payload/1" do
    test "returns %{nodes, edges, epics} with serialized nodes, pass-through edges/epics" do
      edges = [%{from: "a", to: "b"}]
      epics = [%{id: "e1", label: "Epic"}]
      model = %{nodes: [slice_node()], edges: edges, epics: epics}

      payload = GraphSerializer.graph_payload(model)

      assert Enum.sort(Map.keys(payload)) == [:edges, :epics, :nodes]
      assert payload.edges == edges
      assert payload.epics == epics
      assert [n] = payload.nodes
      assert Enum.sort(Map.keys(n)) == Enum.sort(@node_keys)
    end
  end
end
