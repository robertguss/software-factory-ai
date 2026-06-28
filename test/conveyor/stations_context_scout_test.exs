defmodule Conveyor.StationsContextScoutTest do
  # TEST-ONLY behavioral unit test for the ContextScout station (plan unit U10).
  #
  # Output contract (happy path): run/2 returns
  #   {:ok, %{"context_pack_id" => _, "context_pack_confidence" => _}}
  # Failure mode: the underlying Conveyor.ContextScout.run!/1 raises ArgumentError
  # when the slice referenced by context.run_attempt.slice_id does not exist.
  use Conveyor.DataCase, async: false

  alias Conveyor.Factory
  alias Conveyor.Factory.ContextPack
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.Slice
  alias Conveyor.Stations.ContextScout

  test "run/2 builds a cited context pack and returns its id and confidence" do
    slice = slice!("context-scout-happy")

    # The station only reads context.run_attempt.slice_id, so a plain map satisfies the
    # context contract while the slice itself is a real persisted row.
    assert {:ok, output} = ContextScout.run(%{}, %{run_attempt: %{slice_id: slice.id}})

    assert is_binary(output["context_pack_id"])
    # confidence is rendered via Decimal.to_string/1.
    assert is_binary(output["context_pack_confidence"])

    assert [%ContextPack{id: id, slice_id: persisted_slice_id}] =
             Ash.read!(ContextPack, domain: Factory)

    assert id == output["context_pack_id"]
    assert persisted_slice_id == slice.id
  end

  test "run/2 raises ArgumentError when the slice does not exist" do
    assert_raise ArgumentError, fn ->
      ContextScout.run(%{}, %{run_attempt: %{slice_id: Ecto.UUID.generate()}})
    end
  end

  defp slice!(label) do
    project =
      Ash.create!(
        Project,
        %{
          name: "ContextScout #{label}",
          # An empty real directory: ContextScout walks local_path and simply finds no files,
          # which keeps the happy path fully hermetic (no toolchain, no git).
          local_path: temp_dir!(label),
          default_branch: "main"
        },
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "ContextScout plan",
          intent: "Exercise the context_scout station.",
          source_document: "docs/context-scout.md",
          normalized_contract: %{"schema_version" => "conveyor.plan@1"},
          contract_sha256: digest("plan")
        },
        domain: Factory
      )

    epic =
      Ash.create!(
        Epic,
        %{plan_id: plan.id, title: "ContextScout epic", description: "Context."},
        domain: Factory
      )

    Ash.create!(
      Slice,
      %{epic_id: epic.id, title: "ContextScout slice", position: 1},
      domain: Factory
    )
  end

  defp temp_dir!(label) do
    path =
      Path.join(System.tmp_dir!(), "conveyor-#{label}-#{System.unique_integer([:positive])}")

    File.mkdir_p!(path)
    path
  end

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
