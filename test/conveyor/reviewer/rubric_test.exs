defmodule Conveyor.Reviewer.RubricTest do
  @moduledoc "m4b2.3: the versioned, hashed reviewer rubric + rendered prompt."
  use ExUnit.Case, async: true

  alias Conveyor.Reviewer.Rubric

  test "load returns the versioned checklist with a stable content hash" do
    rubric = Rubric.load("reviewer@1")

    assert rubric["version"] == "reviewer@1"
    assert rubric["stance"] == "adversarial"
    assert length(rubric["checklist"]) == 5
    assert String.starts_with?(rubric["sha256"], "sha256:")
    # deterministic: same artifact -> same hash across loads.
    assert rubric["sha256"] == Rubric.load("reviewer@1")["sha256"]
    assert Rubric.sha256("reviewer@1") == rubric["sha256"]
  end

  test "the rubric forces rejection on gaming/scope items and only advises on seam robustness" do
    rubric = Rubric.load("reviewer@1")
    by_id = Map.new(rubric["checklist"], &{&1["id"], &1["forces"]})

    assert by_id["contract_conformance"] == "rejected"
    assert by_id["test_gaming"] == "rejected"
    assert by_id["seam_robustness"] == "needs_rework"
  end

  test "render_prompt banners trusted vs untrusted sections and states the schema + stance" do
    rubric = Rubric.load("reviewer@1")

    prompt =
      Rubric.render_prompt(rubric, %{
        desired_behavior: "List ready issues sorted by id.",
        acceptance_criteria: [%{"key" => "AC-001", "text" => "prints unblocked issues"}],
        diff: "diff --git a/x b/x",
        excerpts: "some repo excerpt"
      })

    # trusted sections
    assert prompt =~ "Trusted: Slice contract"
    assert prompt =~ "List ready issues sorted by id."
    assert prompt =~ "Trusted: Rubric reviewer@1 (#{rubric["sha256"]})"
    assert prompt =~ "[contract_conformance]"
    # untrusted banner precedes the diff
    assert prompt =~ "UNTRUSTED context"
    assert :binary.match(prompt, "UNTRUSTED context") < :binary.match(prompt, "diff --git a/x")
    # stance + output schema instructions
    assert prompt =~ "ADVERSARIAL"
    assert prompt =~ "Uncertainty => needs_rework"
    assert prompt =~ "conveyor.review@1"
    # deterministic
    assert prompt ==
             Rubric.render_prompt(rubric, %{
               desired_behavior: "List ready issues sorted by id.",
               acceptance_criteria: [%{"key" => "AC-001", "text" => "prints unblocked issues"}],
               diff: "diff --git a/x b/x",
               excerpts: "some repo excerpt"
             })
  end
end
