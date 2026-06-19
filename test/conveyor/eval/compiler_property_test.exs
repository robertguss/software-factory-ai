defmodule Conveyor.Eval.CompilerPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Conveyor.Eval.{CompilerProperties, Schema}

  alias Conveyor.Planning.{
    CompilerStructureGate,
    GraphAnalyses,
    PassRegistry,
    StaticDecisionPackage,
    WorkGraphLowering
  }

  @moduletag :eval

  setup_all do
    {:ok, _} = Application.ensure_all_started(:jsv)
    :ok
  end

  property "every acceptance criterion retains an obligation (no silent intent loss), and the invariant bites" do
    check all(count <- integer(1..6)) do
      graph = CompilerProperties.graph_fixture(count, [])
      analysis = GraphAnalyses.run(graph)

      # Positive: a well-formed graph has no traceability gap.
      assert analysis.status == :passed
      refute Enum.any?(analysis.findings, &(&1[:rule_key] == "traceability_gap"))

      # Falsification: drop one AC's obligation -> the invariant must bite.
      broken = update_in(graph.obligations, &Enum.drop(&1, 1))

      assert Enum.any?(GraphAnalyses.run(broken).findings, fn f ->
               f[:rule_key] == "traceability_gap" and f[:subject_key] =~ "has no obligation"
             end)
    end
  end

  property "lowering is deterministic" do
    check all(count <- integer(1..6)) do
      {cand, spec} = CompilerProperties.candidate_fixture(count)
      {:ok, a} = WorkGraphLowering.lower(cand, spec)
      {:ok, b} = WorkGraphLowering.lower(cand, spec)
      assert Conveyor.CanonicalJson.digest(a) == Conveyor.CanonicalJson.digest(b)
    end
  end

  property "every generated work_graph@2 validates against its materialized schema" do
    check all(count <- integer(1..6)) do
      {cand, spec} = CompilerProperties.candidate_fixture(count)
      {:ok, graph} = WorkGraphLowering.lower(cand, spec)
      json = graph |> Jason.encode!() |> Jason.decode!()
      assert Schema.validate(json, "conveyor.work_graph@2") == :ok
    end
  end

  property "pass cache hits on identical inputs and misses on changed semantic or authority digest" do
    check all(version <- integer(1..3)) do
      registry =
        PassRegistry.new()
        |> PassRegistry.register(%{
          pass_key: "property-pass",
          version: Integer.to_string(version),
          input_stage: :plan,
          output_stage: :graph,
          selectors: ["value"],
          cache_policy: :reusable,
          authority_effect: :none,
          run: fn ctx -> PassRegistry.read!(ctx, "value") end
        })

      inputs = %{
        "value" => "stable",
        "semantic_digest" => CompilerProperties.digest("semantic"),
        "authority_digest" => CompilerProperties.digest("authority")
      }

      first = PassRegistry.run(registry, "property-pass", inputs)
      second = PassRegistry.run(first.registry, "property-pass", inputs)

      authority_changed =
        PassRegistry.run(second.registry, "property-pass", %{
          inputs
          | "authority_digest" => CompilerProperties.digest("changed-authority")
        })

      semantic_changed =
        PassRegistry.run(authority_changed.registry, "property-pass", %{
          inputs
          | "semantic_digest" => CompilerProperties.digest("changed-semantic")
        })

      assert first.cache_status == :miss
      assert second.cache_status == :hit
      assert authority_changed.cache_status == :miss
      assert semantic_changed.cache_status == :miss
    end
  end

  test "lowering/decision package never escalates authority even with injection markers in the text" do
    package = StaticDecisionPackage.build(CompilerProperties.package_input(inject: true))
    gate = CompilerStructureGate.evaluate(package, [])

    assert package.authority_effect == :none
    assert gate[:authority_effect] == :none
    assert gate[:exit_code] in [0, 2]
  end

  test "run/0 reports zero invariant violations and the schema present" do
    report = CompilerProperties.run()
    assert report["violations"] == 0, "failed checks: #{inspect(report["failed_checks"])}"
    assert report["work_graph_schema_present"] == true
  end
end
