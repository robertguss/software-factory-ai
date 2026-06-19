defmodule Conveyor.BehaviorOracleAdapterTest do
  use ExUnit.Case, async: true

  alias Conveyor.BehaviorOracleAdapter

  test "reports bounded no-divergence without claiming general equivalence" do
    fixture = %{
      fixture_id: "pure-refactor/tasks-list",
      inputs: [
        %{path: "/tasks", query: %{include_completed: true}},
        %{path: "/tasks", query: %{include_completed: false}}
      ],
      normalize_paths: [["headers", "date"], ["body", "generated_at"]],
      base_runner: fn input ->
        %{
          "status" => 200,
          "headers" => %{"date" => "Fri, 19 Jun 2026 05:00:00 GMT"},
          "body" => %{
            "path" => input.path,
            "query" => input.query,
            "generated_at" => "2026-06-19T05:00:00Z"
          }
        }
      end,
      candidate_runner: fn input ->
        %{
          "status" => 200,
          "headers" => %{"date" => "Fri, 19 Jun 2026 05:00:02 GMT"},
          "body" => %{
            "path" => input.path,
            "query" => input.query,
            "generated_at" => "2026-06-19T05:00:02Z"
          }
        }
      end
    }

    assert %{
             "schema_version" => "conveyor.behavior_oracle_result@1",
             "fixture_id" => "pure-refactor/tasks-list",
             "result" => "no_divergence_observed",
             "equivalence_claim" => "bounded_observation_only",
             "input_count" => 2,
             "normalized_paths" => [["headers", "date"], ["body", "generated_at"]],
             "findings" => []
           } = BehaviorOracleAdapter.evaluate!(fixture)
  end

  test "reports the first bounded input whose observable behavior diverged" do
    fixture = %{
      fixture_id: "pure-refactor/tasks-complete",
      inputs: [
        %{task_id: "task-1", completed: false},
        %{task_id: "task-1", completed: true}
      ],
      base_runner: fn input ->
        %{"status" => 200, "body" => %{"id" => input.task_id, "completed" => input.completed}}
      end,
      candidate_runner: fn input ->
        %{"status" => 200, "body" => %{"id" => input.task_id, "completed" => false}}
      end
    }

    assert %{
             "result" => "diverged",
             "first_divergence_index" => 1,
             "findings" => [
               %{
                 "category" => "behavior_divergence",
                 "input_index" => 1,
                 "base_observation" => %{"body" => %{"completed" => true}},
                 "candidate_observation" => %{"body" => %{"completed" => false}}
               }
             ]
           } = BehaviorOracleAdapter.evaluate!(fixture)
  end

  test "reports inconclusive when a bounded observation cannot be completed" do
    fixture = %{
      fixture_id: "pure-refactor/tasks-error",
      inputs: [%{task_id: "task-1"}],
      base_runner: fn input -> %{"status" => 200, "body" => %{"id" => input.task_id}} end,
      candidate_runner: fn _input -> raise "candidate crashed" end
    }

    assert %{
             "result" => "inconclusive",
             "first_inconclusive_index" => 0,
             "findings" => [
               %{
                 "category" => "oracle_execution_error",
                 "runner" => "candidate",
                 "input_index" => 0,
                 "message" => "candidate crashed"
               }
             ]
           } = BehaviorOracleAdapter.evaluate!(fixture)
  end

  test "does not pass vacuously without bounded inputs" do
    fixture = %{
      fixture_id: "pure-refactor/empty",
      inputs: [],
      base_runner: fn _input -> %{} end,
      candidate_runner: fn _input -> %{} end
    }

    assert %{
             "result" => "inconclusive",
             "findings" => [
               %{
                 "category" => "missing_bounded_inputs",
                 "message" => "behavior oracle requires at least one bounded input"
               }
             ]
           } = BehaviorOracleAdapter.evaluate!(fixture)
  end
end
