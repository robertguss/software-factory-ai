defmodule Conveyor.Policy.EngineTest do
  use ExUnit.Case, async: true

  alias Conveyor.Config.CommandSpec
  alias Conveyor.Factory.Policy
  alias Conveyor.Policy.Engine
  alias Conveyor.Policy.NormalizedCommand

  test "allows commands that match the profile allowlist" do
    command = normalized_command(["pytest", "-q"])
    policy = policy(allowlist: ["pytest"])

    assert %Engine.Decision{status: :allowed, reason: :allowed} =
             Engine.evaluate!(policy, command)
  end

  test "blocks commands outside the profile allowlist" do
    command = normalized_command(["bash", "-lc", "pytest -q"])
    policy = policy(allowlist: ["pytest"])

    assert %Engine.Decision{status: :blocked, reason: :not_allowlisted} =
             Engine.evaluate!(policy, command)
  end

  test "applies denylist after allowlist as defense in depth" do
    command = normalized_command(["git", "reset", "--hard", "HEAD"])
    policy = policy(allowlist: ["git"], denylist: ["git reset --hard"])

    assert %Engine.Decision{status: :blocked, reason: :denylisted} =
             Engine.evaluate!(policy, command)
  end

  test "blocks the minimum dangerous command classes by denylist" do
    cases = [
      {["rm", "-rf", "/tmp/workspace"], "rm -rf"},
      {["git", "reset", "--hard", "HEAD"], "git reset --hard"},
      {["git", "clean", "-fd"], "git clean -fd"},
      {["git", "push", "--force"], "git push --force"},
      {["sudo", "apt", "install", "curl"], "sudo"},
      {["kubectl", "apply", "-f", "deploy.yaml"], "kubectl apply"},
      {["terraform", "apply", "-auto-approve"], "terraform apply"}
    ]

    Enum.each(cases, fn {argv, denied_pattern} ->
      command = normalized_command(argv)
      policy = policy(allowlist: [List.first(argv)], denylist: [denied_pattern])

      assert %Engine.Decision{status: :blocked, reason: :denylisted} =
               Engine.evaluate!(policy, command)
    end)
  end

  test "blocks env keys outside the profile env allowlist" do
    command = normalized_command(["pytest", "-q"], env_allowlist: ["AWS_SECRET_ACCESS_KEY"])
    policy = policy(allowlist: ["pytest"], env_policy: %{"allowlist" => ["MIX_ENV"]})

    assert %Engine.Decision{status: :blocked, reason: :env_not_allowed} =
             Engine.evaluate!(policy, command)
  end

  test "blocks network modes outside the profile network policy" do
    command = normalized_command(["pytest", "-q"], network: :egress)
    policy = policy(allowlist: ["pytest"], network_policy: %{"default" => "none"})

    assert %Engine.Decision{status: :blocked, reason: :network_not_allowed} =
             Engine.evaluate!(policy, command)
  end

  defp normalized_command(argv, opts \\ []) do
    workspace_root = temp_dir!("workspace")

    command_spec = %CommandSpec{
      key: List.first(argv),
      argv: argv,
      profile: :verify,
      network: Keyword.get(opts, :network, :none),
      env_allowlist: Keyword.get(opts, :env_allowlist, []),
      timeout_ms: 120_000
    }

    NormalizedCommand.normalize!(command_spec, workspace_root: workspace_root)
  end

  defp policy(opts) do
    %Policy{
      name: "verify",
      profile: :verify,
      allowlist: Keyword.get(opts, :allowlist, []),
      denylist: Keyword.get(opts, :denylist, []),
      env_policy: Keyword.get(opts, :env_policy, %{"allowlist" => []}),
      network_policy: Keyword.get(opts, :network_policy, %{"default" => "none"}),
      budget_policy: %{},
      autonomy_ceiling: 1
    }
  end

  defp temp_dir!(label) do
    path =
      Path.join(
        System.tmp_dir!(),
        "conveyor-policy-engine-#{label}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(path)
    Path.expand(path)
  end
end
