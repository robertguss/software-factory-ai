defmodule Conveyor.TestArchitect.Artifacts do
  @moduledoc """
  Schema-shaped Test Architect artifact builders.

  TestSpecifications, TestPack patches, and challenge cases are proposals and
  evidence producers. They map tests to obligations and acceptance criteria but
  do not grant contract-lock or implementation authority.
  """

  @test_roles ~w(acceptance_new bug_reproduction regression_preservation characterization property interface_contract security_policy human_verification)
  @outcomes ~w(pass fail not_applicable)
  @base_expectations ~w(pass fail_expected_reason differential not_applicable)
  @patch_modes ~w(create modify delete)

  @spec build!(map()) :: %{
          test_specifications: [map()],
          test_pack_patch: map(),
          challenge_cases: [map()]
        }
  def build!(input) when is_map(input) do
    normalized = stringify_map(input)
    slice_id = required_string(normalized, "slice_id")

    test_specifications =
      normalized
      |> required_list("test_specs")
      |> Enum.map(&new_test_specification!(Map.put(&1, "slice_id", slice_id)))

    test_pack_patch =
      new_test_pack_patch!(%{
        "slice_id" => slice_id,
        "agent_brief_contract_id" => required_string(normalized, "agent_brief_contract_id"),
        "test_pack_id" => required_string(normalized, "test_pack_id"),
        "workspace_contract_id" => required_string(normalized, "workspace_contract_id"),
        "test_specification_ids" => Enum.map(test_specifications, &Map.fetch!(&1, "id")),
        "patch_files" => required_list(normalized, "patch_files"),
        "environment_policy" => required_map(normalized, "environment_policy"),
        "nondeterminism_policy" => required_map(normalized, "nondeterminism_policy"),
        "result_adapters" =>
          test_specifications
          |> Enum.map(&Map.fetch!(&1, "result_adapter"))
          |> Enum.uniq()
      })

    challenge_cases =
      normalized
      |> Map.get("challenge_cases", [])
      |> Enum.map(&new_challenge_case!(Map.put(&1, "slice_id", slice_id)))

    %{
      test_specifications: test_specifications,
      test_pack_patch: test_pack_patch,
      challenge_cases: challenge_cases
    }
  end

  @spec new_test_specification!(map()) :: map()
  def new_test_specification!(attrs) when is_map(attrs) do
    normalized = stringify_map(attrs)

    spec =
      %{
        "schema_version" => "conveyor.test_specification@1",
        "slice_id" => required_string(normalized, "slice_id"),
        "test_id" => required_string(normalized, "test_id"),
        "role" => required_enum(normalized, "role", @test_roles),
        "verification_obligation_refs" =>
          required_non_empty_string_list(normalized, "verification_obligation_refs"),
        "acceptance_refs" => required_non_empty_string_list(normalized, "acceptance_refs"),
        "interface_refs" => optional_string_list(normalized, "interface_refs"),
        "expected_on_base" => required_enum(normalized, "expected_on_base", @outcomes),
        "base_calibration_expectation" =>
          required_enum(normalized, "base_calibration_expectation", @base_expectations),
        "expected_base_reason" => required_string(normalized, "expected_base_reason"),
        "expected_on_candidate" => required_enum(normalized, "expected_on_candidate", @outcomes),
        "failure_signature_policy" => required_string(normalized, "failure_signature_policy"),
        "compiler_falsifier_seed_refs" =>
          optional_string_list(normalized, "compiler_falsifier_seed_refs"),
        "hermeticity_requirements" =>
          optional_string_list(normalized, "hermeticity_requirements"),
        "environment_requirements" =>
          optional_string_list(normalized, "environment_requirements"),
        "hidden_from_implementer" =>
          optional_boolean(normalized, "hidden_from_implementer", false),
        "result_adapter" => required_string(normalized, "result_adapter"),
        "claim_refs" => optional_string_list(normalized, "claim_refs")
      }

    digest = digest(spec)

    spec
    |> Map.put("test_specification_digest", "sha256:#{digest}")
    |> Map.put("id", "test_specification:sha256:#{digest}")
  end

  @spec new_test_pack_patch!(map()) :: map()
  def new_test_pack_patch!(attrs) when is_map(attrs) do
    normalized = stringify_map(attrs)

    patch =
      %{
        "schema_version" => "conveyor.test_pack_patch@1",
        "slice_id" => required_string(normalized, "slice_id"),
        "test_pack_id" => required_string(normalized, "test_pack_id"),
        "agent_brief_contract_id" => required_string(normalized, "agent_brief_contract_id"),
        "workspace_contract_id" => required_string(normalized, "workspace_contract_id"),
        "test_specification_ids" =>
          required_non_empty_string_list(normalized, "test_specification_ids"),
        "patch_files" =>
          normalized
          |> required_list("patch_files")
          |> Enum.map(&patch_file!/1),
        "environment_policy" => required_map(normalized, "environment_policy"),
        "nondeterminism_policy" => required_map(normalized, "nondeterminism_policy"),
        "result_adapters" => required_non_empty_string_list(normalized, "result_adapters")
      }

    digest = digest(patch)

    patch
    |> Map.put("test_pack_patch_digest", "sha256:#{digest}")
    |> Map.put("id", "test_pack_patch:sha256:#{digest}")
  end

  @spec new_challenge_case!(map()) :: map()
  def new_challenge_case!(attrs) when is_map(attrs) do
    normalized = stringify_map(attrs)

    challenge =
      %{
        "schema_version" => "conveyor.challenge_case@1",
        "slice_id" => required_string(normalized, "slice_id"),
        "challenge_id" => required_string(normalized, "challenge_id"),
        "verification_obligation_refs" =>
          required_non_empty_string_list(normalized, "verification_obligation_refs"),
        "acceptance_refs" => required_non_empty_string_list(normalized, "acceptance_refs"),
        "compiler_falsifier_seed_refs" =>
          optional_string_list(normalized, "compiler_falsifier_seed_refs"),
        "hidden_from_implementer" => required_boolean(normalized, "hidden_from_implementer"),
        "expected_on_candidate" => required_enum(normalized, "expected_on_candidate", @outcomes),
        "reason" => required_string(normalized, "reason")
      }

    digest = digest(challenge)

    challenge
    |> Map.put("challenge_case_digest", "sha256:#{digest}")
    |> Map.put("id", "challenge_case:sha256:#{digest}")
  end

  defp patch_file!(attrs) when is_map(attrs) do
    normalized = stringify_map(attrs)

    %{
      "path" => required_relative_path(normalized, "path"),
      "mode" => required_enum(normalized, "mode", @patch_modes),
      "content_digest" => required_string(normalized, "content_digest")
    }
  end

  defp required_relative_path(map, key) do
    path = required_string(map, key)

    if Path.type(path) == :relative and not String.contains?(path, "..") do
      path
    else
      raise ArgumentError, "#{key} must be a relative path inside the test workspace"
    end
  end

  defp required_enum(map, key, allowed) do
    value = required_string(map, key)

    if value in allowed do
      value
    else
      raise ArgumentError, "#{key} must be one of #{Enum.join(allowed, ", ")}"
    end
  end

  defp required_non_empty_string_list(map, key) do
    case optional_string_list(map, key) do
      [] -> raise ArgumentError, "#{key} must not be empty"
      values -> values
    end
  end

  defp optional_string_list(map, key) do
    case Map.get(map, key, []) do
      values when is_list(values) and values != [] ->
        if Enum.all?(values, &(is_binary(&1) and &1 != "")) do
          values
        else
          raise ArgumentError, "#{key} must contain only non-empty strings"
        end

      [] ->
        []

      _other ->
        raise ArgumentError, "#{key} must be a list"
    end
  end

  defp required_list(map, key) do
    case Map.fetch!(map, key) do
      values when is_list(values) and values != [] -> values
      [] -> raise ArgumentError, "#{key} must not be empty"
      _other -> raise ArgumentError, "#{key} must be a list"
    end
  end

  defp required_map(map, key) do
    case Map.fetch!(map, key) do
      value when is_map(value) -> stringify_map(value)
      _other -> raise ArgumentError, "#{key} must be a map"
    end
  end

  defp required_string(map, key) do
    case Map.fetch!(map, key) do
      value when is_binary(value) and value != "" -> value
      _other -> raise ArgumentError, "#{key} must be a non-empty string"
    end
  end

  defp required_boolean(map, key) do
    case Map.fetch!(map, key) do
      value when is_boolean(value) -> value
      _other -> raise ArgumentError, "#{key} must be a boolean"
    end
  end

  defp optional_boolean(map, key, default) do
    case Map.get(map, key, default) do
      value when is_boolean(value) -> value
      _other -> raise ArgumentError, "#{key} must be a boolean"
    end
  end

  defp digest(value) do
    value
    |> canonical_term()
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp canonical_term(value) when is_map(value) do
    value
    |> stringify_map()
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.map(fn {key, value} -> [key, canonical_term(value)] end)
  end

  defp canonical_term(values) when is_list(values), do: Enum.map(values, &canonical_term/1)
  defp canonical_term(value), do: value

  defp stringify_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), stringify_value(value)} end)
  end

  defp stringify_value(value) when is_map(value), do: stringify_map(value)
  defp stringify_value(values) when is_list(values), do: Enum.map(values, &stringify_value/1)
  defp stringify_value(value) when is_boolean(value), do: value
  defp stringify_value(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify_value(value), do: value
end
