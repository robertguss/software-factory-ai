defmodule Conveyor.NegotiatedScope.ScopeAmendmentTest do
  @moduledoc """
  nyrl.2 grant execution: minting a widened DiffPolicy version + the audit trail. Pins the two
  design-law acceptance items — lock/policy-version digests CHAIN (a widened version has a different
  digest), and the prior version is NEVER mutated in place (a new row is minted, the old row stands).
  """
  use Conveyor.DataCase, async: false

  alias Conveyor.Factory
  alias Conveyor.Factory.DiffPolicy
  alias Conveyor.Factory.LedgerEvent
  alias Conveyor.Factory.Slice
  alias Conveyor.FactoryFixtures
  alias Conveyor.NegotiatedScope.ScopeAmendment
  alias Conveyor.Planning.RunSpecAssembler

  defp setup_prior_policy do
    %{slices: [slice], run_attempts: run_attempts} =
      FactoryFixtures.create_run_with_ledger!(
        terminal: :none,
        slices: [%{status: "parked"}]
      )

    prior =
      Ash.create!(
        DiffPolicy,
        %{
          slice_id: slice.id,
          allowed_path_globs: ["lib/app/bar.ex"],
          protected_path_globs: ["tests/**"],
          max_files_changed: 5,
          notes: "prior"
        },
        domain: Factory
      )

    Ash.update!(slice, %{diff_policy_id: prior.id, likely_files: ["lib/app/bar.ex"]},
      domain: Factory
    )

    [attempt] = Map.fetch!(run_attempts, slice.id)
    %{slice: slice, prior: prior, attempt: attempt}
  end

  describe "mint_widened_policy!/2" do
    test "mints a NEW row with the widened allow-list and a recomputed file cap" do
      %{prior: prior} = setup_prior_policy()

      new = ScopeAmendment.mint_widened_policy!(prior, ["lib/app/bar.ex", "lib/app/foo.ex"])

      assert new.id != prior.id
      assert new.allowed_path_globs == ["lib/app/bar.ex", "lib/app/foo.ex"]
      # cap is derived from the widened count, not copied
      assert new.max_files_changed != prior.max_files_changed
      # protected set is carried through untouched — a widen never relaxes protection
      assert new.protected_path_globs == ["tests/**"]
    end

    test "design-law: the prior policy row is never mutated in place" do
      %{prior: prior} = setup_prior_policy()
      _new = ScopeAmendment.mint_widened_policy!(prior, ["lib/app/bar.ex", "lib/app/foo.ex"])

      reloaded = Ash.get!(DiffPolicy, prior.id, domain: Factory)
      assert reloaded.allowed_path_globs == ["lib/app/bar.ex"]
      assert reloaded.notes == "prior"
    end

    test "chaining: the widened version's digest differs from its predecessor" do
      %{prior: prior} = setup_prior_policy()
      new = ScopeAmendment.mint_widened_policy!(prior, ["lib/app/bar.ex", "lib/app/foo.ex"])

      assert RunSpecAssembler.diff_policy_sha256(new) !=
               RunSpecAssembler.diff_policy_sha256(prior)
    end
  end

  describe "apply_grant!/4" do
    test "moves the slice scope pointers to the widened version and records the trail" do
      %{slice: slice, prior: prior, attempt: attempt} = setup_prior_policy()

      grant = %{
        allowed_path_globs: ["lib/app/bar.ex", "lib/app/foo.ex"],
        added_globs: ["lib/app/foo.ex"],
        rationale: "foo is a required barrel export"
      }

      amended_sha = ScopeAmendment.apply_grant!(attempt, prior, grant, actor: "tester")

      # slice now points at the widened policy + likely_files grew
      reloaded_slice = Ash.get!(Slice, slice.id, domain: Factory)
      assert reloaded_slice.diff_policy_id != prior.id
      assert "lib/app/foo.ex" in reloaded_slice.likely_files

      widened = Ash.get!(DiffPolicy, reloaded_slice.diff_policy_id, domain: Factory)
      assert RunSpecAssembler.diff_policy_sha256(widened) == amended_sha

      # auditable trail: the sha chain + granted paths + rationale
      [event] =
        LedgerEvent
        |> Ash.read!(domain: Factory)
        |> Enum.filter(&(&1.type == "scope.amendment_granted"))

      assert event.payload["granted_paths"] == ["lib/app/foo.ex"]
      assert event.payload["rationale"] == "foo is a required barrel export"

      assert event.payload["prior_diff_policy_sha256"] !=
               event.payload["amended_diff_policy_sha256"]
    end
  end
end
