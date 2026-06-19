defmodule Conveyor.CassetteFreshnessTest do
  use ExUnit.Case, async: true

  alias Conveyor.Cassettes.Freshness

  @surface %{
    prompt_digest: "sha256:prompt",
    role_view_digest: "sha256:role",
    context_pack_digest: "sha256:context",
    adapter_profile_digest: "sha256:adapter",
    tool_contract_digest: "sha256:tool",
    gate_digest: "sha256:gate-old",
    verification_digest: "sha256:test-old",
    obligation_digest: "sha256:obligation-old"
  }

  test "generation digest ignores evaluation-only gate and test changes" do
    old = Freshness.surface_digests(@surface)

    new =
      @surface
      |> Map.put(:gate_digest, "sha256:gate-new")
      |> Map.put(:verification_digest, "sha256:test-new")
      |> Freshness.surface_digests()

    assert old.generation_freshness_digest == new.generation_freshness_digest
    assert old.evaluation_surface_digest != new.evaluation_surface_digest

    assert Freshness.classify(old, new) == :hybrid_replay_eligible
  end

  test "generation-surface changes make every replay mode miss" do
    old = Freshness.surface_digests(@surface)
    new = Freshness.surface_digests(%{@surface | context_pack_digest: "sha256:context-new"})

    assert old.generation_freshness_digest != new.generation_freshness_digest
    assert Freshness.classify(old, new) == :generation_stale
  end

  test "identical generation and evaluation surfaces are fresh" do
    digests = Freshness.surface_digests(@surface)

    assert Freshness.classify(digests, digests) == :fresh
    assert digests.generation_freshness_digest =~ ~r/^sha256:[0-9a-f]{64}$/
    assert digests.evaluation_surface_digest =~ ~r/^sha256:[0-9a-f]{64}$/
  end
end
