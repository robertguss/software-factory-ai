defmodule Conveyor.Reviewer.ContainedReviewer do
  @moduledoc """
  m4b2.2: the real contained second-agent reviewer — the production `:reviewer` for `RunReviewer`.

  It renders the adversarial rubric prompt (m4b2.3) over the bounded, redacted dossier, hands it to
  a contained agent, and parses the `conveyor.review@1` verdict. Two invariants make it safe:

    * **Read-only workspace** — the agent runs through `ContainedExec` with `mount_mode: :ro`, so
      the reviewer physically cannot mutate the code it judges (D1 containment parity with the gate).
    * **Identity is stamped by us, not the agent** — `run_spec_sha256`/`dossier_sha256`/`reviewer`
      come from the trusted context; the agent only supplies the judgment. A malformed judgment
      leaves those fields on a verdict that fails schema validation, so `RunReviewer` records it as
      `:not_assessed` (fail closed) rather than trusting a guess.

  The agent invocation is an injectable seam (`:exec`) so tests run a canned review at \$0 and CI
  cassettes replay; the default builds the contained, read-only Claude Code invocation.
  """

  require Logger

  alias Conveyor.AgentRunner.ContainedExec
  alias Conveyor.Reviewer.Rubric

  @doc "Build the `:reviewer` function `RunReviewer` calls. `opts[:exec]` overrides the agent seam."
  @spec reviewer_fun(keyword()) :: (map() -> map())
  def reviewer_fun(opts \\ []), do: fn context -> review(context, opts) end

  @spec review(map(), keyword()) :: map()
  def review(context, opts \\ []) do
    rubric = Rubric.load(context.rubric_version)
    prompt = Rubric.render_prompt(rubric, prompt_context(context))
    exec = Keyword.get(opts, :exec, &default_exec/3)

    prompt
    |> exec.(context, opts)
    |> parse_verdict()
    |> stamp_identity(context)
  end

  # Only the bounded, already-redacted dossier crosses into the untrusted prompt sections.
  defp prompt_context(context) do
    %{
      desired_behavior: context[:desired_behavior],
      acceptance_criteria: context[:acceptance_criteria],
      diff: context.dossier,
      excerpts: nil
    }
  end

  # The agent returns only the judgment; unparseable output yields an empty map, which fails schema
  # validation downstream and is recorded :not_assessed (never a guessed accept).
  defp parse_verdict(raw) when is_binary(raw) do
    case Jason.decode(raw) do
      {:ok, verdict} when is_map(verdict) ->
        verdict

      _ ->
        Logger.warning(
          "ContainedReviewer: agent output was not valid JSON; verdict left unassessed."
        )

        %{}
    end
  end

  defp parse_verdict(verdict) when is_map(verdict), do: verdict
  defp parse_verdict(_other), do: %{}

  # Trusted identity is stamped by us — the agent can never forge which run/dossier it reviewed.
  defp stamp_identity(verdict, context) do
    Map.merge(verdict, %{
      "schema_version" => "conveyor.review@1",
      "run_spec_sha256" => raw_sha256(context.run_spec.run_spec_sha256),
      "dossier_sha256" => context.dossier_sha256,
      "rubric_version" => context.rubric_version,
      "reviewer" => %{
        "actor_id" => context.reviewer_session_id,
        "profile_id" => context.reviewer_profile_id
      }
    })
  end

  # The default agent invocation: contained, network-egress to the model API only, and — the
  # load-bearing reviewer invariant — the workspace bind-mount is READ-ONLY.
  defp default_exec(prompt, _context, opts) do
    workspace = Keyword.fetch!(opts, :workspace)
    argv = Keyword.get(opts, :argv, ["claude", "--print", prompt])

    {stdout, _exit} =
      ContainedExec.run(argv, workspace, Keyword.put(opts, :mount_mode, :ro))

    stdout
  end

  defp raw_sha256("sha256:" <> hex), do: hex
  defp raw_sha256(value), do: value
end
