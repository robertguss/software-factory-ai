defmodule Conveyor.AgentsMdLinterTest do
  use ExUnit.Case, async: true

  alias Conveyor.AgentsMd
  alias Conveyor.AgentsMd.Linter
  alias Conveyor.Config

  @sample_config Path.expand("../../priv/conveyor/templates/config.toml", __DIR__)

  test "generated AGENTS.md passes lint against config and policies" do
    project_path = temp_project_path()
    scaffold_project!(project_path)

    config = Config.load!(Path.join(project_path, ".conveyor/config.toml"))
    File.write!(Path.join(project_path, "AGENTS.md"), AgentsMd.generate(config))

    assert {:ok, result} = Linter.lint(project_path)
    assert result.status == :passed
    assert result.findings == []
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

  defp temp_project_path do
    Path.join(System.tmp_dir!(), "conveyor-agents-lint-#{System.unique_integer([:positive])}")
  end
end
