defmodule Conveyor.AgentRunner.ReferenceSolution do
  @moduledoc """
  Deterministic, $0-LLM agent (idea #2): applies a fixed reference patch
  (known-good or a mutant) to the workspace as if an agent produced it, then emits
  the identical canned event stream and captures the resulting diff. The stand-in
  that lets the full plan→verdict pipeline run with zero spend.

  Mirrors `Conveyor.AgentRunner.Fake` exactly, swapping ONE function: instead of
  writing `fake_agent_output.txt`, it applies the patch named by
  `opts[:reference_patch]` (a repo-root-relative `.patch`, applied with `-p3`).
  Everything else — the event sequence, `capture_patch`, the `RawRunResult` shape —
  is identical so it passes `assert_adapter_conforms!/3`.
  """

  @behaviour Conveyor.AgentRunner

  alias Conveyor.AgentRunner.Capabilities
  alias Conveyor.AgentRunner.EventRecorder
  alias Conveyor.AgentRunner.PatchCapture
  alias Conveyor.Artifacts.BlobStore
  alias Conveyor.Factory
  alias Conveyor.Factory.AgentSession
  alias Conveyor.Factory.Policy
  alias Conveyor.Factory.RunPrompt

  @adapter "reference_solution"

  @impl true
  def capabilities do
    %Capabilities{
      streaming_events: true,
      pre_exec_command_policy: true,
      cancellation: :hard,
      diff_capture: :git_diff,
      cost_reporting: :estimated,
      mcp_support: false,
      slash_commands_enabled: false,
      structured_output: true,
      session_resume: true,
      known_limitations: []
    }
  end

  @impl true
  def run(%RunPrompt{} = run_prompt, workspace, %Policy{} = _policy, opts \\ []) do
    agent_session_id = Keyword.fetch!(opts, :agent_session_id)
    session_id = Keyword.get(opts, :session_id, "reference-#{Ash.UUID.generate()}")
    blob_opts = Keyword.take(opts, [:blob_root])

    # THE ONLY REAL CHANGE vs Fake: apply a fixed reference patch instead of
    # writing fake_agent_output.txt.
    apply_reference_patch!(workspace, opts)

    record_event!(
      agent_session_id,
      session_id,
      "session_started",
      %{"mode" => "reference"},
      blob_opts
    )

    record_event!(agent_session_id, session_id, "heartbeat", %{"status" => "running"}, blob_opts)

    record_event!(
      agent_session_id,
      session_id,
      "message_completed",
      message(run_prompt),
      blob_opts
    )

    record_event!(agent_session_id, session_id, "command_requested", command(), blob_opts)

    record_event!(
      agent_session_id,
      session_id,
      "command_policy_decision",
      policy_decision(),
      blob_opts
    )

    patch_capture = capture_patch(workspace, opts, blob_opts)
    raw_transcript_ref = raw_transcript_ref(run_prompt, session_id, blob_opts)

    result = %Conveyor.AgentRunner.RawRunResult{
      summary: "Reference solution applied #{run_prompt.body_sha256}",
      messages: [message(run_prompt)],
      tool_calls: [command()],
      attempted_commands: ["reference verify"],
      diff_ref: patch_capture.patch_ref,
      metadata: %{
        "adapter" => @adapter,
        "session_id" => session_id,
        "patch_set_id" => patch_capture.patch_set_id,
        "raw_transcript_ref" => raw_transcript_ref,
        "reference_patch" => Keyword.get(opts, :reference_patch)
      }
    }

    record_event!(
      agent_session_id,
      session_id,
      "final_response",
      %{"summary" => result.summary},
      blob_opts
    )

    record_event!(
      agent_session_id,
      session_id,
      "session_completed",
      %{"status" => "succeeded"},
      blob_opts
    )

    update_agent_session!(agent_session_id, session_id, result, raw_transcript_ref)

    {:ok, result}
  end

  @impl true
  def cancel(session_id), do: cancel(session_id, [])

  @spec cancel(String.t(), keyword()) :: :ok
  def cancel(session_id, opts) when is_binary(session_id) and session_id != "" do
    if agent_session_id = Keyword.get(opts, :agent_session_id) do
      blob_opts = Keyword.take(opts, [:blob_root])
      reason = Keyword.get(opts, :reason, "operator_requested")

      record_event!(
        agent_session_id,
        session_id,
        "cancel_requested",
        %{"reason" => reason},
        blob_opts
      )

      record_event!(
        agent_session_id,
        session_id,
        "cancel_acknowledged",
        %{"reason" => reason},
        blob_opts
      )
    end

    :ok
  end

  # Apply the configured reference patch (repo-root-relative, -p3). Treats the
  # patch as data (ADR-07) — it is the agent's "output", not instruction authority.
  defp apply_reference_patch!(workspace, opts) do
    patch_ref = Keyword.fetch!(opts, :reference_patch)
    ws_path = workspace_path!(workspace)
    patch_abs = Path.expand(patch_ref, File.cwd!())

    case System.cmd("patch", ["-p3", "-f", "-d", ws_path, "-i", patch_abs],
           stderr_to_stdout: true
         ) do
      {_out, 0} -> :ok
      {out, status} -> raise "reference patch #{patch_ref} failed to apply (#{status}): #{out}"
    end
  end

  defp capture_patch(workspace, opts, blob_opts) do
    case Keyword.get(opts, :run_attempt_id) do
      nil ->
        diff = git_diff!(workspace_path!(workspace), base_commit!(workspace, opts))
        blob = BlobStore.write!(diff, blob_opts)
        %{patch_ref: blob.ref, patch_set_id: nil}

      run_attempt_id ->
        patch_set =
          PatchCapture.capture!(
            workspace,
            blob_opts
            |> Keyword.put(:base_commit, base_commit!(workspace, opts))
            |> Keyword.put(:run_attempt_id, run_attempt_id)
            |> Keyword.put(:agent_session_id, Keyword.get(opts, :agent_session_id))
            |> Keyword.put(:locked_paths, Keyword.get(opts, :locked_paths, []))
          )

        %{patch_ref: patch_set.patch_ref, patch_set_id: patch_set.id}
    end
  end

  defp record_event!(agent_session_id, session_id, event_type, payload, blob_opts) do
    EventRecorder.record!(
      %{
        agent_session_id: agent_session_id,
        adapter: @adapter,
        session_id: session_id,
        sequence_no: EventRecorder.next_sequence_no(agent_session_id),
        event_type: event_type,
        payload: payload,
        raw: payload
      },
      blob_opts
    )
  end

  defp raw_transcript_ref(run_prompt, session_id, blob_opts) do
    %{
      "adapter" => @adapter,
      "session_id" => session_id,
      "run_prompt_sha256" => run_prompt.body_sha256
    }
    |> Jason.encode!(pretty: true)
    |> BlobStore.write!(blob_opts)
    |> Map.fetch!(:ref)
  end

  defp update_agent_session!(agent_session_id, session_id, result, raw_transcript_ref) do
    update_agent_session(agent_session_id, %{
      adapter_session_id: result.metadata["session_id"] || session_id,
      status: :succeeded,
      completed_at: DateTime.utc_now(:microsecond),
      raw_result_ref: raw_transcript_ref
    })
  end

  defp update_agent_session(agent_session_id, attrs) do
    AgentSession
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == agent_session_id))
    |> case do
      nil -> :ok
      session -> Ash.update!(session, attrs, domain: Factory)
    end
  end

  defp message(run_prompt) do
    %{"role" => "assistant", "content" => "Reference solution for #{run_prompt.body_sha256}"}
  end

  defp command, do: %{"argv" => ["reference", "verify"], "trusted" => true}
  defp policy_decision, do: %{"decision" => "allowed", "reason" => "reference runner command"}

  defp workspace_path!(workspace) do
    workspace
    |> field(:path, :workspace_path)
    |> require_non_empty_string!(:workspace_path)
    |> Path.expand()
  end

  defp base_commit!(workspace, opts) do
    opts
    |> Keyword.get(:base_commit)
    |> Kernel.||(field(workspace, :base_commit))
    |> require_non_empty_string!(:base_commit)
  end

  defp field(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
  defp field(struct, primary, fallback), do: field(struct, primary) || field(struct, fallback)

  defp require_non_empty_string!(value, _field) when is_binary(value) and value != "", do: value

  defp require_non_empty_string!(_value, field),
    do: raise(ArgumentError, "#{field} must be a non-empty string")

  defp git_diff!(workspace_path, base_commit) do
    System.cmd("git", ["-C", workspace_path, "add", "--intent-to-add", "--", "."],
      stderr_to_stdout: true
    )

    case System.cmd("git", ["-C", workspace_path, "diff", "--binary", base_commit, "--"],
           stderr_to_stdout: true
         ) do
      {diff, 0} -> diff
      {output, status} -> raise "git diff failed with #{status}: #{output}"
    end
  end
end
