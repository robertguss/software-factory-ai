defmodule Conveyor.Factory.Validations.ReviewerActorSeparation do
  @moduledoc false

  use Ash.Resource.Validation

  alias Ash.Error.Changes.InvalidAttribute
  alias Conveyor.Factory
  alias Conveyor.Factory.AgentSession

  @impl true
  def validate(changeset, _opts, _context) do
    run_attempt_id = Ash.Changeset.get_attribute(changeset, :run_attempt_id)
    reviewer_profile_id = Ash.Changeset.get_attribute(changeset, :reviewer_profile_id)
    reviewer_session_id = Ash.Changeset.get_attribute(changeset, :reviewer_session_id)

    case check(run_attempt_id, reviewer_profile_id, reviewer_session_id) do
      :ok ->
        :ok

      {:error, message} ->
        {:error, InvalidAttribute.exception(field: :reviewer_profile_id, message: message)}
    end
  end

  @spec check(String.t() | nil, String.t() | nil, String.t() | nil) :: :ok | {:error, String.t()}
  def check(nil, _reviewer_profile_id, _reviewer_session_id), do: :ok
  def check(_run_attempt_id, nil, _reviewer_session_id), do: :ok

  def check(run_attempt_id, reviewer_profile_id, reviewer_session_id) do
    sessions = sessions_for_run(run_attempt_id)
    reviewer_session = Enum.find(sessions, &(&1.id == reviewer_session_id))
    implementer_sessions = Enum.filter(sessions, &(&1.role == :implementer))

    with :ok <- require_reviewer_session_exists(reviewer_session_id, reviewer_session),
         :ok <- require_reviewer_role(reviewer_session),
         :ok <- require_matching_profile(reviewer_session, reviewer_profile_id),
         :ok <- require_distinct_profile(implementer_sessions, reviewer_profile_id),
         :ok <- require_distinct_adapter_session(reviewer_session, implementer_sessions) do
      :ok
    end
  end

  defp require_reviewer_session_exists(nil, _reviewer_session), do: :ok
  defp require_reviewer_session_exists(_reviewer_session_id, %AgentSession{}), do: :ok

  defp require_reviewer_session_exists(_reviewer_session_id, nil) do
    {:error, "reviewer_session_id must reference a session on the same run attempt"}
  end

  defp require_reviewer_role(nil), do: :ok
  defp require_reviewer_role(%{role: :reviewer}), do: :ok

  defp require_reviewer_role(_reviewer_session) do
    {:error, "reviewer_session_id must reference a reviewer session"}
  end

  defp require_matching_profile(nil, _reviewer_profile_id), do: :ok

  defp require_matching_profile(%{agent_profile_id: reviewer_profile_id}, reviewer_profile_id),
    do: :ok

  defp require_matching_profile(_reviewer_session, _reviewer_profile_id) do
    {:error, "reviewer_profile_id must match the reviewer session profile"}
  end

  defp require_distinct_profile(implementer_sessions, reviewer_profile_id) do
    if Enum.any?(implementer_sessions, &(&1.agent_profile_id == reviewer_profile_id)) do
      {:error, "reviewer profile must differ from every implementer profile on the run"}
    else
      :ok
    end
  end

  defp require_distinct_adapter_session(nil, _implementer_sessions), do: :ok

  defp require_distinct_adapter_session(reviewer_session, implementer_sessions) do
    if shared_adapter_session?(reviewer_session, implementer_sessions) do
      {:error,
       "reviewer adapter session must differ from every implementer adapter session on the run"}
    else
      :ok
    end
  end

  defp sessions_for_run(run_attempt_id) do
    AgentSession
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.run_attempt_id == run_attempt_id))
  end

  defp shared_adapter_session?(reviewer_session, implementer_sessions) do
    reviewer_session.adapter_session_id not in [nil, ""] and
      Enum.any?(
        implementer_sessions,
        &(&1.adapter_session_id == reviewer_session.adapter_session_id)
      )
  end
end
