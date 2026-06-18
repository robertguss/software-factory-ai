defmodule Conveyor.Policy.ProfilesTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.Config.ValidationError
  alias Conveyor.Factory
  alias Conveyor.Factory.Policy
  alias Conveyor.Policy.Profiles

  @template_dir Path.expand("../../../priv/conveyor/templates/policies", __DIR__)

  test "loads all policy profile TOML files into Policy records" do
    policy_dir = temp_dir!("policies")

    write_policy!(policy_dir, "explore", "explore", "L0", [], ["python"], true)
    write_policy!(policy_dir, "implement", "implement", "L1", ["git diff", "rg"], [], false)
    write_policy!(policy_dir, "verify", "verify", "L1", ["mix test"], ["deploy"], false)
    write_policy!(policy_dir, "release", "release", "L0", [], ["deploy"], true)
    write_policy!(policy_dir, "maintenance", "maintenance", "L0", [], ["rm -rf"], true)

    policies = Profiles.load_dir!(policy_dir)

    assert policies |> Enum.map(& &1.profile) |> Enum.sort() ==
             [:explore, :implement, :maintenance, :release, :verify]

    implement = Enum.find(policies, &(&1.profile == :implement))
    assert implement.name == "implement"
    assert implement.allowlist == ["git diff", "rg"]

    assert implement.env_policy == %{
             "allowlist" => ["MIX_ENV"],
             "deny_production_secrets" => true
           }

    assert implement.network_policy == %{"default" => "none"}
    assert implement.budget_policy == %{"future_gated" => false, "max_tool_calls" => 200}
    assert implement.autonomy_ceiling == 1

    release = Enum.find(policies, &(&1.profile == :release))
    maintenance = Enum.find(policies, &(&1.profile == :maintenance))
    assert release.budget_policy["future_gated"] == true
    assert maintenance.budget_policy["future_gated"] == true

    assert length(Ash.read!(Policy, domain: Factory)) == 5
  end

  test "template policy directory defines every required profile" do
    policies = Profiles.load_dir!(@template_dir)

    assert policies |> Enum.map(& &1.profile) |> Enum.sort() ==
             [:explore, :implement, :maintenance, :release, :verify]

    verify = Enum.find(policies, &(&1.profile == :verify))
    assert verify.network_policy["default"] == "none"
    assert "mix test" in verify.allowlist

    release = Enum.find(policies, &(&1.profile == :release))
    assert release.budget_policy["future_gated"] == true
  end

  test "missing required profiles fail loudly" do
    policy_dir = temp_dir!("missing-policies")
    write_policy!(policy_dir, "implement", "implement", "L1", ["rg"], [], false)
    write_policy!(policy_dir, "verify", "verify", "L1", ["mix test"], [], false)

    assert_raise ValidationError,
                 ~r/missing policy profiles: explore, release, maintenance/,
                 fn ->
                   Profiles.load_dir!(policy_dir)
                 end
  end

  defp write_policy!(
         policy_dir,
         name,
         profile,
         autonomy_ceiling,
         allowlist,
         denylist,
         future_gated?
       ) do
    content = """
    [policy]
    name = "#{name}"
    profile = "#{profile}"
    autonomy_ceiling = "#{autonomy_ceiling}"
    network = "none"
    future_gated = #{future_gated?}
    allowlist = #{inspect(allowlist)}
    denylist = #{inspect(denylist)}

    [policy.env]
    allowlist = ["MIX_ENV"]
    deny_production_secrets = true

    [policy.budget]
    max_tool_calls = 200
    """

    File.write!(Path.join(policy_dir, "#{name}.toml"), content)
  end

  defp temp_dir!(label) do
    path =
      Path.join(
        System.tmp_dir!(),
        "conveyor-policy-#{label}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(path)
    path
  end
end
