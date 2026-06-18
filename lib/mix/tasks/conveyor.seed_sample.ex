defmodule Mix.Tasks.Conveyor.SeedSample do
  @moduledoc """
  Seeds the Phase 1 sample tasks work graph.

      mix conveyor.seed_sample
  """

  use Mix.Task

  alias Conveyor.SampleTasksSeed

  @shortdoc "Seed the Phase 1 sample tasks work graph"

  @impl Mix.Task
  def run([]) do
    Mix.Task.run("app.start")

    result = SampleTasksSeed.seed!()

    Mix.shell().info("Seeded sample_tasks work graph")
    Mix.shell().info("Project: #{result.project.id}")
    Mix.shell().info("Plan: #{result.plan.id}")
    Mix.shell().info("Slice: #{result.slice.id}")
    Mix.shell().info("AgentBrief: #{result.agent_brief.id}")
    Mix.shell().info("ContractLock: #{result.contract_lock.id}")
    Mix.shell().info("TestPack: #{result.test_pack.id}")
    Mix.shell().info("RunSpec: #{result.run_spec.id}")
    Mix.shell().info("Base commit: #{result.base_commit}")
  end

  def run(_args) do
    Mix.raise("usage: mix conveyor.seed_sample")
  end
end
