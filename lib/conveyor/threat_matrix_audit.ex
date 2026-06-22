defmodule Conveyor.ThreatMatrixAudit do
  @moduledoc """
  Static audit for §12.0 threat-model coverage.
  """

  @schema_version "conveyor.threat_matrix_audit@1"

  @threats [
    %{
      id: "malicious_repository_content",
      title: "Malicious repository content",
      coverage: [
        {"test", "test/conveyor/prompt_builder_test.exs",
         "Prompt trust labels mark repository excerpts as untrusted."},
        {"test", "test/conveyor/eval_suites_test.exs",
         "Prompt-injection eval cases are surfaced in the Phase-1 suite."}
      ]
    },
    %{
      id: "malicious_tool_output",
      title: "Malicious tool output",
      coverage: [
        {"test", "test/conveyor/prompt_builder_test.exs",
         "Tool output is labeled as untrusted prompt context."},
        {"test", "test/conveyor/gate_canary_fixtures_test.exs",
         "Canary fixtures include tool-output injection mutants."}
      ]
    },
    %{
      id: "agent_policy_evasion",
      title: "Agent policy evasion",
      coverage: [
        {"test", "test/conveyor/policy/engine_test.exs",
         "Policy engine blocks denylisted commands and network modes."},
        {"test", "test/conveyor/tool_executor_test.exs",
         "ToolExecutor records and stops blocked invocations."},
        {"test", "test/conveyor/sandbox/policy_executor_test.exs",
         "Sandbox policy executor blocks unsafe execution."}
      ]
    },
    %{
      id: "test_weakening",
      title: "Test weakening",
      coverage: [
        {"test", "test/conveyor/readiness_test.exs",
         "Readiness blocks missing or mismatched locked tests."},
        {"test", "test/conveyor/gate_stages_acceptance_contract_test.exs",
         "Contract gate detects locked-contract mismatches."},
        {"test", "test/conveyor/contract_evolution_test.exs",
         "Contract weakening requires explicit human reason."}
      ]
    },
    %{
      id: "secret_exposure",
      title: "Secret exposure",
      coverage: [
        {"test", "test/conveyor/security_redactor_test.exs",
         "Redactor removes fake credentials without storing raw secret values."},
        {"test", "test/conveyor/gate_stages_policy_secret_test.exs",
         "Gate secret-safety stage fails unredacted secrets."},
        {"test", "test/conveyor/evidence_recorder_test.exs",
         "Evidence recorder projects redacted artifacts and findings."}
      ]
    },
    %{
      id: "supply_chain_drift",
      title: "Supply-chain drift",
      coverage: [
        {"test", "test/conveyor/runtime_versions_test.exs",
         "Runtime version capture covers run evidence fields."},
        {"test", "test/conveyor/factory/run_spec_test.exs",
         "RunSpec freezes image, policy, and test-pack digests."},
        {"test", "test/conveyor/gate_stage_run_check_test.exs",
         "RunCheck validates bundle freshness inputs."}
      ]
    },
    %{
      id: "artifact_tampering",
      title: "Artifact tampering",
      coverage: [
        {"test", "test/conveyor/artifacts/projector_test.exs",
         "Projector rejects corrupted blobs and regenerates deterministic bundles."},
        {"test", "test/conveyor/eval_suites_test.exs",
         "Artifact-integrity eval cases expose mismatched and missing artifacts."},
        {"test", "test/conveyor/gate_stage_run_check_test.exs",
         "RunCheck validates artifact manifest entries."}
      ]
    },
    %{
      id: "reviewer_rubber_stamp",
      title: "Reviewer rubber stamp",
      coverage: [
        {"test", "test/conveyor/run_reviewer_test.exs",
         "Reviewer records schema-validated dossier decisions."},
        {"test", "test/conveyor/gate_stages_reviewer_canary_test.exs",
         "Reviewer health and freshness compose through gate stages."},
        {"test", "test/conveyor/reviewer_health_test.exs",
         "Reviewer fixture suite detects bad reviewer behavior."}
      ]
    },
    %{
      id: "gate_false_negative",
      title: "Gate false negative",
      coverage: [
        {"test", "test/conveyor/run_gate_canary_test.exs",
         "Gate canary detects false-negative mutants."},
        {"test", "test/conveyor/eval/mutant_gauntlet_test.exs",
         "MutantGauntlet measures a real false-pass rate over the behavioral mutant corpus."},
        {"test", "test/conveyor/gate_canary_fixtures_test.exs",
         "Initial mutant corpus includes known-bad changes."}
      ]
    },
    %{
      id: "internal_state_corruption",
      title: "Internal state corruption",
      coverage: [
        {"test", "test/conveyor/sandbox/network_policy_test.exs",
         "Sandbox egress allowlist rejects conductor/internal hosts."},
        {"test", "test/conveyor/design_laws_invariant_test.exs",
         "Design law checks keep station execution isolated from conductor state."}
      ]
    },
    %{
      id: "host_escape_or_overreach",
      title: "Host escape or overreach",
      coverage: [
        {"test", "test/conveyor/sandbox/docker_runner_test.exs",
         "Docker runner uses no network and avoids host network mode."},
        {"doctor", "test/conveyor/doctor_test.exs",
         "Doctor checks rootless/seccomp sandbox posture."},
        {"test", "test/conveyor/design_laws_invariant_test.exs",
         "Sandbox design-law checks assert network and policy isolation."}
      ]
    }
  ]

  @spec audit() :: map()
  def audit do
    threats = Enum.map(@threats, &threat_result/1)

    %{
      "schema_version" => @schema_version,
      "threat_count" => length(threats),
      "passed" => Enum.all?(threats, & &1["covered"]),
      "threats" => threats
    }
  end

  def threat_ids, do: Enum.map(@threats, & &1.id)

  defp threat_result(threat) do
    coverage = Enum.map(threat.coverage, &coverage/1)

    %{
      "id" => threat.id,
      "title" => threat.title,
      "covered" => coverage != [],
      "coverage" => coverage
    }
  end

  defp coverage({kind, path, description}) do
    %{
      "kind" => kind,
      "path" => path,
      "description" => description
    }
  end
end
