defmodule Conveyor.StatisticsTest do
  use ExUnit.Case, async: true

  alias Conveyor.Statistics

  describe "regularized_incomplete_beta/3" do
    test "matches closed-form references" do
      assert_in_delta Statistics.regularized_incomplete_beta(0.5, 1, 1), 0.5, 1.0e-9
      assert_in_delta Statistics.regularized_incomplete_beta(0.5, 2, 2), 0.5, 1.0e-9
      assert Statistics.regularized_incomplete_beta(0.0, 2, 5) == 0.0
      assert Statistics.regularized_incomplete_beta(1.0, 2, 5) == 1.0
    end
  end

  describe "clopper_pearson_interval/3" do
    test "matches published two-sided 95% intervals" do
      {lo, hi} = Statistics.clopper_pearson_interval(8, 10, 0.95)
      assert_in_delta lo, 0.4439, 0.001
      assert_in_delta hi, 0.9748, 0.001

      {lo5, hi5} = Statistics.clopper_pearson_interval(5, 10, 0.95)
      assert_in_delta lo5, 0.1871, 0.001
      assert_in_delta hi5, 0.8129, 0.001
    end

    test "uses hard boundaries at the extremes" do
      {lo0, hi0} = Statistics.clopper_pearson_interval(0, 10, 0.95)
      assert lo0 == 0.0
      assert_in_delta hi0, 0.3085, 0.001

      {lo_all, hi_all} = Statistics.clopper_pearson_interval(10, 10, 0.95)
      assert hi_all == 1.0
      assert_in_delta lo_all, 0.6915, 0.001

      {lo_zero, hi_zero} = Statistics.clopper_pearson_interval(0, 0, 0.95)
      assert lo_zero == 0.0
      assert hi_zero == 1.0
    end

    test "lower bound sits below the point estimate and tightens with more samples" do
      {lo_small, _} = Statistics.clopper_pearson_interval(9, 10, 0.95)
      {lo_large, _} = Statistics.clopper_pearson_interval(90, 100, 0.95)

      assert lo_small < 0.9
      assert lo_large < 0.9
      # Same point estimate, more samples -> tighter (higher) lower bound.
      assert lo_large > lo_small
    end
  end
end
