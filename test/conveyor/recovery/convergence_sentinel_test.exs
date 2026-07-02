defmodule Conveyor.Recovery.ConvergenceSentinelTest do
  @moduledoc "rt6k.3: convergence sentinel decision."
  use ExUnit.Case, async: true

  alias Conveyor.Recovery.ConvergenceSentinel

  test "empty diff parks with no_progress (even on the first attempt, no prior fingerprint)" do
    assert ConvergenceSentinel.decide(%{
             diff_empty?: true,
             prev_fingerprint: nil,
             current_fingerprint: "sha256:a"
           }) ==
             {:park, "no_progress"}
  end

  test "the same fingerprint twice parks with convergence_stall" do
    assert ConvergenceSentinel.decide(%{
             diff_empty?: false,
             prev_fingerprint: "sha256:a",
             current_fingerprint: "sha256:a"
           }) ==
             {:park, "convergence_stall"}
  end

  test "a changed fingerprint continues" do
    assert ConvergenceSentinel.decide(%{
             diff_empty?: false,
             prev_fingerprint: "sha256:a",
             current_fingerprint: "sha256:b"
           }) ==
             :continue
  end

  test "no prior fingerprint (first attempt, non-empty diff) continues" do
    assert ConvergenceSentinel.decide(%{
             diff_empty?: false,
             prev_fingerprint: nil,
             current_fingerprint: "sha256:a"
           }) ==
             :continue
  end

  test "empty diff takes precedence over a matching fingerprint" do
    assert ConvergenceSentinel.decide(%{
             diff_empty?: true,
             prev_fingerprint: "sha256:a",
             current_fingerprint: "sha256:a"
           }) ==
             {:park, "no_progress"}
  end
end
