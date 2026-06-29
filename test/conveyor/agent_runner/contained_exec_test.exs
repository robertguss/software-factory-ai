defmodule Conveyor.AgentRunner.ContainedExecTest do
  use ExUnit.Case, async: true

  alias Conveyor.AgentRunner.ContainedExec
  alias Conveyor.Factory.Policy

  @mount "/workspace"

  defp policy(overrides \\ %{}) do
    base = %{
      network_policy: %{"default" => "none"},
      env_policy: %{"allowlist" => []}
    }

    struct(Policy, Map.merge(base, overrides))
  end

  # uid lookup that never shells out (non-root host) for the pure arg tests.
  defp non_root_ids do
    fn
      "id", ["-u"], _ -> {"1000\n", 0}
      "id", ["-g"], _ -> {"1000\n", 0}
    end
  end

  describe "docker_args/3 (pure construction)" do
    test "wraps argv in a hardened docker run with workspace mount and network none" do
      args =
        ContainedExec.docker_args(["claude", "-p", "hi"], "/tmp/ws",
          policy: policy(),
          agent_image: "python:3.12-slim",
          id_cmd: non_root_ids()
        )

      assert ["run", "--rm", "--workdir", @mount | _] = args
      # reuses the gate's hardening (DockerProfile/NetworkPolicy)
      assert contains_pair?(args, "--network", "none")
      assert "--read-only" in args
      assert "--cap-drop" in args
      # host uid:gid so bind-mount writes land as the host user (non-root)
      assert contains_pair?(args, "--user", "1000:1000")
      # workspace mounted rw at the container mount point
      assert contains_pair?(args, "--volume", "/tmp/ws:#{@mount}:rw")
      # image, then the agent argv, in order, at the tail
      assert List.last(chunk_before(args, "claude")) == "python:3.12-slim"
      assert Enum.slice(args, -3, 3) == ["claude", "-p", "hi"]
    end

    test "env: only allowlisted host keys cross the boundary; HOME forced onto tmpfs" do
      System.put_env("CONTAINED_TEST_ALLOWED", "yes")
      System.put_env("ANTHROPIC_API_KEY", "sk-should-not-leak")
      on_exit(fn -> System.delete_env("CONTAINED_TEST_ALLOWED") end)

      args =
        ContainedExec.docker_args(["claude"], "/tmp/ws",
          policy: policy(%{env_policy: %{"allowlist" => ["CONTAINED_TEST_ALLOWED"]}}),
          agent_image: "img",
          id_cmd: non_root_ids()
        )

      env_values = env_flag_values(args)
      assert "HOME=/tmp" in env_values
      assert "CONTAINED_TEST_ALLOWED=yes" in env_values
      refute Enum.any?(env_values, &String.starts_with?(&1, "ANTHROPIC_API_KEY"))
    end

    test "refuses to run the contained agent as root (uid 0)" do
      root_ids = fn
        "id", ["-u"], _ -> {"0\n", 0}
        "id", ["-g"], _ -> {"0\n", 0}
      end

      assert_raise ArgumentError, ~r/root/, fn ->
        ContainedExec.docker_args(["claude"], "/tmp/ws",
          policy: policy(),
          agent_image: "img",
          id_cmd: root_ids
        )
      end
    end

    test "raises a clear operator error when no agent image is configured" do
      assert_raise ArgumentError, ~r/agent_container_image/, fn ->
        ContainedExec.docker_args(["claude"], "/tmp/ws", policy: policy(), id_cmd: non_root_ids())
      end
    end
  end

  describe "run/3" do
    test "passes the constructed docker invocation to the injected cmd and returns its result" do
      parent = self()

      cmd = fn "docker", args, sysopts ->
        send(parent, {:invoked, args, sysopts})
        {"stream-json line\n", 0}
      end

      assert {"stream-json line\n", 0} =
               ContainedExec.run(["claude", "-p", "x"], "/tmp/ws",
                 cmd: cmd,
                 policy: policy(),
                 agent_image: "img",
                 id_cmd: non_root_ids()
               )

      assert_received {:invoked, args, sysopts}
      assert ["run", "--rm" | _] = args
      # KTD1: no stderr_to_stdout on the station path (merged stderr corrupts result line)
      refute Keyword.get(sysopts, :stderr_to_stdout, false)
    end
  end

  # Real-Docker enforcement — the boundary is exercised, not mocked. Untagged to match
  # the existing test/conveyor/sandbox/docker_runner_test.exs convention (Docker assumed
  # present). Uses a generic probe image so no agent CLI/credentials are required.
  describe "enforced boundary (real docker, python:3.12-slim)" do
    @describetag :containment_integration

    setup do
      ws = Path.join(System.tmp_dir!(), "contained-ws-#{System.unique_integer([:positive])}")
      File.mkdir_p!(ws)
      on_exit(fn -> File.rm_rf(ws) end)
      {:ok, ws: ws}
    end

    test "network egress is blocked under network_policy none", %{ws: ws} do
      {_out, code} =
        ContainedExec.run(
          ["python", "-c", "import socket; socket.create_connection(('1.1.1.1', 53), timeout=3)"],
          ws,
          policy: policy(),
          agent_image: "python:3.12-slim"
        )

      assert code != 0
    end

    test "writes outside the workspace are prevented (read-only rootfs)", %{ws: ws} do
      {_out, code} =
        ContainedExec.run(
          ["python", "-c", "open('/root/escape', 'w').write('x')"],
          ws,
          policy: policy(),
          agent_image: "python:3.12-slim"
        )

      assert code != 0
    end

    test "writes inside the workspace succeed and land on the host", %{ws: ws} do
      {_out, code} =
        ContainedExec.run(
          ["sh", "-c", "echo contained > #{@mount}/proof.txt"],
          ws,
          policy: policy(),
          agent_image: "python:3.12-slim"
        )

      assert code == 0
      assert File.read!(Path.join(ws, "proof.txt")) =~ "contained"
    end

    test "the agent env does not carry host secrets", %{ws: ws} do
      System.put_env("ANTHROPIC_API_KEY", "sk-should-not-leak")

      {out, 0} =
        ContainedExec.run(
          ["python", "-c", "import os; print(os.environ.get('ANTHROPIC_API_KEY', 'MISSING'))"],
          ws,
          policy: policy(),
          agent_image: "python:3.12-slim"
        )

      assert out =~ "MISSING"
    end

    test "the agent runs non-root (host uid, not container root)", %{ws: ws} do
      {out, 0} =
        ContainedExec.run(["id", "-u"], ws, policy: policy(), agent_image: "python:3.12-slim")

      refute String.trim(out) == "0"
    end
  end

  # helpers ------------------------------------------------------------------

  defp contains_pair?(args, flag, value) do
    args
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.any?(fn [a, b] -> a == flag and b == value end)
  end

  defp env_flag_values(args) do
    args
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.filter(fn [a, _] -> a == "--env" end)
    |> Enum.map(fn [_, v] -> v end)
  end

  defp chunk_before(args, marker), do: Enum.take_while(args, &(&1 != marker))
end
