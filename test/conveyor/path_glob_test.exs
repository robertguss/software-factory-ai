defmodule Conveyor.PathGlobTest do
  use ExUnit.Case, async: true

  alias Conveyor.PathGlob

  test "* matches within a segment but not across a slash" do
    assert PathGlob.matches?("lib/foo.ex", "lib/*.ex")
    refute PathGlob.matches?("lib/nested/foo.ex", "lib/*.ex")
  end

  test "** matches across segments" do
    assert PathGlob.matches?("lib/nested/deep/foo.ex", "lib/**")
    assert PathGlob.matches?("tests/unit/foo_test.exs", "tests/**")
  end

  test "match_any? is true iff some glob matches; empty list never matches" do
    assert PathGlob.match_any?("lib/app/foo.ex", ["config/**", "lib/app/**"])
    refute PathGlob.match_any?("lib/app/foo.ex", ["config/**", "priv/**"])
    refute PathGlob.match_any?("anything", [])
  end

  test "matches the same semantics diff_scope computes inline (regression anchor for the dedup)" do
    # mirrors lib/conveyor/gate/stages/diff_scope.ex glob_match?/2
    assert PathGlob.matches?("lib/a/b.ex", "lib/a/*.ex")
    refute PathGlob.matches?("lib/a/b/c.ex", "lib/a/*.ex")
  end
end
