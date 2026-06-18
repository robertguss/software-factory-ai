defmodule Conveyor.Sandbox.NetworkPolicyTest do
  use ExUnit.Case, async: true

  alias Conveyor.Sandbox.NetworkPolicy

  test "all phase one executable stations default to no network" do
    for station <- [:scout, :implement, :verify, :gate, :canary] do
      assert NetworkPolicy.default_for(station) == :none

      assert NetworkPolicy.docker_args(NetworkPolicy.default_for(station)) == [
               "--network",
               "none"
             ]
    end
  end

  test "egress allowlist rejects conductor and private network targets" do
    for host <- ["localhost", "127.0.0.1", "10.0.0.5", "172.18.0.2", "192.168.1.10", "postgres"] do
      assert NetworkPolicy.internal_host?(host)
    end

    assert_raise ArgumentError, ~r/internal host/, fn ->
      NetworkPolicy.validate_egress_allowlist!(["api.openai.com", "postgres"])
    end
  end

  test "external hosts can be allowlisted" do
    assert :ok = NetworkPolicy.validate_egress_allowlist!(["api.openai.com", "pypi.org"])
  end
end
