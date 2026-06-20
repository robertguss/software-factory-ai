defmodule Conveyor.Gate.Stages.ContractLock do
  @moduledoc """
  Gate stage 9: verifies the run still matches the approved contract lock.
  """

  @behaviour Conveyor.Gate.Stage

  alias Conveyor.ContractEvolution
  alias Conveyor.Gate.StageResult

  @impl true
  def run(context, _opts \\ []) do
    contract_lock = value(context, :contract_lock)
    findings = findings(contract_lock, context)

    %StageResult{
      key: "contract_lock",
      status: status(findings),
      required?: true,
      findings: findings,
      evidence_refs: evidence_refs(context),
      input_digests: input_digests(contract_lock, context)
    }
  end

  defp findings(nil, _context) do
    [finding("missing_contract_lock", "ContractLock is required for the gate.")]
  end

  defp findings(contract_lock, context) do
    []
    |> Kernel.++(brief_findings(contract_lock, value(context, :agent_brief)))
    |> Kernel.++(test_pack_findings(contract_lock, value(context, :test_pack)))
    |> Kernel.++(run_spec_findings(contract_lock, value(context, :run_spec)))
    |> Kernel.++(protected_path_findings(contract_lock, value(context, :patch_set)))
    |> Kernel.++(
      mount_findings(value(context, :test_pack), value(context, :test_pack_mount_mode))
    )
  end

  defp brief_findings(_contract_lock, nil),
    do: [finding("missing_agent_brief", "AgentBrief is required.")]

  defp brief_findings(contract_lock, agent_brief) do
    []
    |> check_equal(
      value(agent_brief, :contract_sha256),
      value(contract_lock, :brief_sha256),
      "brief_digest_mismatch",
      "AgentBrief digest does not match ContractLock."
    )
    |> check_equal(
      digest_value(value(agent_brief, :acceptance_criteria) || []),
      value(contract_lock, :acceptance_criteria_sha256),
      "acceptance_criteria_digest_mismatch",
      "Acceptance criteria digest does not match ContractLock."
    )
    |> check_equal(
      digest_value(value(agent_brief, :required_tests) || []),
      value(contract_lock, :required_tests_sha256),
      "required_tests_digest_mismatch",
      "Required tests digest does not match ContractLock."
    )
    |> check_equal(
      digest_value(value(agent_brief, :verification_commands) || []),
      value(contract_lock, :verification_commands_sha256),
      "verification_commands_digest_mismatch",
      "Verification commands digest does not match ContractLock."
    )
  end

  defp test_pack_findings(_contract_lock, nil),
    do: [finding("missing_test_pack", "TestPack is required.")]

  defp test_pack_findings(contract_lock, test_pack) do
    []
    |> check_equal(
      value(test_pack, :test_pack_sha256),
      value(contract_lock, :test_pack_sha256),
      "test_pack_digest_mismatch",
      "TestPack digest does not match ContractLock."
    )
  end

  defp run_spec_findings(_contract_lock, nil),
    do: [finding("missing_run_spec", "RunSpec is required.")]

  defp run_spec_findings(contract_lock, run_spec) do
    []
    |> check_equal(
      value(run_spec, :test_pack_sha256),
      value(contract_lock, :test_pack_sha256),
      "run_spec_test_pack_digest_mismatch",
      "RunSpec test pack digest does not match ContractLock."
    )
    |> check_equal(
      value(run_spec, :policy_sha256),
      value(contract_lock, :policy_sha256),
      "policy_digest_mismatch",
      "RunSpec policy digest does not match ContractLock."
    )
  end

  defp protected_path_findings(_contract_lock, nil), do: []

  defp protected_path_findings(contract_lock, patch_set) do
    protected_globs = value(contract_lock, :protected_path_globs) || []

    changed_protected =
      patch_set
      |> value(:changed_files)
      |> List.wrap()
      |> Enum.filter(&matches_any?(&1, protected_globs))

    if changed_protected == [] do
      []
    else
      [
        finding(
          "locked_test_pack_or_contract_changed",
          "Patch changes protected contract or locked TestPack paths.",
          changed_protected
        )
      ]
    end
  end

  defp mount_findings(nil, _mount_mode), do: []

  defp mount_findings(test_pack, mount_mode) do
    []
    |> maybe_add(
      mount_mode in [:read_write, "read_write"],
      "locked_test_pack_not_read_only",
      "Locked TestPack must be mounted read-only outside the editable workspace."
    )
    |> maybe_add(
      not locked_mount_path?(value(test_pack, :mount_path)),
      "locked_test_pack_mount_invalid",
      "Locked TestPack mount path must be outside the editable project tree."
    )
  end

  defp locked_mount_path?(path) when is_binary(path) do
    String.starts_with?(path, "/workspace/.conveyor/test-packs/")
  end

  defp locked_mount_path?(_path), do: false

  defp check_equal(findings, actual, expected, _category, _message) when actual == expected,
    do: findings

  defp check_equal(findings, _actual, _expected, category, message),
    do: [finding(category, message) | findings]

  defp maybe_add(findings, true, category, message), do: [finding(category, message) | findings]
  defp maybe_add(findings, false, _category, _message), do: findings

  defp finding(category, message, paths \\ []) do
    %{
      "category" => category,
      "severity" => "blocking",
      "message" => message,
      "paths" => paths
    }
  end

  defp status([]), do: :passed
  defp status(_findings), do: :failed

  defp evidence_refs(context) do
    [
      value(value(context, :contract_lock), :id),
      value(value(context, :agent_brief), :id),
      value(value(context, :test_pack), :test_pack_ref),
      value(value(context, :patch_set), :patch_ref)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp input_digests(contract_lock, context) do
    %{
      "contract_lock_sha256" => value(context, :contract_lock_sha256),
      "brief_sha256" => value(contract_lock, :brief_sha256),
      "test_pack_sha256" => value(contract_lock, :test_pack_sha256),
      "policy_sha256" => value(contract_lock, :policy_sha256)
    }
  end

  defp matches_any?(_path, []), do: false
  defp matches_any?(path, globs), do: Enum.any?(globs, &glob_match?(path, &1))

  defp glob_match?(path, glob) do
    glob
    |> Regex.escape()
    |> String.replace("\\*\\*", ".*")
    |> String.replace("\\*", "[^/]*")
    |> then(&Regex.compile!("^#{&1}$"))
    |> Regex.match?(path)
  end

  defp digest_value(value) do
    ContractEvolution.digest_value(value)
  end

  defp value(nil, _key), do: nil

  defp value(map, key) when is_map(map),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
