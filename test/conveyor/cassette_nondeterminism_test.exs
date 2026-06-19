defmodule Conveyor.CassetteNondeterminismTest do
  use ExUnit.Case, async: true

  alias Conveyor.Cassettes.Nondeterminism

  test "virtual clock and deterministic ids are reproducible from the same seed" do
    first =
      Nondeterminism.new(seed: "replay-seed", clock_start: "2026-06-19T00:00:00Z")
      |> Nondeterminism.tick(:agent_started)
      |> elem(1)
      |> Nondeterminism.allocate_id("tool")
      |> elem(1)
      |> Nondeterminism.allocate_id("tool")
      |> elem(1)

    second =
      Nondeterminism.new(seed: "replay-seed", clock_start: "2026-06-19T00:00:00Z")
      |> Nondeterminism.tick(:agent_started)
      |> elem(1)
      |> Nondeterminism.allocate_id("tool")
      |> elem(1)
      |> Nondeterminism.allocate_id("tool")
      |> elem(1)

    assert Nondeterminism.ledger(first) == Nondeterminism.ledger(second)
    assert ["tool-000001", "tool-000002"] = Enum.map(first.id_allocations, & &1.id)
  end

  test "ledger records environment, external reads, and tool-equivalence policy versions" do
    state =
      Nondeterminism.new(seed: "seed-1")
      |> Nondeterminism.record_env_read("MIX_ENV", "test")
      |> Nondeterminism.record_external_read("hex.pm/packages/jason", "etag:abc")
      |> Nondeterminism.record_tool_equivalence_policy("shell.exec", "tool-equivalence@1")

    ledger = Nondeterminism.ledger(state)

    assert ledger["schema_version"] == "conveyor.nondeterminism_ledger@1"
    assert ledger["rng_seed"] == "seed-1"
    assert [%{"key" => "MIX_ENV", "value" => "test"}] = ledger["env_reads"]

    assert [%{"subject" => "hex.pm/packages/jason", "version_ref" => "etag:abc"}] =
             ledger["external_reads"]

    assert [%{"tool_contract_key" => "shell.exec", "policy_version" => "tool-equivalence@1"}] =
             ledger["tool_equivalence_policies"]
  end

  test "incomplete required ledger returns replay_incomplete instead of success" do
    incomplete = Nondeterminism.new(seed: "seed-1") |> Nondeterminism.ledger()

    assert {:error, finding} =
             Nondeterminism.require_complete(incomplete,
               required: [:clock_reads, :rng_seed, :env_reads]
             )

    assert finding.reason == :replay_incomplete
    assert finding.missing == [:clock_reads, :env_reads]
  end
end
