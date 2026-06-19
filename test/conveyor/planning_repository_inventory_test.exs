defmodule Conveyor.PlanningRepositoryInventoryTest do
  use ExUnit.Case, async: true

  alias Conveyor.Planning.RepositoryInventory

  test "builds deterministic content-addressed inventory reusable for matching inputs only" do
    files = [
      %{path: "lib/tasks.ex", content: "defmodule Tasks do\nend\n"},
      %{path: "mix.exs", content: "defmodule MixProject do\nend\n"}
    ]

    opts = [
      repo_base_ref: "abc123",
      extractor_versions: %{
        manifest: "manifest@1",
        rg: "rg@14",
        route: "phoenix-routes@1",
        schema: "json-schema@2020-12",
        tree_sitter: "elixir@1",
        lsp: "elixir-ls@1"
      },
      policy_digest: digest("policy")
    ]

    first = RepositoryInventory.build(files, opts)
    second = RepositoryInventory.build(Enum.reverse(files), opts)

    assert first.inventory_digest == second.inventory_digest
    assert Enum.map(first.files, & &1.path) == ["lib/tasks.ex", "mix.exs"]
    assert Enum.all?(first.files, &(&1.content_digest =~ ~r/^sha256:[0-9a-f]{64}$/))
    assert first.authority_effect == :none
    assert first.changes_question_authority? == false
    assert RepositoryInventory.reusable?(first, opts)
    refute RepositoryInventory.reusable?(first, Keyword.put(opts, :repo_base_ref, "def456"))
  end

  test "records deterministic extractor outputs and failures without authority impact" do
    inventory =
      RepositoryInventory.build([],
        repo_base_ref: "abc123",
        extractor_versions: %{manifest: "manifest@1", rg: "rg@14", lsp: "elixir-ls@1"},
        policy_digest: digest("policy"),
        extractor_outputs: [
          %{key: :rg, status: :ok, output: ["defmodule Tasks"]},
          %{key: :lsp, status: :failed, error: "server unavailable"},
          %{key: :manifest, status: :ok, output: ["mix.exs"]}
        ]
      )

    assert Enum.map(inventory.extractors, & &1.key) == ["lsp", "manifest", "rg"]
    assert Enum.find(inventory.extractors, &(&1.key == "lsp")).status == :failed
    assert Enum.all?(inventory.extractors, &(&1.output_digest =~ ~r/^sha256:[0-9a-f]{64}$/))
    assert inventory.authority_effect == :none
    assert inventory.changes_question_authority? == false
  end

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
