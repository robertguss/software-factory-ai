defmodule Conveyor.AgentsMdLinterTest do
  use ExUnit.Case, async: true

  alias Conveyor.AgentsMd
  alias Conveyor.AgentsMd.Linter
  alias Conveyor.Config

  @sample_config Path.expand("../../priv/conveyor/templates/config.toml", __DIR__)
  @fixture_path Path.expand("../fixtures/agents_md_linter", __DIR__)
  @fixture_expectations [
    {"complete.md", :passed, []},
    {"missing-commands.md", :failed, [:command_mismatch, :missing_config_command]},
    {"vague-done.md", :failed,
     [
       :done_missing_evidence,
       :done_missing_independent_verification,
       :ambiguous_language
     ]},
    {"contradictory.md", :failed, [:contradictory_command]},
    {"no-security.md", :failed, [:security_missing_deploys, :security_missing_prod_secrets]}
  ]

  test "generated AGENTS.md passes lint against config and policies" do
    project_path = temp_project_path()
    scaffold_project!(project_path)

    config = Config.load!(Path.join(project_path, ".conveyor/config.toml"))
    File.write!(Path.join(project_path, "AGENTS.md"), AgentsMd.generate(config))

    assert {:ok, result} = Linter.lint(project_path)
    assert result.status == :passed
    assert result.findings == []
  end

  test "fixture AGENTS.md files yield expected findings" do
    for {fixture, expected_status, expected_codes} <- @fixture_expectations do
      project_path = temp_project_path()
      scaffold_project!(project_path)

      fixture
      |> fixture_content()
      |> then(&File.write!(Path.join(project_path, "AGENTS.md"), &1))

      assert {:ok, result} = Linter.lint(project_path)
      assert result.status == expected_status, "unexpected status for #{fixture}"

      assert finding_code_counts(result) == code_counts(expected_codes),
             "unexpected finding codes for #{fixture}: #{inspect(result.findings)}"
    end
  end

  test "reports specific findings for missing sections and command drift" do
    project_path = temp_project_path()
    scaffold_project!(project_path)

    File.write!(Path.join(project_path, "AGENTS.md"), """
    # Project Overview

    make it good

    # Commands

    - Test: `pytest` -> `pytest --wrong`
    """)

    assert {:ok, result} = Linter.lint(project_path)
    assert result.status == :failed
    assert finding_codes(result) |> Enum.member?(:missing_section)
    assert finding_codes(result) |> Enum.member?(:command_mismatch)
    assert finding_codes(result) |> Enum.member?(:done_missing_evidence)
    assert finding_codes(result) |> Enum.member?(:security_missing_prod_secrets)
    assert finding_codes(result) |> Enum.member?(:ambiguous_language)
  end

  test "reports policy denylist omissions from forbidden actions" do
    project_path = temp_project_path()
    scaffold_project!(project_path)

    config = Config.load!(Path.join(project_path, ".conveyor/config.toml"))

    content =
      config
      |> AgentsMd.generate()
      |> String.replace(
        "Do not merge, deploy, edit locked contracts, change policy, access production secrets, or run denied commands without explicit human approval.",
        "Do not merge without approval."
      )

    File.write!(Path.join(project_path, "AGENTS.md"), content)

    assert {:ok, result} = Linter.lint(project_path)
    assert result.status == :failed
    assert :missing_policy_denylist in finding_codes(result)
  end

  defp scaffold_project!(project_path) do
    File.mkdir_p!(Path.join(project_path, ".conveyor/policies"))
    File.cp!(@sample_config, Path.join(project_path, ".conveyor/config.toml"))

    File.cp!(
      "priv/conveyor/templates/policies/implement.toml",
      Path.join(project_path, ".conveyor/policies/implement.toml")
    )

    File.cp!(
      "priv/conveyor/templates/policies/verify.toml",
      Path.join(project_path, ".conveyor/policies/verify.toml")
    )
  end

  defp finding_codes(result), do: Enum.map(result.findings, & &1.code)

  defp finding_code_counts(result), do: code_counts(finding_codes(result))

  defp code_counts(codes), do: Enum.frequencies(codes)

  defp fixture_content(fixture), do: File.read!(Path.join(@fixture_path, fixture))

  defp temp_project_path do
    Path.join(System.tmp_dir!(), "conveyor-agents-lint-#{System.unique_integer([:positive])}")
  end
end
