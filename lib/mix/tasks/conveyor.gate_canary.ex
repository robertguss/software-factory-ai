defmodule Mix.Tasks.Conveyor.GateCanary do
  @moduledoc """
  Runs the gate-canary fixture suite for a project.

      mix conveyor.gate_canary PROJECT_ID [--manifest PATH] [--output PATH]
  """

  use Mix.Task

  alias Conveyor.Jobs.RunGateCanary

  @shortdoc "Run the Conveyor gate-canary suite"
  @default_output "canary/mutants.json"

  @impl Mix.Task
  def run([project_id | args]) do
    Mix.Task.run("app.start")

    opts = parse_opts!(args)
    output_path = Keyword.fetch!(opts, :output)

    report =
      opts
      |> Keyword.put(:project_id, project_id)
      |> Keyword.put(:context, canary_context(project_id))
      |> RunGateCanary.run!()
      |> Map.put("project_id", project_id)
      |> Map.put("output_path", output_path)

    json = Jason.encode!(report, pretty: true)

    output_path
    |> Path.dirname()
    |> File.mkdir_p!()

    File.write!(output_path, json)
    Mix.shell().info(json)
    exit_fun().(Map.fetch!(report, "ci_exit_code"))
  end

  def run(_args) do
    Mix.raise(usage())
  end

  defp parse_opts!(args) do
    {opts, remaining, invalid} =
      OptionParser.parse(args,
        strict: [manifest: :string, output: :string]
      )

    if remaining != [] or invalid != [] do
      Mix.raise(usage())
    end

    []
    |> maybe_put(:manifest_path, opts[:manifest])
    |> Keyword.put(:output, opts[:output] || @default_output)
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp canary_context(project_id) do
    %{
      project_id: project_id,
      run_attempt_id: "gate-canary-cli",
      gate_code_sha256: "sha256:gate",
      policy_sha256: "sha256:policy",
      contract_lock_sha256: "sha256:contract",
      test_pack_sha256: "sha256:test-pack",
      container_image_digest: "sha256:image",
      code_quality_profile_sha256: "sha256:quality",
      canary_suite_version: "canary@1",
      runcheck_schema_version: "conveyor.run_bundle@1"
    }
  end

  defp usage do
    "usage: mix conveyor.gate_canary PROJECT_ID [--manifest PATH] [--output PATH]"
  end

  defp exit_fun do
    Process.get(:conveyor_gate_canary_exit_fun, &System.halt/1)
  end
end
