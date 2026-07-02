defmodule Conveyor.ContextScout.DeepeningConsolidatedTest do
  @moduledoc """
  aabq.3: the consolidated test surface for the ContextScout deepening (aabq.1 excerpts + aabq.2
  language-neutral signatures). These assert the deepening through the WHOLE path the agent sees —
  scout -> ContextPack -> PromptBuilder -> rendered prompt body — not just the ContextPack in
  isolation (the per-component tests in context_scout_test.exs already cover that layer).

  Coverage: per-language signatures reach the prompt; the prompt digest is replayable; a planted
  secret never reaches the prompt; a tiny-greenfield repo degrades cleanly to a path-only pack; the
  scout emits a per-slice observability line.

  Measurement hook (honest, not run here): the eval-corpus first-attempt gate-pass-rate before/after
  is a LIVE-agent measurement (needs real runs against the eval corpus), which this environment
  cannot execute. It belongs to the eval harness (EVAL-* beads); no target is enforced, per the
  project's honesty conventions.
  """
  use Conveyor.DataCase, async: false

  import ExUnit.CaptureLog

  alias Conveyor.ContextScout
  alias Conveyor.Factory
  alias Conveyor.Factory.AgentBrief
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.Slice
  alias Conveyor.PromptBuilder

  @languages [
    %{
      lang: "elixir",
      file: "lib/math.ex",
      body:
        "defmodule Math do\n  @spec add(integer, integer) :: integer\n  def add(a, b), do: a + b\nend\n",
      signature: "def add"
    },
    %{
      lang: "javascript",
      file: "server.js",
      body: "export function handler(req) {\n  return req\n}\n",
      signature: "export function handler"
    },
    %{
      lang: "python",
      file: "app.py",
      body: "def handler(req):\n    return req\n",
      signature: "def handler"
    }
  ]

  for %{lang: lang} = fixture <- @languages do
    @fixture fixture
    test "the #{lang} interface signature reaches the rendered prompt (aabq.1/aabq.2 e2e)" do
      slice = fixture_slice!(@fixture.file, @fixture.body)
      pack = ContextScout.run!(slice)
      prompt = PromptBuilder.build!(slice, context_pack: pack)

      assert prompt.body =~ @fixture.signature,
             "#{@fixture.lang}: expected signature #{inspect(@fixture.signature)} in the prompt body"
    end
  end

  test "the same tree yields a byte-identical prompt digest twice (replayable)" do
    slice = fixture_slice!("lib/math.ex", "defmodule Math do\n  def add(a, b), do: a + b\nend\n")

    first = PromptBuilder.build!(slice, context_pack: ContextScout.run!(slice))
    second = PromptBuilder.build!(slice, context_pack: ContextScout.run!(slice))

    assert first.body_sha256 == second.body_sha256
  end

  test "a planted secret never reaches the rendered prompt" do
    slice =
      fixture_slice!(
        "svc/app.py",
        "SECRET = \"AKIAIOSFODNN7EXAMPLE\"\ndef run():\n    return 1\n"
      )

    prompt = PromptBuilder.build!(slice, context_pack: ContextScout.run!(slice))

    refute prompt.body =~ "AKIAIOSFODNN7EXAMPLE"
  end

  test "a tiny-greenfield repo (no source files) degrades to a path-only pack, prompt still builds" do
    root = tmp_root!()
    File.write!(Path.join(root, "README.md"), "# hello\n")
    slice = project_slice!(root, [])
    brief!(slice)

    pack = ContextScout.run!(slice)
    prompt = PromptBuilder.build!(slice, context_pack: pack)

    assert pack.file_excerpts == []
    assert is_binary(prompt.body) and prompt.body != ""
    assert prompt.body =~ "File excerpts:"
  end

  test "the scout emits a per-slice observability line (files/bytes/truncations)" do
    slice = fixture_slice!("lib/math.ex", "defmodule Math do\n  def add(a, b), do: a + b\nend\n")

    prev = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: prev) end)

    log = capture_log(fn -> ContextScout.run!(slice) end)

    assert log =~ "context_scout: slice=#{slice.id}"
    assert log =~ "files_selected="
    assert log =~ "excerpt_bytes="
    assert log =~ "truncations="
  end

  # --- fixtures --------------------------------------------------------------

  defp fixture_slice!(rel_path, contents) do
    root = tmp_root!()
    File.mkdir_p!(Path.dirname(Path.join(root, rel_path)))
    File.write!(Path.join(root, rel_path), contents)
    slice = project_slice!(root, [rel_path])
    brief!(slice)
    slice
  end

  defp tmp_root! do
    root = Path.join(System.tmp_dir!(), "scout-aabq3-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    root
  end

  defp brief!(slice) do
    Ash.create!(
      AgentBrief,
      %{
        slice_id: slice.id,
        version: 1,
        current_behavior: "none",
        desired_behavior: "implement",
        key_interfaces: [],
        out_of_scope: [],
        risk: "medium",
        acceptance_criteria: [],
        required_tests: [],
        verification_commands: [],
        non_goals: [],
        locked_at: DateTime.utc_now(:microsecond),
        locked_by: "planner",
        contract_sha256: "sha256:brief-#{System.unique_integer([:positive])}"
      },
      domain: Factory
    )
  end

  defp project_slice!(root, likely_files) do
    project =
      Ash.create!(
        Project,
        %{
          name: "scout-aabq3-#{System.unique_integer([:positive])}",
          local_path: root,
          default_branch: "main",
          default_autonomy_level: 2
        },
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "scout aabq3",
          intent: "scout",
          source_document: "t",
          normalized_contract: %{"goal" => "t"},
          contract_sha256: "sha256:t",
          status: :handoff_ready
        },
        domain: Factory
      )

    epic = Ash.create!(Epic, %{plan_id: plan.id, title: "e", description: "d"}, domain: Factory)

    Ash.create!(
      Slice,
      %{
        epic_id: epic.id,
        title: "s",
        position: 1,
        risk: "medium",
        autonomy_level: "L2",
        source_refs: [],
        likely_files: likely_files,
        conflict_domains: []
      },
      domain: Factory
    )
  end
end
