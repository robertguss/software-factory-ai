defmodule Conveyor.NegotiatedScope.ScopeAmendment do
  @moduledoc """
  nyrl.2: executes a GRANTED scope amendment as ADR-20 contract evolution.

  It mints a NEW widened `DiffPolicy` version (never mutating the prior row in place), moves the
  slice's scope pointers (`diff_policy_id` + `likely_files`) to it, and records an auditable ledger
  trail — the prior/amended `diff_policy_sha256` chain, the granted paths, and the agent's rationale.
  The caller then re-runs the attempt under the widened scope. The authority decision was already
  made by `ScopeAmendmentEvaluator`; this only executes a grant, so it never re-checks bounds.
  """

  alias Conveyor.Factory
  alias Conveyor.Factory.DiffPolicy
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.Slice
  alias Conveyor.Ledger
  alias Conveyor.Planning.RunSpecAssembler
  alias Conveyor.Planning.ScopeCap

  @doc """
  Apply a granted amendment: mint the widened policy, move the slice pointers, record the trail.
  Returns the amended `diff_policy_sha256` (thread it into the forged retry RunSpec).
  """
  @spec apply_grant!(RunAttempt.t(), DiffPolicy.t(), map(), keyword()) :: String.t()
  def apply_grant!(%RunAttempt{} = prior_attempt, %DiffPolicy{} = prior_policy, grant, opts \\ []) do
    actor = Keyword.get(opts, :actor, "scope-amendment")
    new_policy = mint_widened_policy!(prior_policy, grant.allowed_path_globs)
    move_scope_pointers!(prior_policy.slice_id, new_policy, grant.added_globs)
    record_trail!(prior_attempt, prior_policy, new_policy, grant, actor)
    RunSpecAssembler.diff_policy_sha256(new_policy)
  end

  @doc "Mint a NEW DiffPolicy row with the widened allow-list (ADR-20 — never mutate the prior row)."
  @spec mint_widened_policy!(DiffPolicy.t(), [String.t()]) :: DiffPolicy.t()
  def mint_widened_policy!(%DiffPolicy{} = prior, widened_allowed_globs) do
    Ash.create!(
      DiffPolicy,
      %{
        slice_id: prior.slice_id,
        allowed_path_globs: widened_allowed_globs,
        protected_path_globs: prior.protected_path_globs,
        always_allowed_path_classes: prior.always_allowed_path_classes,
        max_files_changed: ScopeCap.max_files_changed(length(widened_allowed_globs)),
        max_lines_added: prior.max_lines_added,
        max_lines_deleted: prior.max_lines_deleted,
        dependency_changes_allowed: prior.dependency_changes_allowed,
        migrations_allowed: prior.migrations_allowed,
        generated_files_allowed: prior.generated_files_allowed,
        public_api_changes_allowed: prior.public_api_changes_allowed,
        notes: "Widened by a granted scope amendment (nyrl.2)."
      },
      domain: Factory
    )
  end

  # The DiffPolicy row is immutable (a new version was minted); only the slice POINTERS move to it.
  defp move_scope_pointers!(slice_id, new_policy, added_globs) do
    slice = Ash.get!(Slice, slice_id, domain: Factory)

    Ash.update!(
      slice,
      %{
        diff_policy_id: new_policy.id,
        likely_files: Enum.uniq((slice.likely_files || []) ++ added_globs)
      },
      domain: Factory
    )
  end

  defp record_trail!(prior_attempt, prior_policy, new_policy, grant, actor) do
    Ledger.write!(%{
      project_id: project_id_for(prior_attempt.slice_id),
      slice_id: prior_attempt.slice_id,
      run_attempt_id: prior_attempt.id,
      idempotency_key: "scope.amendment_granted:#{prior_attempt.id}",
      type: "scope.amendment_granted",
      payload: %{
        "actor" => actor,
        "prior_diff_policy_sha256" => RunSpecAssembler.diff_policy_sha256(prior_policy),
        "amended_diff_policy_sha256" => RunSpecAssembler.diff_policy_sha256(new_policy),
        "granted_paths" => grant.added_globs,
        "rationale" => grant.rationale
      }
    })
  end

  defp project_id_for(slice_id) do
    slice = Ash.get!(Slice, slice_id, domain: Factory)
    epic = Ash.get!(Epic, slice.epic_id, domain: Factory)
    plan = Ash.get!(Plan, epic.plan_id, domain: Factory)
    plan.project_id
  end
end
