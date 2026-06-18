defmodule Conveyor.SecurityRedactorTest do
  use ExUnit.Case, async: true

  alias Conveyor.Security.Redactor

  test "redacts fake credentials without storing secret values in findings" do
    content = """
    OPENAI_API_KEY=sk-test-secret123
    token=ghp_abcdefghijklmnopqrstuvwxyz
    """

    result = Redactor.redact!(content, source: "logs/run.txt", policy: :redact)

    assert result.sensitivity == :redacted
    refute result.blocked?
    assert result.raw_sha256 != result.redacted_sha256
    refute result.content =~ "sk-test-secret123"
    refute result.content =~ "ghp_abcdefghijklmnopqrstuvwxyz"
    assert result.content =~ "[REDACTED:"
    assert length(result.findings) == 2

    finding_text = inspect(result.findings)
    refute finding_text =~ "sk-test-secret123"
    refute finding_text =~ "ghp_abcdefghijklmnopqrstuvwxyz"
    assert Enum.all?(result.findings, &(&1["category"] == "secret_exposure"))
    assert Enum.all?(result.findings, &(&1["severity"] == "warning"))
  end

  test "block policy quarantines raw bytes and records redacted digest provenance" do
    content = "AWS_ACCESS_KEY_ID=AKIA1234567890ABCDEF\n"

    result = Redactor.redact!(content, source: "diff.patch", policy: :block)

    assert result.sensitivity == :quarantined
    assert result.blocked?
    assert result.content == content
    assert result.raw_sha256 != result.redacted_sha256
    assert [%{"severity" => "blocking", "policy" => "block"}] = result.findings
  end

  test "redacted output keeps surrounding text in order for single and multiple matches" do
    single =
      Redactor.redact!("prefix OPENAI_API_KEY=sk-test-secret123 suffix",
        source: "logs/run.txt",
        policy: :redact
      )

    assert String.starts_with?(single.content, "prefix ")
    assert single.content =~ ~r/prefix.*\[REDACTED:.*suffix/

    multi =
      Redactor.redact!(
        "a OPENAI_API_KEY=sk-test-secret123 b token=ghp_abcdefghijklmnopqrstuvwxyz c",
        source: "logs/run.txt",
        policy: :redact
      )

    assert multi.content =~ ~r/a .*\[REDACTED:.*b .*\[REDACTED:.*c/
    refute multi.content =~ "sk-test-secret123"
    refute multi.content =~ "ghp_abcdefghijklmnopqrstuvwxyz"
  end
end
