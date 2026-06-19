defmodule Mix.Tasks.Conveyor.EvidenceTimeMachineCommands do
  @moduledoc false

  alias Conveyor.Evidence.TimeMachine

  def run_diff(command, args, usage) do
    {opts, positional, invalid} =
      OptionParser.parse(args, strict: [section: :string, markdown: :boolean])

    case {positional, invalid} do
      {[left_path, right_path], []} ->
        report =
          command
          |> TimeMachine.diff(
            TimeMachine.read_json!(left_path),
            TimeMachine.read_json!(right_path),
            section: opts[:section],
            markdown: markdown(command, opts[:markdown])
          )
          |> Jason.encode!()

        Mix.shell().info(report)

      _other ->
        Mix.raise(usage)
    end
  end

  def run_why_stale(args, usage) do
    case args do
      [subject_path] ->
        subject_path
        |> TimeMachine.read_json!()
        |> TimeMachine.why_stale()
        |> Jason.encode!()
        |> Mix.shell().info()

      _other ->
        Mix.raise(usage)
    end
  end

  defp markdown(_command, nil), do: nil
  defp markdown(_command, false), do: nil
  defp markdown(command, true), do: "## #{command}\n\nSee canonical JSON comparison for details."
end

defmodule Mix.Tasks.Conveyor.DiffRuns do
  @moduledoc "Compares two run subject descriptors."
  use Mix.Task
  @shortdoc "Compare two run descriptors"

  @impl Mix.Task
  def run(args) do
    Mix.Tasks.Conveyor.EvidenceTimeMachineCommands.run_diff(
      "diff_runs",
      args,
      "usage: mix conveyor.diff_runs RUN_A RUN_B [--section SECTION] [--markdown]"
    )
  end
end

defmodule Mix.Tasks.Conveyor.DiffPlans do
  @moduledoc "Compares two plan revision descriptors."
  use Mix.Task
  @shortdoc "Compare two plan descriptors"

  @impl Mix.Task
  def run(args) do
    Mix.Tasks.Conveyor.EvidenceTimeMachineCommands.run_diff(
      "diff_plans",
      args,
      "usage: mix conveyor.diff_plans REV_A REV_B [--markdown]"
    )
  end
end

defmodule Mix.Tasks.Conveyor.DiffCandidates do
  @moduledoc "Compares two candidate descriptors."
  use Mix.Task
  @shortdoc "Compare two candidate descriptors"

  @impl Mix.Task
  def run(args) do
    Mix.Tasks.Conveyor.EvidenceTimeMachineCommands.run_diff(
      "diff_candidates",
      args,
      "usage: mix conveyor.diff_candidates CANDIDATE_A CANDIDATE_B [--markdown]"
    )
  end
end

defmodule Mix.Tasks.Conveyor.DiffGrants do
  @moduledoc "Compares two qualification grant descriptors."
  use Mix.Task
  @shortdoc "Compare two grant descriptors"

  @impl Mix.Task
  def run(args) do
    Mix.Tasks.Conveyor.EvidenceTimeMachineCommands.run_diff(
      "diff_grants",
      args,
      "usage: mix conveyor.diff_grants GRANT_A GRANT_B [--markdown]"
    )
  end
end

defmodule Mix.Tasks.Conveyor.WhyDifferent do
  @moduledoc "Explains why two subject descriptors differ."
  use Mix.Task
  @shortdoc "Explain subject descriptor differences"

  @impl Mix.Task
  def run(args) do
    Mix.Tasks.Conveyor.EvidenceTimeMachineCommands.run_diff(
      "why_different",
      args,
      "usage: mix conveyor.why_different LEFT RIGHT [--markdown]"
    )
  end
end

defmodule Mix.Tasks.Conveyor.WhyStale do
  @moduledoc "Explains why a subject descriptor is stale."
  use Mix.Task
  @shortdoc "Explain stale subject metadata"

  @impl Mix.Task
  def run(args) do
    Mix.Tasks.Conveyor.EvidenceTimeMachineCommands.run_why_stale(
      args,
      "usage: mix conveyor.why_stale SUBJECT_JSON"
    )
  end
end
