defmodule Conveyor.GateStagesPolicySecretTest do
  use ExUnit.Case, async: true

  alias Conveyor.Factory.Artifact
  alias Conveyor.Factory.PatchSet
  alias Conveyor.Factory.ToolInvocation
  alias Conveyor.Gate
  alias Conveyor.Gate.Stages.PolicyCompliance
  alias Conveyor.Gate.Stages.SecretSafety

  test "policy compliance fails when a patch edits policy definitions" do
    result =
      PolicyCompliance.run(%{
        patch_set: %PatchSet{
          patch_ref: "artifacts/patches/attempt-1.patch",
          patch_sha256: digest("patch"),
          changed_files: ["priv/conveyor/templates/policies/verify.toml", "lib/app.ex"]
        },
        tool_invocations: []
      })

    assert result.status == :failed
    assert [%{"category" => "policy_file_change", "paths" => paths}] = result.findings
    assert paths == ["priv/conveyor/templates/policies/verify.toml"]
  end

  test "policy compliance fails on blocked or denied tool invocation records" do
    result =
      PolicyCompliance.run(%{
        patch_set: %PatchSet{
          patch_ref: "artifacts/patches/attempt-1.patch",
          patch_sha256: digest("patch"),
          changed_files: ["lib/app.ex"]
        },
        tool_invocations: [
          %ToolInvocation{
            id: "invocation-1",
            tool_name: "git",
            command_spec: %{"argv" => ["git", "reset", "--hard", "HEAD"]},
            policy_decision: :blocked,
            status: :blocked
          }
        ]
      })

    assert result.status == :failed
    assert [%{"category" => "policy_invocation_blocked"} = finding] = result.findings
    assert finding["tool_invocation_id"] == "invocation-1"
    assert finding["command"] == "git reset --hard HEAD"
  end

  test "policy compliance passes for in-scope files and allowed invocations" do
    result =
      PolicyCompliance.run(%{
        patch_set: %PatchSet{
          patch_ref: "artifacts/patches/attempt-1.patch",
          patch_sha256: digest("patch"),
          changed_files: ["lib/app.ex", "test/app_test.exs"]
        },
        tool_invocations: [
          %ToolInvocation{
            id: "invocation-1",
            tool_name: "mix",
            command_spec: %{"argv" => ["mix", "test"]},
            policy_decision: :allowed,
            status: :succeeded
          }
        ]
      })

    assert result.status == :passed
    assert result.findings == []
  end

  test "secret safety fails on raw gate-visible content containing a secret" do
    result =
      SecretSafety.run(%{
        artifact_contents: [
          %{source: "diff.patch", content: "OPENAI_API_KEY=sk-test-secret123\n"}
        ],
        redaction_policy: :block
      })

    assert result.status == :failed
    assert [%{"category" => "unredacted_secret", "severity" => "blocking"}] = result.findings
    assert result.evidence_refs == ["diff.patch"]
  end

  test "secret safety allows redacted findings when policy permits continuation" do
    result =
      SecretSafety.run(%{
        security_findings: [
          %{
            "category" => "secret_exposure",
            "severity" => "warning",
            "policy" => "redact",
            "source" => "logs/verification.json"
          }
        ],
        allow_redacted_continuation: true
      })

    assert result.status == :passed
    assert [%{"category" => "unredacted_secret", "severity" => "warning"}] = result.findings
  end

  test "secret safety blocks redacted findings when continuation is explicitly disallowed" do
    result =
      SecretSafety.run(%{
        security_findings: [
          %{
            "category" => "secret_exposure",
            "severity" => "warning",
            "policy" => "redact",
            "source" => "logs/verification.json"
          }
        ],
        allow_redacted_continuation: false
      })

    assert result.status == :failed
    assert [%{"category" => "unredacted_secret", "severity" => "blocking"}] = result.findings
  end

  test "secret safety fails on quarantined artifacts even without duplicated content bytes" do
    result =
      SecretSafety.run(%{
        artifacts: [
          %Artifact{
            projection_path: "dossier.md",
            sensitivity: :quarantined,
            redaction_findings: []
          }
        ]
      })

    assert result.status == :failed
    assert [%{"source" => "dossier.md", "severity" => "blocking"}] = result.findings
  end

  test "policy and secret stages compose through the gate framework" do
    context = %{
      gate_code_sha256: "sha256:gate",
      policy_sha256: "sha256:policy",
      contract_lock_sha256: "sha256:contract",
      patch_set: %PatchSet{
        patch_ref: "artifacts/patches/attempt-1.patch",
        patch_sha256: digest("patch"),
        changed_files: ["lib/app.ex"]
      },
      tool_invocations: [],
      security_findings: []
    }

    result =
      Gate.run!(context, [
        %{key: "policy_compliance", module: PolicyCompliance},
        %{key: "secret_safety", module: SecretSafety}
      ])

    assert result.passed?
    assert Enum.map(result.stages, & &1.status) == [:passed, :passed]
  end

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
