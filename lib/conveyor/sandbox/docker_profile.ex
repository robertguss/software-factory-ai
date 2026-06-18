defmodule Conveyor.Sandbox.DockerProfile do
  @moduledoc """
  Hardened Docker defaults for Phase-1 sandbox containers.
  """

  alias Conveyor.Sandbox.NetworkPolicy

  @spec create_args(keyword()) :: [String.t()]
  def create_args(opts \\ []) do
    [
      "--user",
      Keyword.get(opts, :user, "65532:65532")
    ] ++
      NetworkPolicy.docker_args(Keyword.get(opts, :network, :none)) ++
      [
        "--security-opt",
        "no-new-privileges:true",
        "--cap-drop",
        "ALL",
        "--read-only",
        "--tmpfs",
        "/tmp:rw,noexec,nosuid,size=64m",
        "--pids-limit",
        Keyword.get(opts, :pids_limit, "256"),
        "--cpus",
        Keyword.get(opts, :cpus, "1.0"),
        "--memory",
        Keyword.get(opts, :memory, "512m")
      ]
  end

  @spec required_security_options() :: [String.t()]
  def required_security_options, do: ["seccomp"]
end
