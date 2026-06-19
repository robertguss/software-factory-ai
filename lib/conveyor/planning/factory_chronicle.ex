defmodule Conveyor.Planning.FactoryChronicle do
  @moduledoc """
  Deterministic Factory Chronicle and approval-summary projection.
  """

  @schema_version "conveyor.factory_chronicle@1"
  @projection_path "factory_chronicle.md"
  @limitations_banner "**What Conveyor did not evaluate:** this package demonstrates faithful compilation of the approved plan, declared constraints, and verification obligations. It does not establish that the plan is the right product, architecture, or business decision."

  @spec build(map()) :: map()
  def build(input) when is_map(input) do
    canonical = canonical_facts(input)
    markdown = markdown(canonical)

    %{
      "schema_version" => @schema_version,
      "projection_path" => @projection_path,
      "status" => canonical["status"],
      "approval_summary" => approval_summary(canonical),
      "canonical_blockers" => canonical["canonical_blockers"],
      "limitations_banner" => @limitations_banner,
      "canonical_facts" => canonical,
      "markdown" => markdown,
      "markdown_sha256" => digest(markdown)
    }
  end

  defp canonical_facts(input) do
    blockers = blockers(input)

    %{
      "status" => if(blockers == [], do: "passed", else: "blocked"),
      "human_request" => value(input, :human_request),
      "explicit_facts" => facts(input, :explicit_facts),
      "observed_facts" => facts(input, :observed_facts),
      "derived_facts" => facts(input, :derived_facts),
      "inferred_facts" => facts(input, :inferred_facts),
      "decomposition_selection" => value(input, :decomposition_selection),
      "rejected_alternatives" => sorted_strings(input, :rejected_alternatives),
      "contracts" => sorted_strings(input, :contracts),
      "obligations" => sorted_strings(input, :obligations),
      "evidence_refs" => sorted_strings(input, :evidence_refs),
      "uncertainties" => sorted_strings(input, :uncertainties),
      "changed_refs" => sorted_strings(input, :changed_refs),
      "invalidated_refs" => sorted_strings(input, :invalidated_refs),
      "canonical_blockers" => blockers,
      "next_safe_step" => value(input, :next_safe_step),
      "source_summary" => value(input, :source_summary)
    }
  end

  defp approval_summary(canonical) do
    %{
      "status" => canonical["status"],
      "canonical_blocker_count" => length(canonical["canonical_blockers"]),
      "summary_canary" =>
        if(canonical["canonical_blockers"] == [],
          do: "no_canonical_blockers",
          else: "canonical_blockers_visible"
        ),
      "next_safe_step" => canonical["next_safe_step"],
      "limitations_banner" => @limitations_banner
    }
  end

  defp markdown(canonical) do
    [
      "# Factory Chronicle",
      "",
      "Status: #{canonical["status"]}",
      "",
      "## Human asked for",
      canonical["human_request"],
      "",
      section("Explicit Facts", canonical["explicit_facts"], &fact_line/1),
      section("Observed Facts", canonical["observed_facts"], &fact_line/1),
      section("Derived Facts", canonical["derived_facts"], &fact_line/1),
      section("Inferred Facts", canonical["inferred_facts"], &fact_line/1),
      "## Decomposition Selection",
      canonical["decomposition_selection"],
      "",
      section("Rejected Alternatives", canonical["rejected_alternatives"], &string_line/1),
      section("Contracts", canonical["contracts"], &string_line/1),
      section("Obligations", canonical["obligations"], &string_line/1),
      section("Evidence", canonical["evidence_refs"], &string_line/1),
      section("Uncertain Or Human-Only", canonical["uncertainties"], &string_line/1),
      section("Changed", canonical["changed_refs"], &string_line/1),
      section("Invalidated", canonical["invalidated_refs"], &string_line/1),
      section("Canonical Blockers", canonical["canonical_blockers"], &blocker_line/1),
      "## Next Safe Operational Step",
      canonical["next_safe_step"],
      "",
      "## Limitations",
      @limitations_banner,
      ""
    ]
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp section(title, values, line_fun) do
    ["## #{title}", Enum.map(values, line_fun), ""]
  end

  defp fact_line(fact), do: "- #{fact["kind"]}: #{fact["text"]}"
  defp string_line(value), do: "- #{value}"

  defp blocker_line(blocker) do
    "- #{blocker["blocker_id"]} (#{blocker["source"]}): #{blocker["reason"]}"
  end

  defp facts(input, key) do
    input
    |> list(key)
    |> Enum.map(fn fact ->
      %{
        "kind" => value(fact, :kind),
        "text" => value(fact, :text)
      }
    end)
    |> Enum.sort_by(fn fact -> {fact["kind"], fact["text"]} end)
  end

  defp blockers(input) do
    input
    |> canonical_blockers()
    |> Enum.map(fn blocker ->
      %{
        "blocker_id" => value(blocker, :blocker_id),
        "source" => value(blocker, :source),
        "reason" => value(blocker, :reason)
      }
    end)
    |> Enum.sort_by(fn blocker ->
      {blocker["blocker_id"], blocker["source"], blocker["reason"]}
    end)
  end

  # The completeness canary must fail wide: a present-but-malformed (non-list) canonical_blockers
  # must surface a blocker, never be silently coerced to "no blockers" (which would let the
  # chronicle render status "passed" while a real blocker exists).
  defp canonical_blockers(input) do
    case value(input, :canonical_blockers, []) do
      blockers when is_list(blockers) ->
        blockers

      nil ->
        []

      _malformed ->
        [
          %{
            "blocker_id" => "MALFORMED_BLOCKERS",
            "source" => "factory_chronicle",
            "reason" => "canonical_blockers was not a list"
          }
        ]
    end
  end

  defp sorted_strings(input, key) do
    input
    |> list(key)
    |> Enum.map(&to_string/1)
    |> Enum.sort()
  end

  defp list(map, key) do
    case value(map, key, []) do
      values when is_list(values) -> values
      _other -> []
    end
  end

  defp digest(value) do
    "sha256:" <> (:crypto.hash(:sha256, value) |> Base.encode16(case: :lower))
  end

  defp value(map, key, default \\ nil) do
    Map.get(map, key, Map.get(map, to_string(key), default))
  end
end
