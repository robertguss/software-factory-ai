defmodule Conveyor.Recovery.ReworkContext do
  @moduledoc """
  Bounded, redacted rework artifacts for a retry attempt (rt6k.2): the two things a human would
  demand before re-attempting a failed slice.

    * **Failing-test excerpt** — the failed tests' ids + assertion messages plus a short output
      tail, parsed from the structured verification results (not the whole log).
    * **Prior-diff summary** — what the failed attempt changed: the sorted changed-file list.

  Everything is derived from our own toolchain (trusted findings, not repo prose), passes through
  `Conveyor.Security.Redactor` before it can enter a prompt, and is deterministically truncated to
  a byte budget (head+tail with a marker) so prompt digests stay stable for cassette replay.
  Budgets live in config; truncation is logged.
  """

  require Logger

  alias Conveyor.Security.Redactor

  @default_test_excerpt_bytes 6144
  @default_diff_summary_bytes 4096

  @type meta :: %{optional(String.t()) => term()}

  @spec build(map() | nil, keyword()) :: map()
  def build(output, opts \\ [])

  def build(output, opts) when is_map(output) do
    {excerpt, excerpt_meta} = failing_test_excerpt(output["verification_result"], opts)
    {diff, diff_meta} = prior_diff_summary(changed_files(output), opts)

    Logger.info(
      "Rework context: test_excerpt=#{excerpt_meta["bytes"]}B (truncated=#{excerpt_meta["truncated"]}, " <>
        "redacted=#{excerpt_meta["redacted"]}), prior_diff=#{diff_meta["bytes"]}B " <>
        "(truncated=#{diff_meta["truncated"]})"
    )

    %{
      "failing_test_excerpt" => excerpt,
      "prior_diff_summary" => diff,
      "meta" => %{"test_excerpt" => excerpt_meta, "prior_diff" => diff_meta}
    }
  end

  def build(_output, _opts),
    do: %{"failing_test_excerpt" => "", "prior_diff_summary" => "", "meta" => %{}}

  @spec failing_test_excerpt(map() | nil, keyword()) :: {String.t(), meta()}
  def failing_test_excerpt(verification_result, opts \\ [])

  def failing_test_excerpt(verification_result, opts) when is_map(verification_result) do
    verification_result
    |> failed_tests()
    |> render_failing_tests()
    |> finalize(budget(opts, :test_excerpt_bytes, @default_test_excerpt_bytes))
  end

  def failing_test_excerpt(_verification_result, _opts), do: {"", empty_meta()}

  @spec prior_diff_summary([term()], keyword()) :: {String.t(), meta()}
  def prior_diff_summary(changed_files, opts \\ [])

  def prior_diff_summary(changed_files, opts) when is_list(changed_files) do
    changed_files
    |> render_diff_summary()
    |> finalize(budget(opts, :diff_summary_bytes, @default_diff_summary_bytes))
  end

  def prior_diff_summary(_changed_files, _opts), do: {"", empty_meta()}

  # --- failing-test excerpt ---------------------------------------------------

  defp failed_tests(verification_result) do
    for suite <- list(verification_result["suites"]),
        command <- list(suite["commands"]),
        attempt <- list(command["attempts"]),
        test <- list(attempt["tests"]),
        test["status"] == "failed" do
      %{
        id: test["id"] || test["name"] || "unknown",
        message: test["message"] || "",
        output_tail: tail(command["stdout"] || command["stderr"] || "")
      }
    end
    # Deterministic order → stable prompt digest for cassette replay.
    |> Enum.sort_by(& &1.id)
  end

  defp render_failing_tests([]), do: "Failing tests (0):\n"

  defp render_failing_tests(tests) do
    blocks =
      Enum.map_join(tests, "\n", fn test ->
        "- #{test.id}\n  #{test.message}"
      end)

    tails =
      tests
      |> Enum.map(& &1.output_tail)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()
      |> Enum.join("\n")

    "Failing tests (#{length(tests)}):\n#{blocks}\n\nOutput tail:\n#{tails}"
  end

  # Bounded, deterministic tail of a command's stdout so the excerpt never carries a whole log.
  defp tail(text) when is_binary(text) do
    lines = text |> String.split("\n") |> Enum.take(-20)
    Enum.join(lines, "\n")
  end

  # --- prior-diff summary -----------------------------------------------------

  defp render_diff_summary([]), do: "Changed files (0):\n"

  defp render_diff_summary(changed_files) do
    rows =
      changed_files
      |> Enum.map(&file_row/1)
      |> Enum.sort()
      |> Enum.map_join("\n", &("- " <> &1))

    "Changed files (#{length(changed_files)}):\n#{rows}"
  end

  defp file_row(path) when is_binary(path), do: path

  defp file_row(%{} = file) do
    path = file["path"] || file[:path] || "unknown"
    add = file["additions"] || file[:additions]
    del = file["deletions"] || file[:deletions]

    if is_integer(add) or is_integer(del) do
      "#{path} (+#{add || 0} -#{del || 0})"
    else
      path
    end
  end

  # --- shared: redact → deterministic truncate --------------------------------

  # Redact BEFORE truncation so a secret can never survive by being on the truncation boundary.
  defp finalize(content, budget) do
    result = Redactor.redact!(content, source: "rework_context")
    {truncated, truncated?} = truncate(result.content, budget)

    meta = %{
      "bytes" => byte_size(truncated),
      "truncated" => truncated?,
      "redacted" => result.findings != []
    }

    {truncated, meta}
  end

  defp truncate(content, budget) when byte_size(content) <= budget, do: {content, false}

  defp truncate(content, budget) do
    marker = "\n...[truncated]...\n"
    keep = max(budget - byte_size(marker), 0)
    half = div(keep, 2)
    head = content |> binary_part(0, half) |> valid_prefix()
    tail = content |> binary_part(byte_size(content) - half, half) |> valid_suffix()
    {head <> marker <> tail, true}
  end

  # Trim a byte slice back to a valid UTF-8 boundary (a byte budget can split a codepoint).
  defp valid_prefix(<<>>), do: <<>>

  defp valid_prefix(bin) do
    if String.valid?(bin), do: bin, else: valid_prefix(binary_part(bin, 0, byte_size(bin) - 1))
  end

  defp valid_suffix(<<>>), do: <<>>

  defp valid_suffix(bin) do
    if String.valid?(bin), do: bin, else: valid_suffix(binary_part(bin, 1, byte_size(bin) - 1))
  end

  # --- helpers ----------------------------------------------------------------

  defp changed_files(output) do
    patch_set = output["patch_set"]

    cond do
      is_list(output["changed_files"]) -> output["changed_files"]
      is_map(patch_set) and is_list(patch_set["changed_files"]) -> patch_set["changed_files"]
      true -> []
    end
  end

  defp list(value) when is_list(value), do: value
  defp list(_value), do: []

  defp empty_meta, do: %{"bytes" => 0, "truncated" => false, "redacted" => false}

  defp budget(opts, key, default) do
    Keyword.get(opts, key) || Application.get_env(:conveyor, __MODULE__, [])[key] || default
  end
end
