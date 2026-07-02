defmodule Conveyor.Planning.RaceConductorTest do
  @moduledoc "ADR-25 — speculative parallelism winner selection + race orchestration."
  use ExUnit.Case, async: true

  alias Conveyor.Planning.RaceConductor

  describe "select_winner/1" do
    test "picks the highest-TrustScore passing candidate" do
      results = [
        %{id: :a, passed?: true, score: 0.91, cost: 100},
        %{id: :b, passed?: true, score: 0.97, cost: 200},
        %{id: :c, passed?: false, score: 0.99, cost: 10}
      ]

      assert {:ok, %{id: :b}} = RaceConductor.select_winner(results)
    end

    test "breaks ties by lowest cost" do
      results = [
        %{id: :a, passed?: true, score: 0.95, cost: 300},
        %{id: :b, passed?: true, score: 0.95, cost: 120}
      ]

      assert {:ok, %{id: :b}} = RaceConductor.select_winner(results)
    end

    test "ignores candidates that did not pass" do
      results = [%{id: :a, passed?: false, score: 0.99, cost: 1}]
      assert RaceConductor.select_winner(results) == :no_winner
    end

    test "no candidates passed -> :no_winner" do
      assert RaceConductor.select_winner([]) == :no_winner
    end
  end

  describe "race/3" do
    test "runs candidates concurrently and returns the winner" do
      candidates = [
        %{id: :slow, score: 0.92},
        %{id: :best, score: 0.98},
        %{id: :fail, score: 0.99}
      ]

      run_fn = fn c ->
        %{id: c.id, passed?: c.id != :fail, score: c.score, cost: 10}
      end

      assert {:winner, %{id: :best}, results} = RaceConductor.race(candidates, run_fn)
      assert length(results) == 3
    end

    test "all candidates fail -> :no_winner with all results" do
      candidates = [%{id: :a}, %{id: :b}]
      run_fn = fn c -> %{id: c.id, passed?: false, score: 0.0, cost: 1} end

      assert {:no_winner, results} = RaceConductor.race(candidates, run_fn)
      assert length(results) == 2
    end

    test "a single candidate (default width-1) returns it when it passes" do
      run_fn = fn c -> %{id: c.id, passed?: true, score: 0.93, cost: 5} end
      assert {:winner, %{id: :only}, _} = RaceConductor.race([%{id: :only}], run_fn)
    end

    test "a candidate that crashes becomes a failed result, never crashing the race (dr1m.3.1)" do
      candidates = [%{id: :boom}, %{id: :good, score: 0.9}]

      run_fn = fn
        %{id: :boom} -> raise "candidate blew up"
        c -> %{id: c.id, passed?: true, score: c.score, cost: 10}
      end

      assert {:winner, %{id: :good}, results} = RaceConductor.race(candidates, run_fn)
      assert length(results) == 2

      boom = Enum.find(results, &(&1.id == :boom))
      refute boom.passed?
      assert Map.has_key?(boom, :error)
    end

    test "a candidate that exceeds the timeout is killed and marked failed, not fatal (dr1m.3.1)" do
      candidates = [%{id: :slow}, %{id: :fast, score: 0.9}]

      run_fn = fn
        %{id: :slow} = c ->
          Process.sleep(5_000)
          %{id: c.id, passed?: true, score: 1.0, cost: 1}

        c ->
          %{id: c.id, passed?: true, score: c.score, cost: 10}
      end

      assert {:winner, %{id: :fast}, results} =
               RaceConductor.race(candidates, run_fn, timeout: 50)

      slow = Enum.find(results, &(&1.id == :slow))
      refute slow.passed?
      assert slow.error == :timeout
    end

    test "all candidates crash -> :no_winner with failed results (dr1m.3.1)" do
      candidates = [%{id: :a}, %{id: :b}]
      run_fn = fn _c -> raise "always fails" end

      assert {:no_winner, results} = RaceConductor.race(candidates, run_fn)
      assert length(results) == 2
      assert Enum.all?(results, &(&1.passed? == false))
    end
  end
end
