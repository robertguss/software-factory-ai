defmodule Mix.Tasks.ConveyorQualificationGateTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Conveyor.Qualification.Gate

  test "qualification_gate emits a canonical JSON result for a passing package" do
    input_path =
      write_json!(%{
        deterministic_checks: passed_checks(),
        replay_checks: passed_replays(),
        live_sample_run: %{
          "worst_required_stratum_result" => "quality_floor_met",
          "stratum_results" => [
            %{
              "stratum_key" => "adapter=primary-live|archetype=planning",
              "band_status" => "quality_floor_met",
              "sample_count" => 40
            }
          ]
        }
      })

    put_exit_fun()

    output =
      capture_io(fn ->
        Mix.Task.reenable("conveyor.qualification_gate")

        Mix.Task.run("conveyor.qualification_gate", [
          "software-factory-ai",
          "--scope",
          "adapter=primary-live,archetype=planning",
          "--input",
          input_path,
          "--format",
          "json"
        ])
      end)

    result = Jason.decode!(output)

    assert result["schema_version"] == "conveyor.qualification_gate_result@1"
    assert result["project_id"] == "software-factory-ai"
    assert result["status"] == "passed"
    assert result["authority_effect"] == "qualification_grant_candidate"
    assert result["requested_scope"] == %{"adapter" => "primary-live", "archetype" => "planning"}
    assert_received {:exit_code, 0}
  after
    Process.delete(:conveyor_qualification_gate_exit_fun)
  end

  defp put_exit_fun do
    test_pid = self()

    Process.put(:conveyor_qualification_gate_exit_fun, fn code ->
      send(test_pid, {:exit_code, code})
    end)
  end

  defp passed_checks do
    Gate.required_hard_blockers()
    |> Enum.map(&%{key: &1, status: "passed"})
  end

  defp passed_replays do
    Gate.required_replay_modes()
    |> Enum.map(&%{mode: &1, status: "passed"})
  end

  defp write_json!(payload) do
    path =
      Path.join(
        System.tmp_dir!(),
        "conveyor-qualification-gate-#{System.unique_integer([:positive])}.json"
      )

    File.write!(path, Jason.encode!(payload))
    path
  end
end
