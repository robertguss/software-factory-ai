defmodule Conveyor.Jobs.RunReviewer do
  @moduledoc """
  Runs an independent reviewer over the recorded run dossier.

  The reviewer context is intentionally limited to the projected dossier bytes
  and digest metadata. Live implementer-session narration is not passed through
  this boundary.
  """

  use Oban.Worker, queue: :gate, max_attempts: 1

  require Logger

  alias Conveyor.Artifacts.BlobStore
  alias Conveyor.Factory
  alias Conveyor.Factory.AgentSession
  alias Conveyor.Factory.Artifact
  alias Conveyor.Factory.Review
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Factory.Validations.ReviewerActorSeparation
  alias Conveyor.Reviewer.Rubric

  defmodule Result do
    @moduledoc false

    @type t :: %__MODULE__{
            review: Review.t(),
            reviewer_session: AgentSession.t(),
            review_json: map()
          }

    @enforce_keys [:review, :reviewer_session, :review_json]
    defstruct [:review, :reviewer_session, :review_json]
  end

  @schema_path Path.expand("../../../docs/schemas/conveyor.review@1.json", __DIR__)
  @rubric_version "reviewer@1"

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"run_attempt_id" => run_attempt_id}} = job) do
    run_attempt = get_by_id!(RunAttempt, run_attempt_id)

    _result =
      run!(run_attempt,
        reviewer_profile_id: Map.get(job.args, "reviewer_profile_id"),
        run_prompt_id: Map.get(job.args, "run_prompt_id")
      )

    :ok
  end

  @spec run!(RunAttempt.t(), keyword()) :: Result.t()
  def run!(%RunAttempt{} = run_attempt, opts \\ []) do
    run_spec = get_by_id!(RunSpec, run_attempt.run_spec_id)
    reviewer_profile_id = Keyword.get(opts, :reviewer_profile_id) || Ash.UUID.generate()
    run_prompt_id = Keyword.get(opts, :run_prompt_id) || Ash.UUID.generate()
    rubric_version = Keyword.get(opts, :rubric_version, @rubric_version)
    rubric_sha256 = rubric_sha256_for(rubric_version)
    dossier = read_dossier!(run_attempt, opts)
    now = DateTime.utc_now(:microsecond)

    case ReviewerActorSeparation.check(run_attempt.id, reviewer_profile_id, nil) do
      :ok -> :ok
      {:error, message} -> raise ArgumentError, message
    end

    # Fail closed, never rubber-stamp: an unconfigured reviewer must refuse, not accept
    # (m4b2.1). Resolved after the separation check so its error still surfaces first.
    reviewer = configured_reviewer!(opts)

    reviewer_session =
      create_reviewer_session!(run_attempt, reviewer_profile_id, run_prompt_id, now, opts)

    context = %{
      dossier: dossier.content,
      dossier_sha256: dossier.sha256,
      run_attempt: run_attempt,
      run_spec: run_spec,
      reviewer_profile_id: reviewer_profile_id,
      reviewer_session_id: reviewer_session.id,
      rubric_version: rubric_version,
      rubric_sha256: rubric_sha256
    }

    # An infra failure (the reviewer subprocess crashing) is distinct from a malformed VERDICT and
    # still raises — a review that never ran is not a not_assessed review. A verdict that ran but
    # failed schema validation is recorded as :not_assessed (fail-closed) so the gate blocks on it.
    review_json = invoke_reviewer!(reviewer, context, reviewer_session)

    {review_status, review_attrs} =
      classify_review(review_json, run_spec, dossier.sha256, reviewer_profile_id)

    review =
      Ash.create!(
        Review,
        Map.merge(review_attrs, %{
          run_attempt_id: run_attempt.id,
          reviewer_session_id: reviewer_session.id,
          reviewer_profile_id: reviewer_profile_id,
          review_kind: Keyword.get(opts, :review_kind, :general),
          rubric_sha256: rubric_sha256,
          dossier_sha256: dossier.sha256,
          reviewed_at: now
        }),
        domain: Factory
      )

    usage = usage_from(review_json)
    reviewer_session = finalize_session!(reviewer_session, review_status, usage)
    log_review(run_attempt, reviewer_session, review, usage)

    %Result{review: review, reviewer_session: reviewer_session, review_json: review_json}
  end

  defp invoke_reviewer!(reviewer, context, reviewer_session) do
    reviewer.(context)
  rescue
    error ->
      Ash.update!(
        reviewer_session,
        %{status: :failed, completed_at: DateTime.utc_now(:microsecond)},
        domain: Factory
      )

      reraise error, __STACKTRACE__
  end

  # A schema-valid verdict is recorded as-is; a malformed one becomes a :not_assessed review with
  # the validation error in its summary (fail-closed — the gate blocks any non-accepted decision).
  defp classify_review(review_json, run_spec, dossier_sha256, reviewer_profile_id) do
    case validate_review(review_json, run_spec, dossier_sha256, reviewer_profile_id) do
      :ok ->
        {:succeeded,
         %{
           rubric_version: review_json["rubric_version"],
           decision: atom!(review_json["decision"]),
           recommendation: atom!(review_json["recommendation"]),
           summary: review_json["summary"],
           findings: review_json["findings"],
           checks: review_json["checks"]
         }}

      {:error, reason} ->
        Logger.warning(
          "RunReviewer: reviewer output failed validation (#{reason}); " <>
            "recording a :not_assessed review (fail closed)."
        )

        {:not_assessed,
         %{
           rubric_version: @rubric_version,
           decision: :not_assessed,
           recommendation: :ask_human,
           summary: "Reviewer output failed validation: #{reason}",
           findings: [],
           checks: []
         }}
    end
  end

  defp usage_from(review_json) when is_map(review_json) do
    case review_json["usage"] do
      usage when is_map(usage) ->
        %{
          tokens: num(usage["input_tokens"]) + num(usage["output_tokens"]),
          cost_estimate: usage["cost_usd"]
        }

      _ ->
        %{tokens: nil, cost_estimate: nil}
    end
  end

  defp usage_from(_review_json), do: %{tokens: nil, cost_estimate: nil}

  # A not_assessed verdict means the reviewer produced no usable review, so its session is :failed
  # (the review row still exists and blocks the gate). A valid verdict succeeds.
  defp finalize_session!(reviewer_session, review_status, usage) do
    session_status = if review_status == :succeeded, do: :succeeded, else: :failed

    Ash.update!(
      reviewer_session,
      %{
        status: session_status,
        completed_at: DateTime.utc_now(:microsecond),
        tokens: usage.tokens,
        cost_estimate: usage.cost_estimate
      },
      domain: Factory
    )
  end

  defp log_review(run_attempt, reviewer_session, review, usage) do
    Logger.info(
      "RunReviewer complete slice=#{run_attempt.slice_id} actor=#{reviewer_session.id} " <>
        "decision=#{review.decision} findings=#{length(review.findings)} " <>
        "tokens=#{usage.tokens || 0}"
    )
  end

  defp num(value) when is_number(value), do: value
  defp num(_value), do: 0

  # The verdict is stamped with the hash of the rubric it was judged under (m4b2.3). A version
  # with no committed artifact (e.g. a bespoke test rubric) has no hash — nil, not a crash.
  defp rubric_sha256_for(version) do
    Rubric.sha256(version)
  rescue
    File.Error -> nil
  end

  defp create_reviewer_session!(run_attempt, reviewer_profile_id, run_prompt_id, now, opts) do
    Ash.create!(
      AgentSession,
      %{
        run_attempt_id: run_attempt.id,
        run_prompt_id: run_prompt_id,
        agent_profile_id: reviewer_profile_id,
        adapter_session_id: Keyword.get(opts, :adapter_session_id),
        role: :reviewer,
        base_commit: run_attempt.base_commit,
        started_at: now,
        status: :running
      },
      domain: Factory
    )
  end

  defp read_dossier!(run_attempt, opts) do
    artifact =
      Artifact
      |> Ash.read!(domain: Factory)
      |> Enum.find(&(&1.run_attempt_id == run_attempt.id and &1.projection_path == "dossier.md")) ||
        raise ArgumentError, "run attempt #{run_attempt.id} has no dossier.md artifact"

    if artifact.sensitivity in [:sensitive, :quarantined] do
      raise ArgumentError, "dossier.md artifact is #{artifact.sensitivity} and cannot be reviewed"
    end

    blob =
      BlobStore.verify!(artifact.blob_ref, artifact.sha256, artifact.size_bytes,
        blob_root: Keyword.get(opts, :blob_root, ".conveyor/blobs")
      )

    %{content: blob.content, sha256: raw_sha256(blob.sha256)}
  end

  # No default reviewer: an unconfigured review must fail closed (m4b2.1). Silently
  # returning an "accepted" verdict would be the project's #1 anti-pattern — an
  # unmeasured signal laundered into trust. Callers must pass an explicit :reviewer.
  defp configured_reviewer!(opts) do
    case Keyword.get(opts, :reviewer) do
      fun when is_function(fun, 1) ->
        fun

      _unconfigured ->
        Logger.warning(
          "RunReviewer invoked with no :reviewer configured; refusing to produce a review " <>
            "(fail closed — never rubber-stamp an unmeasured accept)."
        )

        raise ArgumentError,
              "RunReviewer requires an explicit :reviewer; refusing to fail open with a rubber-stamp accept"
    end
  end

  defp validate_review(review_json, run_spec, dossier_sha256, reviewer_profile_id) do
    with :ok <- validate_schema(review_json),
         :ok <-
           match_field(
             review_json["run_spec_sha256"],
             raw_sha256(run_spec.run_spec_sha256),
             "run_spec_sha256"
           ),
         :ok <- match_field(review_json["dossier_sha256"], dossier_sha256, "dossier_sha256"),
         :ok <-
           match_field(
             get_in(review_json, ["reviewer", "profile_id"]),
             reviewer_profile_id,
             "reviewer.profile_id"
           ) do
      :ok
    end
  end

  defp validate_schema(review_json) do
    schema = @schema_path |> File.read!() |> Jason.decode!()
    root = JSV.build!(schema, warnings: :silent)

    case JSV.validate(review_json, root) do
      {:ok, _validated} ->
        :ok

      {:error, error} ->
        {:error, "schema validation failed: #{inspect(JSV.normalize_error(error))}"}
    end
  end

  defp match_field(actual, expected, field) do
    if actual == expected, do: :ok, else: {:error, "#{field} does not match"}
  end

  defp get_by_id!(resource, id) do
    resource
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == id)) ||
      raise ArgumentError, "#{inspect(resource)} #{id} was not found"
  end

  defp atom!(value) when is_binary(value), do: String.to_existing_atom(value)
  defp atom!(value) when is_atom(value), do: value

  defp raw_sha256("sha256:" <> digest), do: raw_sha256(digest)
  defp raw_sha256(digest), do: digest
end
