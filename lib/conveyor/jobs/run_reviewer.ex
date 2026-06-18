defmodule Conveyor.Jobs.RunReviewer do
  @moduledoc """
  Runs an independent reviewer over the recorded run dossier.

  The reviewer context is intentionally limited to the projected dossier bytes
  and digest metadata. Live implementer-session narration is not passed through
  this boundary.
  """

  use Oban.Worker, queue: :gate, max_attempts: 1

  alias Conveyor.Artifacts.BlobStore
  alias Conveyor.Factory
  alias Conveyor.Factory.AgentSession
  alias Conveyor.Factory.Artifact
  alias Conveyor.Factory.Review
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Factory.Validations.ReviewerActorSeparation

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
  @schema_version "conveyor.review@1"
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
    dossier = read_dossier!(run_attempt, opts)
    now = DateTime.utc_now(:microsecond)

    case ReviewerActorSeparation.check(run_attempt.id, reviewer_profile_id, nil) do
      :ok -> :ok
      {:error, message} -> raise ArgumentError, message
    end

    reviewer_session =
      create_reviewer_session!(run_attempt, reviewer_profile_id, run_prompt_id, now, opts)

    try do
      review_json =
        reviewer!(opts).(%{
          dossier: dossier.content,
          dossier_sha256: dossier.sha256,
          run_attempt: run_attempt,
          run_spec: run_spec,
          reviewer_profile_id: reviewer_profile_id,
          reviewer_session_id: reviewer_session.id,
          rubric_version: rubric_version
        })

      validate_review_json!(review_json, run_spec, dossier.sha256, reviewer_profile_id)

      review =
        Ash.create!(
          Review,
          %{
            run_attempt_id: run_attempt.id,
            reviewer_session_id: reviewer_session.id,
            reviewer_profile_id: reviewer_profile_id,
            review_kind: Keyword.get(opts, :review_kind, :general),
            rubric_version: review_json["rubric_version"],
            dossier_sha256: dossier.sha256,
            reviewed_at: now,
            decision: atom!(review_json["decision"]),
            recommendation: atom!(review_json["recommendation"]),
            summary: review_json["summary"],
            findings: review_json["findings"],
            checks: review_json["checks"]
          },
          domain: Factory
        )

      reviewer_session =
        Ash.update!(
          reviewer_session,
          %{status: :succeeded, completed_at: DateTime.utc_now(:microsecond)},
          domain: Factory
        )

      %Result{review: review, reviewer_session: reviewer_session, review_json: review_json}
    rescue
      error ->
        Ash.update!(
          reviewer_session,
          %{status: :failed, completed_at: DateTime.utc_now(:microsecond)},
          domain: Factory
        )

        reraise error, __STACKTRACE__
    end
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

  defp reviewer!(opts), do: Keyword.get(opts, :reviewer, &default_review/1)

  defp default_review(context) do
    %{
      "schema_version" => @schema_version,
      "run_spec_sha256" => raw_sha256(context.run_spec.run_spec_sha256),
      "dossier_sha256" => context.dossier_sha256,
      "reviewer" => %{
        "actor_id" => context.reviewer_session_id,
        "profile_id" => context.reviewer_profile_id
      },
      "rubric_version" => context.rubric_version,
      "decision" => "accepted",
      "recommendation" => "merge",
      "summary" => "Recorded dossier evidence is present for independent review.",
      "findings" => [],
      "checks" => [
        %{
          "name" => "dossier_digest",
          "status" => "pass",
          "evidence_refs" => ["dossier.md"],
          "summary" => "Dossier bytes matched the recorded digest."
        }
      ]
    }
  end

  defp validate_review_json!(review_json, run_spec, dossier_sha256, reviewer_profile_id) do
    schema = @schema_path |> File.read!() |> Jason.decode!()
    root = JSV.build!(schema, warnings: :silent)

    case JSV.validate(review_json, root) do
      {:ok, _validated} ->
        :ok

      {:error, validation_error} ->
        raise ArgumentError,
              "review JSON failed schema validation: #{inspect(JSV.normalize_error(validation_error))}"
    end

    expected_run_spec_sha256 = raw_sha256(run_spec.run_spec_sha256)

    unless review_json["run_spec_sha256"] == expected_run_spec_sha256 do
      raise ArgumentError, "review run_spec_sha256 does not match RunSpec"
    end

    unless review_json["dossier_sha256"] == dossier_sha256 do
      raise ArgumentError, "review dossier_sha256 does not match dossier artifact"
    end

    unless get_in(review_json, ["reviewer", "profile_id"]) == reviewer_profile_id do
      raise ArgumentError, "review reviewer.profile_id does not match reviewer session profile"
    end
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
