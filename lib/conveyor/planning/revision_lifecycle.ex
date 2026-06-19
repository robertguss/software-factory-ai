defmodule Conveyor.Planning.RevisionLifecycle do
  @moduledoc """
  Pure lifecycle model for imported plan bytes, draft checkpoints, and published revisions.
  """

  defstruct plan_id: nil,
            source_snapshots: [],
            draft_checkpoints: [],
            plan_revisions: []

  @type t :: %__MODULE__{}

  @spec new(String.t()) :: t()
  def new(plan_id), do: %__MODULE__{plan_id: plan_id}

  @spec import_source!(t(), binary(), keyword()) :: t()
  def import_source!(%__MODULE__{} = state, source_bytes, opts) when is_binary(source_bytes) do
    snapshot_no = length(state.source_snapshots) + 1

    snapshot = %{
      snapshot_id: "plan-source-snapshot:#{state.plan_id}:#{snapshot_no}",
      snapshot_no: snapshot_no,
      plan_id: state.plan_id,
      source_document_ref: Keyword.get(opts, :source_document_ref, "inline"),
      source_content_digest: digest(source_bytes),
      imported_by: Keyword.fetch!(opts, :actor),
      imported_at: Keyword.get_lazy(opts, :at, &DateTime.utc_now/0)
    }

    %{state | source_snapshots: state.source_snapshots ++ [snapshot]}
  end

  @spec save_draft_checkpoint!(t(), binary(), keyword()) :: t()
  def save_draft_checkpoint!(%__MODULE__{} = state, draft_bytes, opts)
      when is_binary(draft_bytes) do
    checkpoint_no = length(state.draft_checkpoints) + 1

    checkpoint = %{
      checkpoint_id: "plan-draft-checkpoint:#{state.plan_id}:#{checkpoint_no}",
      checkpoint_no: checkpoint_no,
      plan_id: state.plan_id,
      draft_digest: digest(draft_bytes),
      saved_by: Keyword.fetch!(opts, :actor),
      saved_at: Keyword.get_lazy(opts, :at, &DateTime.utc_now/0)
    }

    %{state | draft_checkpoints: state.draft_checkpoints ++ [checkpoint]}
  end

  @spec publish_revision!(t(), map(), keyword()) :: t()
  def publish_revision!(%__MODULE__{} = state, normalized_contract, opts)
      when is_map(normalized_contract) do
    revision_no = length(state.plan_revisions) + 1

    revision = %{
      revision_id: "plan-revision:#{state.plan_id}:#{revision_no}",
      revision_no: revision_no,
      plan_id: state.plan_id,
      source_snapshot_ids: Enum.map(state.source_snapshots, & &1.snapshot_id),
      normalized_contract: normalized_contract,
      contract_digest: digest(canonical_json(normalized_contract)),
      status: :published,
      created_by: Keyword.fetch!(opts, :actor),
      created_at: Keyword.get_lazy(opts, :at, &DateTime.utc_now/0)
    }

    %{state | plan_revisions: state.plan_revisions ++ [revision]}
  end

  @spec update_revision!(t(), String.t(), map()) :: no_return()
  def update_revision!(%__MODULE__{} = state, revision_id, _attrs) do
    revision = Enum.find(state.plan_revisions, &(&1.revision_id == revision_id))

    if revision && revision.status == :published do
      raise ArgumentError, "published PlanRevision is immutable"
    else
      raise ArgumentError, "unknown PlanRevision"
    end
  end

  defp digest(content) when is_binary(content) do
    "sha256:" <> Base.encode16(:crypto.hash(:sha256, content), case: :lower)
  end

  defp canonical_json(value) when is_map(value) do
    entries =
      value
      |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
      |> Enum.map(fn {key, nested} ->
        Jason.encode!(to_string(key)) <> ":" <> canonical_json(nested)
      end)

    "{" <> Enum.join(entries, ",") <> "}"
  end

  defp canonical_json(value) when is_list(value),
    do: "[" <> Enum.map_join(value, ",", &canonical_json/1) <> "]"

  defp canonical_json(value), do: Jason.encode!(value)
end
