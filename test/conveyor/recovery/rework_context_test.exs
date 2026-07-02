defmodule Conveyor.Recovery.ReworkContextTest do
  @moduledoc "rt6k.2: bounded, redacted failing-test excerpt + prior-diff summary."
  use ExUnit.Case, async: true

  alias Conveyor.Recovery.ReworkContext

  defp vr(tests, stdout \\ "") do
    %{"suites" => [%{"commands" => [%{"stdout" => stdout, "attempts" => [%{"tests" => tests}]}]}]}
  end

  @tests [
    %{"id" => "test_b", "status" => "failed", "message" => "expected 1 got 2"},
    %{"id" => "test_a", "status" => "failed", "message" => "boom in a"},
    %{"id" => "test_c", "status" => "passed", "message" => "ok"}
  ]

  test "excerpt selects only failing tests, sorted by id" do
    {excerpt, meta} = ReworkContext.failing_test_excerpt(vr(@tests))

    assert excerpt =~ "test_a"
    assert excerpt =~ "boom in a"
    assert excerpt =~ "test_b"
    refute excerpt =~ "test_c"
    # deterministic order: a before b
    assert :binary.match(excerpt, "test_a") < :binary.match(excerpt, "test_b")
    assert meta["bytes"] == byte_size(excerpt)
    refute meta["truncated"]
  end

  test "truncation is deterministic, marked, and within the byte budget" do
    {excerpt, meta} = ReworkContext.failing_test_excerpt(vr(@tests), test_excerpt_bytes: 60)
    {again, _} = ReworkContext.failing_test_excerpt(vr(@tests), test_excerpt_bytes: 60)

    assert meta["truncated"]
    assert byte_size(excerpt) <= 60
    assert excerpt =~ "[truncated]"
    assert excerpt == again
  end

  test "a planted secret never reaches the excerpt (redactor applied)" do
    secret = "sk-abcdef0123456789ghij"
    tests = [%{"id" => "t", "status" => "failed", "message" => "auth failed with #{secret}"}]

    {excerpt, meta} = ReworkContext.failing_test_excerpt(vr(tests))

    refute excerpt =~ secret
    assert meta["redacted"]
  end

  test "pathological huge failure output stays within budget" do
    huge = String.duplicate("x", 500_000)
    tests = [%{"id" => "t", "status" => "failed", "message" => huge}]

    {excerpt, meta} = ReworkContext.failing_test_excerpt(vr(tests, huge))

    assert byte_size(excerpt) <= 6144
    assert meta["truncated"]
    assert String.valid?(excerpt)
  end

  test "prior-diff summary lists changed files sorted by path" do
    {summary, _meta} = ReworkContext.prior_diff_summary(["b/two.ex", "a/one.ex"])

    assert summary =~ "Changed files (2)"
    assert :binary.match(summary, "a/one.ex") < :binary.match(summary, "b/two.ex")
  end

  test "prior-diff summary renders per-file stats when present" do
    {summary, _meta} =
      ReworkContext.prior_diff_summary([%{"path" => "a.ex", "additions" => 10, "deletions" => 2}])

    assert summary =~ "a.ex (+10 -2)"
  end

  test "build assembles both artifacts from a slice output map" do
    output = %{"verification_result" => vr(@tests), "changed_files" => ["lib/x.ex"]}
    result = ReworkContext.build(output)

    assert result["failing_test_excerpt"] =~ "test_a"
    assert result["prior_diff_summary"] =~ "lib/x.ex"
    assert result["meta"]["test_excerpt"]["bytes"] > 0
  end

  test "build tolerates a missing/empty output" do
    assert ReworkContext.build(nil) == %{
             "failing_test_excerpt" => "",
             "prior_diff_summary" => "",
             "meta" => %{}
           }
  end
end
