defmodule Conveyor.PlanningPassDiagnosticsTest do
  use ExUnit.Case, async: true

  alias Conveyor.Planning.PassDiagnostics

  test "emits deterministic diagnostics while preserving reusable valid fragments" do
    fragments = [
      fragment("SLC-A", %{title: "Valid A"}),
      fragment("SLC-B", %{title: "Broken", malformed?: true}),
      fragment("SLC-C", %{title: "Valid C"})
    ]

    result =
      PassDiagnostics.run_fragments("lower_work_graph", fragments, fn fragment ->
        if Map.get(fragment.payload, :malformed?, false) do
          {:error, "missing interface binding"}
        else
          {:ok, %{stable_key: fragment.fragment_key, title: fragment.payload.title}}
        end
      end)

    assert result.status == :partial
    assert result.pass_key == "lower_work_graph"
    assert result.authority_effect == :partial_no_execution_authority

    assert result.diagnostics == [
             %{
               pass_key: "lower_work_graph",
               fragment_key: "SLC-B",
               severity: :error,
               reason: :fragment_failed,
               message: "missing interface binding",
               deterministic?: true
             }
           ]

    assert Enum.map(result.partial_artifacts, & &1.fragment_key) == ["SLC-A", "SLC-C"]
    assert Enum.all?(result.partial_artifacts, &(&1.reusable? == true))
    assert Enum.all?(result.partial_artifacts, &(&1.artifact_digest =~ ~r/^sha256:[0-9a-f]{64}$/))
    assert Enum.all?(result.partial_artifacts, &(&1.reuse_key =~ ~r/^sha256:[0-9a-f]{64}$/))
    assert Enum.map(result.partial_artifacts, & &1.output.title) == ["Valid A", "Valid C"]
  end

  test "complete fragment runs carry no diagnostics and keep reusable artifacts" do
    result =
      PassDiagnostics.run_fragments("identity", [fragment("SLC-A", %{title: "Valid"})], fn fragment ->
        {:ok, %{stable_key: fragment.fragment_key, title: fragment.payload.title}}
      end)

    assert result.status == :complete
    assert result.diagnostics == []
    assert [%{fragment_key: "SLC-A", reusable?: true}] = result.partial_artifacts
  end

  defp fragment(key, payload) do
    %{
      fragment_key: key,
      payload: payload,
      semantic_digest: digest(key)
    }
  end

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
