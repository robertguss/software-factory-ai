defmodule Conveyor.Recovery.ScopeAmendmentEvaluatorTest do
  @moduledoc """
  nyrl.2 authority core: the deterministic evaluator that grants or denies a scope amendment. The
  agent can only REQUEST (supply offending paths + a rationale); the policy decides. No input the
  agent controls can move a path from protected to allowed (the untrusted-input authority rule).
  """
  use ExUnit.Case, async: true

  alias Conveyor.Recovery.ScopeAmendmentEvaluator, as: Evaluator

  # A request within every bound: two eligible, non-protected extra files under the cap.
  defp request(overrides \\ %{}) do
    Map.merge(
      %{
        offending_paths: ["lib/app/foo.ex"],
        allowed_path_globs: ["lib/app/bar.ex"],
        protected_path_globs: ["tests/**", ".conveyor/**"],
        allowlist_globs: ["lib/app/**"],
        max_extra_files: 2,
        rationale: "barrel export needed by the new module"
      },
      overrides
    )
  end

  describe "grant (within all bounds)" do
    test "widens allowed_path_globs with the offending paths and echoes the rationale" do
      assert {:grant, grant} = Evaluator.evaluate(request())
      assert grant.added_globs == ["lib/app/foo.ex"]
      # widened scope = existing allow-list plus the granted paths (deduped, order-stable)
      assert grant.allowed_path_globs == ["lib/app/bar.ex", "lib/app/foo.ex"]
      assert grant.rationale == "barrel export needed by the new module"
    end

    test "a path already in the allow-list is not double-added (idempotent widen)" do
      req =
        request(%{offending_paths: ["lib/app/bar.ex"], allowed_path_globs: ["lib/app/bar.ex"]})

      assert {:grant, grant} = Evaluator.evaluate(req)
      assert grant.allowed_path_globs == ["lib/app/bar.ex"]
    end
  end

  describe "deny — protected precedence (the untrusted-input rule)" do
    test "a protected path is never granted even if it is on the allowlist and under the cap" do
      req =
        request(%{
          offending_paths: ["tests/foo_test.exs"],
          allowlist_globs: ["tests/**", "lib/app/**"]
        })

      assert {:deny, denial} = Evaluator.evaluate(req)
      assert denial.park_reason == :scope_denied
      assert denial.violated_bound == :protected_path
      assert denial.offending == ["tests/foo_test.exs"]
    end

    test "protected wins when a request mixes protected and eligible paths" do
      req =
        request(%{
          offending_paths: ["lib/app/foo.ex", "tests/foo_test.exs"],
          allowlist_globs: ["lib/app/**", "tests/**"],
          max_extra_files: 5
        })

      assert {:deny, denial} = Evaluator.evaluate(req)
      assert denial.violated_bound == :protected_path
      assert denial.offending == ["tests/foo_test.exs"]
    end
  end

  describe "deny — allowlist eligibility" do
    test "a path outside the per-profile allowlist is denied" do
      req = request(%{offending_paths: ["config/runtime.exs"], allowlist_globs: ["lib/app/**"]})
      assert {:deny, denial} = Evaluator.evaluate(req)
      assert denial.violated_bound == :not_on_allowlist
      assert denial.offending == ["config/runtime.exs"]
    end

    test "an empty allowlist fails closed — nothing is eligible for grant" do
      req = request(%{allowlist_globs: []})
      assert {:deny, denial} = Evaluator.evaluate(req)
      assert denial.violated_bound == :not_on_allowlist
    end
  end

  describe "deny — extra-file cap" do
    test "more offending files than the cap is denied even when all are eligible" do
      req =
        request(%{
          offending_paths: ["lib/app/a.ex", "lib/app/b.ex", "lib/app/c.ex"],
          max_extra_files: 2
        })

      assert {:deny, denial} = Evaluator.evaluate(req)
      assert denial.violated_bound == :extra_file_cap
      assert denial.detail =~ "3"
      assert denial.detail =~ "2"
    end
  end

  describe "edges" do
    test "no offending paths is a trivial grant that widens nothing" do
      assert {:grant, grant} = Evaluator.evaluate(request(%{offending_paths: []}))
      assert grant.added_globs == []
    end

    test "a nil rationale still evaluates (rationale is audit metadata, not an authority input)" do
      assert {:grant, grant} = Evaluator.evaluate(request(%{rationale: nil}))
      assert grant.rationale == nil
    end
  end
end
