defmodule Conveyor.Eval.CassetteBridge do
  @moduledoc """
  The Cassette Flywheel (B4): wires the built-but-orphaned cassette record/replay
  (`Conveyor.Cassettes`, `ReplayEngine`, `Freshness`) around the agent boundary so
  any run (ReferenceSolution today, a real LLM later) is recorded once and replayed
  deterministically for $0 forever.

  `run/5` is an **opt-in wrapper** over `Conveyor.AgentRunner.run/5`: with no
  `:cassette_key` it is a pure passthrough (perfect back-compat — core AgentRunner
  is untouched). With a `:cassette_key`:

    * **Replay** (before invoking the adapter): if a sealed cassette exists for the
      key and the current `generation_freshness_digest` matches the recorded one,
      `ReplayEngine.replay(:full, …)` returns the recorded `primary_outputs`, from
      which we synthesize the `RawRunResult` and return **without calling the
      adapter** ($0). A stale freshness → a miss (never a false replay), and we run
      live instead.
    * **Record** (on a live `{:ok, RawRunResult}`): seal a `conveyor.agent_cassette@1`
      via `Cassettes.record/2` and persist it (with the freshness + a `result_digest`)
      under `eval/cassettes/`.

  Cassettes are return-only maps; we persist them as files (no DB), so replay is
  DB-free. `record/2`'s cassette omits `generation_freshness_digest`, so the file
  stores it (and empty `tool_records`/`causal_events`) next to the schema-valid
  cassette and merges them at replay.

  Divergence from the plan sketch: the seam is a wrapper here, not an edit to
  `AgentRunner.run/5` — same opt-in/back-compat behavior with cleaner layering
  (eval depends on core, not the reverse).
  """

  alias Conveyor.AgentRunner
  alias Conveyor.AgentRunner.RawRunResult
  alias Conveyor.CanonicalJson
  alias Conveyor.Cassettes
  alias Conveyor.Cassettes.{Freshness, ReplayEngine}

  @cassettes_dir "eval/cassettes"

  @doc """
  Opt-in cached agent run. With `opts[:cassette_key]` set, replays a matching sealed
  cassette ($0, adapter not invoked) or runs live and records one. Without it, a
  plain `AgentRunner.run/5`.
  """
  @spec run(module(), struct(), term(), term(), keyword()) ::
          {:ok, RawRunResult.t()} | {:error, term()}
  def run(adapter, run_prompt, workspace, policy, opts) do
    case Keyword.get(opts, :cassette_key) do
      nil -> AgentRunner.run(adapter, run_prompt, workspace, policy, opts)
      key -> cached_run(key, adapter, run_prompt, workspace, policy, opts)
    end
  end

  defp cached_run(key, adapter, run_prompt, workspace, policy, opts) do
    freshness = freshness_digest(run_prompt, adapter)

    case maybe_replay(key, freshness) do
      {:replayed, %RawRunResult{} = result} -> {:ok, result}
      :miss -> run_live_and_record(key, adapter, run_prompt, workspace, policy, freshness, opts)
    end
  end

  defp run_live_and_record(key, adapter, run_prompt, workspace, policy, freshness, opts) do
    with {:ok, %RawRunResult{} = result} <-
           AgentRunner.run(adapter, run_prompt, workspace, policy, opts) do
      record!(key, result, run_prompt, adapter, freshness)
      {:ok, result}
    end
  end

  @doc "Synthesize a `RawRunResult` from a sealed cassette for `key` if fresh; else `:miss`."
  @spec maybe_replay(String.t(), String.t()) :: {:replayed, RawRunResult.t()} | :miss
  def maybe_replay(key, current_freshness) do
    with {:ok, file} <- read_file(key),
         cassette <- replay_cassette(file),
         {:ok, %{status: :replayed, primary_outputs: [json | _]}} <-
           ReplayEngine.replay(:full, cassette,
             current_generation_freshness_digest: current_freshness,
             requested_tool_records: [],
             requested_causal_events: []
           ) do
      {:replayed, raw_from_json(json)}
    else
      _ -> :miss
    end
  end

  @doc "Seal and persist a cassette for `key` from a live `RawRunResult`."
  @spec record!(String.t(), RawRunResult.t(), struct(), module(), String.t()) :: map()
  def record!(key, %RawRunResult{} = result, run_prompt, adapter, freshness) do
    series = series(run_prompt, adapter, freshness)

    {:ok, cassette} =
      Cassettes.record(series,
        recording_no: 1,
        recorded_at: now(),
        provider: %{model_id: to_string(adapter), model_revision: "v1", request_id: "rec-1"},
        agent_event_stream: [%{"event_type" => "final_response"}],
        tool_transcript: [],
        primary_outputs: [raw_to_json(result)]
      )

    write_file!(key, %{
      "cassette" => cassette,
      "generation_freshness_digest" => freshness,
      "tool_records" => [],
      "causal_events" => [],
      "result_digest" => result_digest(result)
    })

    cassette
  end

  @doc "Canonical digest over a `RawRunResult`'s reportable fields (the replay-fidelity key)."
  @spec result_digest(RawRunResult.t()) :: String.t()
  def result_digest(%RawRunResult{} = result), do: CanonicalJson.digest(raw_map(result))

  @doc "Replay every sealed cassette under `eval/cassettes/`, checking the synthesized digest matches the recorded one."
  @spec replay_corpus() :: %{
          total: non_neg_integer(),
          matched: non_neg_integer(),
          fidelity: float()
        }
  def replay_corpus do
    files = corpus_files()

    matched =
      Enum.count(files, fn path ->
        file = path |> File.read!() |> Jason.decode!()
        cassette = replay_cassette(file)
        recorded = file["generation_freshness_digest"]

        case ReplayEngine.replay(:full, cassette,
               current_generation_freshness_digest: recorded,
               requested_tool_records: [],
               requested_causal_events: []
             ) do
          {:ok, %{status: :replayed, primary_outputs: [json | _]}} ->
            result_digest(raw_from_json(json)) == file["result_digest"]

          _ ->
            false
        end
      end)

    total = length(files)
    %{total: total, matched: matched, fidelity: if(total == 0, do: 1.0, else: matched / total)}
  end

  @doc "List sealed cassette file paths."
  @spec corpus_files() :: [String.t()]
  def corpus_files do
    case File.ls(@cassettes_dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".json"))
        |> Enum.sort()
        |> Enum.map(&Path.join(@cassettes_dir, &1))

      {:error, _} ->
        []
    end
  end

  # --- internals ------------------------------------------------------------

  defp series(run_prompt, adapter, freshness) do
    Cassettes.new_series!(%{
      spec_kind: "run_spec",
      spec_digest: run_prompt.body_sha256,
      role: "implementer",
      adapter: to_string(adapter),
      agent_profile_snapshot_digest: digest("profile"),
      capability_snapshot_digest: digest("capability"),
      generation_environment_fingerprint_digest: digest("env"),
      generation_freshness_digest: freshness,
      created_at: now()
    })
  end

  # Deterministic generation freshness from the prompt + adapter (no clock/RNG).
  defp freshness_digest(run_prompt, adapter) do
    %{
      prompt_digest: run_prompt.body_sha256,
      role_view_digest: digest("role:implementer"),
      context_pack_digest: digest("context:bridge"),
      adapter_profile_digest: digest("adapter:#{adapter}"),
      tool_contract_digest: digest("tools:bridge")
    }
    |> Freshness.surface_digests()
    |> Map.fetch!(:generation_freshness_digest)
  end

  defp replay_cassette(file) do
    Map.merge(file["cassette"], %{
      "generation_freshness_digest" => file["generation_freshness_digest"],
      "tool_records" => file["tool_records"] || [],
      "causal_events" => file["causal_events"] || []
    })
  end

  defp raw_map(%RawRunResult{} = r) do
    %{
      "summary" => r.summary,
      "messages" => r.messages,
      "tool_calls" => r.tool_calls,
      "attempted_commands" => r.attempted_commands,
      "diff_ref" => r.diff_ref,
      "metadata" => r.metadata
    }
  end

  defp raw_to_json(%RawRunResult{} = r), do: Jason.encode!(raw_map(r))

  defp raw_from_json(json) do
    map = Jason.decode!(json)

    %RawRunResult{
      summary: map["summary"],
      messages: map["messages"] || [],
      tool_calls: map["tool_calls"] || [],
      attempted_commands: map["attempted_commands"] || [],
      diff_ref: map["diff_ref"],
      metadata: map["metadata"] || %{}
    }
  end

  defp read_file(key) do
    path = cassette_path(key)
    if File.exists?(path), do: {:ok, path |> File.read!() |> Jason.decode!()}, else: :error
  end

  defp write_file!(key, file) do
    File.mkdir_p!(@cassettes_dir)
    File.write!(cassette_path(key), CanonicalJson.encode(file))
  end

  defp cassette_path(key), do: Path.join(@cassettes_dir, key <> ".json")
  defp now, do: DateTime.utc_now() |> DateTime.to_iso8601()
  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
