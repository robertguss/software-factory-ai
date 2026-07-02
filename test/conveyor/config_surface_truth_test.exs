defmodule Conveyor.ConfigSurfaceTruthTest do
  @moduledoc """
  mmxr.1 flip-guard for the operator-editable config surface. Keeps
  docs/audits/config-surface-truth.md honest: every shipped INERT key must carry an `# ADVISORY`
  banner (so an operator who edits it is not misled into a false belief before an unattended run),
  and no un-audited key may sneak into a shipped template. $0 — reads the shipped templates only,
  no DB, no run.
  """
  use ExUnit.Case, async: true

  @templates Path.expand("../../priv/conveyor/templates", __DIR__)

  # Inert keys per the audit; each must be banner-tagged on every occurrence in its template.
  @config_inert ~w(default_autonomy_level prompts_dir runs_dir blobs_dir cwd timeout_ms
                   env_allowlist output_limit_bytes result_format result_adapter)
  @policy_inert ~w(autonomy_ceiling deny_production_secrets)

  # The audited config.toml key surface (docs/audits/config-surface-truth.md). A new key added to
  # the shipped template without an audit entry fails the last test below — "new knobs without
  # coverage fail review by convention".
  @audited_config_keys ~w(name repo_path default_branch dev_branch default_autonomy_level
                          policies_dir prompts_dir runs_dir blobs_dir quality_adapter
                          key argv cwd profile required timeout_ms network env_allowlist
                          output_limit_bytes result_format result_adapter)

  test "every inert config.toml key carries an ADVISORY banner on each occurrence" do
    body = File.read!(Path.join(@templates, "config.toml"))
    for key <- @config_inert, do: assert_lines_tagged(body, key, "config.toml")
  end

  test "every inert policy key carries an ADVISORY banner in each shipped policy file" do
    for path <- Path.wildcard(Path.join(@templates, "policies/*.toml")) do
      body = File.read!(path)

      for key <- @policy_inert, body =~ ~r/^\s*#{key}\s*=/m do
        assert_lines_tagged(body, key, Path.basename(path))
      end
    end
  end

  test "the wholly-inert prompt templates carry a reference-only banner" do
    prompts = Path.wildcard(Path.join(@templates, "prompts/*.md"))
    assert prompts != [], "expected shipped prompt templates"

    for path <- prompts do
      assert File.read!(path) =~ "ADVISORY — reference only",
             "#{Path.basename(path)} must carry the reference-only ADVISORY banner (the operator " <>
               "prompt file is inert; editing it does not change agent behavior)"
    end
  end

  test "no un-audited key sneaks into the shipped config.toml surface" do
    body = File.read!(Path.join(@templates, "config.toml"))

    keys =
      ~r/^\s*([a-z_]+)\s*=/m
      |> Regex.scan(body)
      |> Enum.map(fn [_, key] -> key end)
      |> Enum.uniq()

    unaudited = keys -- @audited_config_keys

    assert unaudited == [],
           "config.toml has un-audited key(s) #{inspect(unaudited)} — add them to " <>
             "docs/audits/config-surface-truth.md (with a verdict) and to this guard, or give the " <>
             "key an ADVISORY banner if inert"
  end

  defp assert_lines_tagged(body, key, where) do
    lines =
      body
      |> String.split("\n")
      |> Enum.filter(&(&1 =~ ~r/^\s*#{key}\s*=/))

    assert lines != [], "#{where}: expected inert key `#{key}` to be present"

    for line <- lines do
      assert line =~ "ADVISORY",
             "#{where}: inert key line must carry an ADVISORY banner — got: #{String.trim(line)}"
    end
  end
end
