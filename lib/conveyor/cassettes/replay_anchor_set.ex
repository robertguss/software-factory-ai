defmodule Conveyor.Cassettes.ReplayAnchorSet do
  @moduledoc """
  Selects representative replay anchors before an evaluated change.
  """

  @categories ~w(successful failed disputed safety_sensitive)

  @spec build!([map()], keyword()) :: map()
  def build!(recordings, opts) when is_list(recordings) and is_list(opts) do
    anchors = Enum.map(@categories, &anchor_for!(recordings, &1, opts))

    anchor_set = %{
      "schema_version" => "conveyor.replay_anchor_set@1",
      "selection_policy_digest" => Keyword.fetch!(opts, :policy_digest),
      "selected_before_change_ref" => Keyword.fetch!(opts, :selected_before_change_ref),
      "anchors" => anchors,
      "replay_anchor_set_digest" => nil
    }

    %{anchor_set | "replay_anchor_set_digest" => digest(anchor_set)}
  end

  defp anchor_for!(recordings, category, opts) do
    recording =
      Enum.find(recordings, &(value(&1, :category) == category)) ||
        raise ArgumentError, "missing replay anchor category #{category}"

    %{
      "category" => category,
      "cassette_ref" => value(recording, :cassette_ref),
      "valuable_failure" => value(recording, :valuable_failure) == true,
      "expected_replay_assertions" =>
        List.wrap(value(recording, :expected_replay_assertions)) ++
          Keyword.get(opts, :expected_assertions, [])
    }
    |> Map.update!("expected_replay_assertions", &Enum.uniq/1)
  end

  defp digest(anchor_set) do
    anchor_set
    |> Map.delete("replay_anchor_set_digest")
    |> canonical()
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> then(&"sha256:#{&1}")
  end

  defp canonical(map) when is_map(map) do
    map
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
    |> Map.new(fn {key, value} -> {key, canonical(value)} end)
  end

  defp canonical(values) when is_list(values), do: Enum.map(values, &canonical/1)
  defp canonical(value), do: value

  defp value(map, key), do: Map.get(map, key) || Map.get(map, to_string(key))
end
