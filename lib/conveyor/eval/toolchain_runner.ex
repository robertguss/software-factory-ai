defmodule Conveyor.Eval.ToolchainRunner do
  @moduledoc """
  Real execution of a sample project's verification commands (idea F1).

  Replaces the gate's injected fixtures / the no-op `VerificationRerunner` runner
  with an actual `pytest` run, and returns the **exact `verification_result`
  shape the gate's `test_execution` stage consumes** plus a stable `runner/2`
  closure for `build_install` / `VerificationRerunner`. This is what converts
  every gate-based eval from "tests decision logic given results" to "tests real
  execution of a behavioral bug".

  Two backends, same interface:

    * `:local` (default) — runs `pytest` from a venv built (and cached by
      `requirements.lock` digest) under the system tmp dir. Portable, CI-friendly,
      no Docker.
    * `:docker` — runs inside the pinned image (`profile.toml` `image_digest`)
      with `--network=none` for full reproducibility. Used when Docker is present.

  Determinism: a pinned, seeded environment (`PYTHONHASHSEED=0`, `TZ=UTC`,
  `LC_ALL=C`) — which doubles as the hermeticity observations E8 feeds the
  IntegritySentinel (`hermeticity/1`). A `result_digest` is computed over a
  normalized projection (suite_kind → sorted {nodeid, status}) so reruns are
  byte-identical and cassette/replay drift (#4) is detectable. The caller is
  responsible for never mutating the source tree (operate on a workspace copy).

  Nodeid reconstruction: pytest's junit emits `classname`+`name` but no `file`,
  so a nodeid is rebuilt as `classname`→path + `"::"` + `name` (e.g.
  `tests.test_tasks_api` → `tests/test_tasks_api.py::<name>`). Exact for
  function-based suites such as `samples/tasks_service`; class-based suites would
  need the `file` attribute (a deliberate tracer-scope limitation).
  """

  alias Conveyor.CanonicalJson

  @type backend :: :local | :docker
  @type command_result :: %{exit_code: integer(), stdout: String.t(), stderr: String.t()}
  @type test_row :: %{
          required(:id) => String.t(),
          required(:name) => String.t(),
          required(:status) => :passed | :failed | :skipped,
          required(:message) => String.t() | nil
        }

  # Pinned image from toolchains/sample-python-runner/profile.toml (ref @ digest).
  @docker_image "ghcr.io/conveyor/sample-python-runner@sha256:18be896c98e13585f4d2701490a5be39126ec1b14d429f72b5707b99516b5548"

  @junit_rel ".conveyor_eval_junit.xml"

  @paired_testcase ~r/<testcase\b((?:(?!\/>).)*?)>(.*?)<\/testcase>/s
  @self_closing_testcase ~r/<testcase\b([^>]*)\/>/
  @attr ~r/([A-Za-z_:][-A-Za-z0-9_:.]*)="([^"]*)"/

  @doc """
  A `(command -> command_result)` closure suitable for the gate's `:runner` /
  `:build_install_runner` / `:verification_runner` opts. Executes the command's
  `argv` against `workspace_path` on the chosen backend.
  """
  @spec runner(String.t(), keyword()) :: (term() -> command_result())
  def runner(workspace_path, opts \\ []) do
    backend = Keyword.get(opts, :backend, :local)
    fn command -> exec(backend, workspace_path, command, opts) end
  end

  @doc """
  Run the plan's verification (pytest) against a (possibly patched) `workspace_path`
  and build the `verification_result` map `test_execution` expects:

      %{
        "status" => "passed" | "failed",
        "suites" => [
          %{"suite_kind" => "baseline_regression", "status" => ..., "commands" => [...]},
          %{"suite_kind" => "acceptance_locked",   "status" => ..., "commands" => [...]}
        ],
        "result_digest" => "sha256:..."
      }

  One pytest run is partitioned into the two gate-required suites: the full run is
  `baseline_regression`; the subset named by the plan's `required_test_refs` is
  `acceptance_locked`.
  """
  @spec verification_result(String.t(), map(), keyword()) :: map()
  def verification_result(workspace_path, plan, opts \\ []) do
    {tests, _exit_code, _stdout, mutated} = run_pytest(workspace_path, opts)
    selected_refs = test_refs(opts)

    argv = plan_argv(plan, selected_refs)
    acceptance_ids = selected_refs || acceptance_test_refs(plan)
    acceptance_tests = Enum.filter(tests, &(&1.id in acceptance_ids))

    suites = [
      suite("baseline_regression", argv, tests),
      suite("acceptance_locked", argv, acceptance_tests)
    ]

    overall =
      if Enum.all?(suites, &(&1["status"] in ["passed", "passed_with_warning"])),
        do: "passed",
        else: "failed"

    result = %{"status" => overall, "suites" => suites}

    # result_digest is computed over {status, suites} only — BEFORE integrity
    # observations are attached — so the digest stays stable across backends and
    # the new key cannot perturb replay/digest assertions.
    result
    |> Map.put("result_digest", CanonicalJson.digest(normalized(result)))
    |> Map.put("integrity_observations", integrity_observations(opts, mutated))
  end

  @doc """
  Hermeticity observations for the IntegritySentinel (F1 ↔ E8). Honest per
  backend: only `:docker` blocks the network (`--network=none`); `:local` pins
  tz/locale/hash-seed but cannot block the network without a sandbox.
  """
  @spec hermeticity(keyword()) :: %{String.t() => String.t()}
  def hermeticity(opts \\ []) do
    backend = Keyword.get(opts, :backend, :local)

    %{
      "network" => if(backend == :docker, do: "blocked", else: "unrestricted"),
      "clock" => "tz_pinned",
      "rng" => "seeded",
      "locale" => "pinned"
    }
  end

  @doc "Whether the `:docker` backend is usable (the `docker` CLI is on PATH)."
  @spec docker_available?() :: boolean()
  def docker_available?, do: System.find_executable("docker") != nil

  # --- pytest run -----------------------------------------------------------

  defp run_pytest(workspace_path, opts) do
    backend = Keyword.get(opts, :backend, :local)
    junit_host = Path.join(workspace_path, @junit_rel)
    _ = File.rm(junit_host)

    argv =
      ["-q", "-p", "no:cacheprovider", "--color=no", "--junitxml=" <> @junit_rel] ++
        (test_refs(opts) || [])

    # source-mutation observation (ADR-23): snapshot production source around the
    # test run so we detect files the *test run itself* rewrote (an anti-vacuity
    # cheat). The agent's patch is already applied before verify, so this is the
    # honest "mutated during pytest" set, not the agent's legitimate diff.
    before = snapshot_source(workspace_path, opts)
    {out, code} = run_pytest_cmd(backend, workspace_path, argv, opts)
    mutated = mutated_paths(before, snapshot_source(workspace_path, opts))

    tests =
      case File.read(junit_host) do
        {:ok, xml} -> parse_testcases(xml)
        {:error, _} -> []
      end

    _ = File.rm(junit_host)
    {tests, code, out, mutated}
  end

  defp run_pytest_cmd(:local, ws, argv, opts) do
    pytest = Path.join(ensure_python_bin(ws, opts), "pytest")
    System.cmd(pytest, argv, cd: ws, env: pinned_env(opts), stderr_to_stdout: true)
  end

  defp run_pytest_cmd(:docker, ws, argv, opts) do
    image = Keyword.get(opts, :docker_image, @docker_image)

    docker_args =
      ["run", "--rm", "--network=" <> network_mode(opts), "-v", ws <> ":/work", "-w", "/work"] ++
        docker_env_flags(opts) ++ ["--entrypoint", "pytest", image] ++ argv

    System.cmd("docker", docker_args, stderr_to_stdout: true)
  end

  # --- runner closure exec --------------------------------------------------

  defp exec(:local, ws, command, opts) do
    case argv(command) do
      [prog | rest] ->
        prog = resolve_local_prog(ws, prog, opts)

        {out, code} =
          System.cmd(prog, rest, cd: ws, env: pinned_env(opts), stderr_to_stdout: true)

        %{exit_code: code, stdout: out, stderr: ""}

      [] ->
        %{exit_code: 127, stdout: "", stderr: "empty command argv"}
    end
  end

  defp exec(:docker, ws, command, opts) do
    image = Keyword.get(opts, :docker_image, @docker_image)

    case argv(command) do
      [prog | rest] ->
        docker_args =
          ["run", "--rm", "--network=" <> network_mode(opts), "-v", ws <> ":/work", "-w", "/work"] ++
            docker_env_flags(opts) ++ ["--entrypoint", prog, image] ++ rest

        {out, code} = System.cmd("docker", docker_args, stderr_to_stdout: true)
        %{exit_code: code, stdout: out, stderr: ""}

      [] ->
        %{exit_code: 127, stdout: "", stderr: "empty command argv"}
    end
  end

  defp resolve_local_prog(ws, "pytest", opts),
    do: Path.join(ensure_python_bin(ws, opts), "pytest")

  defp resolve_local_prog(_ws, prog, _opts), do: prog

  defp argv(command) when is_list(command), do: command
  defp argv(%{} = command), do: command["argv"] || Map.get(command, :argv) || []
  defp argv(_), do: []

  # --- integrity observations (ADR-23) --------------------------------------

  defp network_mode(opts), do: Keyword.get(opts, :network, "none")

  # Truthful IntegritySentinel observations for the run. source-mutation is always
  # provided (snapshot-based, backend-agnostic). hermeticity is provided ONLY under
  # the docker backend, where the container genuinely enforces all six controls;
  # under :local we omit it so it stays not_assessed (non-blocking) rather than
  # falsely claiming an un-isolated host is hermetic.
  defp integrity_observations(opts, mutated) do
    base = %{"source_mutation" => %{"mutated_production_paths" => mutated}}

    case Keyword.get(opts, :backend, :local) do
      :docker -> Map.put(base, "hermeticity", hermeticity_observation(opts))
      _other -> base
    end
  end

  # Maps the docker run's ACTUAL enforced configuration to the sentinel's six
  # controls. Only `network` varies (the `:network` opt / `--network=`); the rest
  # are enforced by the pinned env (PYTHONHASHSEED -> rng+ordering, LC/LANG=C ->
  # locale, TZ=UTC -> clock) and the fresh `--rm` container (shared_state).
  defp hermeticity_observation(opts) do
    %{
      network: if(network_mode(opts) == "none", do: :blocked, else: :unrestricted),
      clock: :controlled,
      rng: :seeded,
      ordering: :stable,
      locale: :pinned,
      shared_state: :isolated
    }
  end

  # Production source files (default `src/`) the test run changed or removed — an
  # anti-vacuity cheat. Keyed workspace-relative; excludes caches/bytecode.
  defp mutated_paths(before, current) do
    changed = for {path, hash} <- current, Map.get(before, path) != hash, do: path
    removed = for {path, _hash} <- before, not Map.has_key?(current, path), do: path

    (changed ++ removed) |> Enum.uniq() |> Enum.sort()
  end

  defp snapshot_source(workspace_path, opts) do
    root = Path.join(workspace_path, Keyword.get(opts, :source_root, "src"))

    if File.dir?(root) do
      (root <> "/**/*")
      |> Path.wildcard()
      |> Enum.filter(&File.regular?/1)
      |> Enum.reject(&(String.contains?(&1, "__pycache__") or String.ends_with?(&1, ".pyc")))
      |> Map.new(fn path -> {Path.relative_to(path, workspace_path), hash_file(path)} end)
    else
      %{}
    end
  end

  defp hash_file(path) do
    path |> File.read!() |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)
  end

  # --- venv management ------------------------------------------------------

  # Returns the `bin/` dir of a usable Python environment. Honors an explicit
  # `:venv_bin` (offline / shared), otherwise builds+caches a venv from the
  # workspace's `requirements.lock`, keyed by the lock's digest.
  defp ensure_python_bin(ws, opts) do
    case Keyword.get(opts, :venv_bin) do
      nil -> build_or_cache_venv(ws, opts)
      bin -> bin
    end
  end

  defp build_or_cache_venv(ws, opts) do
    lock = Keyword.get(opts, :requirements_lock, Path.join(ws, "requirements.lock"))
    key = lock |> File.read!() |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)
    venv = Path.join(System.tmp_dir!(), "conveyor_eval_venv_" <> binary_part(key, 0, 16))
    pytest = Path.join([venv, "bin", "pytest"])

    unless File.exists?(pytest), do: build_venv!(venv, lock)

    Path.join(venv, "bin")
  end

  # Build the eval venv. Prefer `uv` — self-contained, needs no system `python3-venv`/`ensurepip`
  # — falling back to stdlib `python3 -m venv` + `pip`. A build step that exits non-zero raises a
  # descriptive error naming the step and its output (bug 9g1i) instead of the previous bare
  # `{_, 0} = System.cmd(...)` MatchError, so Verify surfaces a legible infrastructure failure.
  defp build_venv!(venv, lock) do
    # We only reach here when the cached venv has no `bin/pytest` — i.e. it's missing or a
    # partial/failed build. Clear any stale dir first so the builder is idempotent (a crashed
    # `python3 -m venv` leaves a pip-less shell that `uv venv` then refuses to overwrite).
    File.rm_rf!(venv)

    case System.find_executable("uv") do
      nil -> stdlib_venv!(venv, lock)
      uv -> uv_venv!(uv, venv, lock)
    end
  end

  defp uv_venv!(uv, venv, lock) do
    run_build_step!("uv venv", uv, ["venv", venv])
    python = Path.join([venv, "bin", "python"])
    run_build_step!("uv pip install", uv, ["pip", "install", "--python", python, "-r", lock])
  end

  defp stdlib_venv!(venv, lock) do
    run_build_step!("python3 -m venv", "python3", ["-m", "venv", venv])
    pip = Path.join([venv, "bin", "pip"])

    run_build_step!(
      "pip install",
      pip,
      ["install", "--quiet", "--disable-pip-version-check", "--no-input", "-r", lock]
    )
  end

  defp run_build_step!(label, cmd, args) do
    case System.cmd(cmd, args, stderr_to_stdout: true) do
      {_out, 0} ->
        :ok

      {out, code} ->
        raise "eval venv build step #{inspect(label)} failed (exit #{code}): " <>
                String.slice(out, 0, 2000)
    end
  end

  defp pinned_env(opts) do
    base = [
      {"PYTHONHASHSEED", "0"},
      {"TZ", "UTC"},
      {"LC_ALL", "C"},
      {"LANG", "C"},
      {"PYTHONDONTWRITEBYTECODE", "1"}
    ]

    base ++ Keyword.get(opts, :env, [])
  end

  defp docker_env_flags(opts) do
    pinned_env(opts)
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.flat_map(fn {k, v} -> ["-e", "#{k}=#{v}"] end)
  end

  # --- suites ---------------------------------------------------------------

  defp suite(kind, argv, tests) do
    # dr1m.7: an acceptance_locked suite that ran ZERO tests cannot pass — a slice with
    # no locked acceptance tests must fail the gate, not vacuously pass on an empty run.
    failed? = Enum.any?(tests, &(&1.status == :failed)) or empty_acceptance?(kind, tests)
    status = if failed?, do: "failed", else: "passed"
    exit_code = if failed?, do: 1, else: 0

    %{
      "suite_id" => "eval-" <> kind,
      "key" => kind,
      "suite_kind" => kind,
      "status" => status,
      "commands" => [
        %{
          "key" => "pytest",
          "argv" => argv,
          "status" => status,
          "classification" => "stable",
          "attempts" => [
            %{
              "attempt_no" => 1,
              "exit_code" => exit_code,
              "infra_retries" => 0,
              "status" => status,
              "tests" => Enum.map(tests, &test_map/1),
              "error" => nil
            }
          ]
        }
      ]
    }
  end

  defp empty_acceptance?("acceptance_locked", tests), do: tests == []
  defp empty_acceptance?(_kind, _tests), do: false

  defp test_map(t) do
    %{
      "id" => t.id,
      "name" => t.name,
      "status" => Atom.to_string(t.status),
      "message" => t.message
    }
  end

  # Stable projection for the result_digest: only suite_kind/status and sorted
  # {nodeid, status}. Excludes ids, times, and failure messages (which carry the
  # ephemeral workspace path) so reruns are byte-identical.
  defp normalized(result) do
    suites =
      result["suites"]
      |> Enum.map(fn s ->
        %{
          "suite_kind" => s["suite_kind"],
          "status" => s["status"],
          "tests" =>
            s
            |> suite_tests()
            |> Enum.map(&%{"id" => &1["id"], "status" => &1["status"]})
            |> Enum.sort_by(& &1["id"])
        }
      end)
      |> Enum.sort_by(& &1["suite_kind"])

    %{"status" => result["status"], "suites" => suites}
  end

  defp suite_tests(suite) do
    suite["commands"]
    |> List.wrap()
    |> Enum.flat_map(fn c -> c["attempts"] || [] end)
    |> Enum.flat_map(fn a -> a["tests"] || [] end)
  end

  # --- plan helpers ---------------------------------------------------------

  defp plan_argv(plan, selected_refs) do
    argv =
      case plan["verification_commands"] do
        [%{} = first | _] -> first["argv"] || ["pytest", "-q"]
        _ -> ["pytest", "-q"]
      end

    argv ++ (selected_refs || [])
  end

  defp test_refs(opts) do
    opts
    |> Keyword.get(:test_refs)
    |> List.wrap()
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      refs -> refs
    end
  end

  defp acceptance_test_refs(plan) do
    (plan["acceptance_criteria"] || [])
    |> Enum.flat_map(fn ac -> ac["required_test_refs"] || [] end)
    |> Enum.uniq()
  end

  # --- junit parsing --------------------------------------------------------

  defp parse_testcases(xml) do
    paired =
      @paired_testcase
      |> Regex.scan(xml)
      |> Enum.map(fn [_full, attrs, body] -> testcase(attrs, body) end)

    self_closing =
      @self_closing_testcase
      |> Regex.scan(xml)
      |> Enum.map(fn [_full, attrs] -> testcase(attrs, "") end)

    paired ++ self_closing
  end

  defp testcase(attrs_str, body) do
    attrs = attrs(attrs_str)
    name = Map.fetch!(attrs, "name")
    classname = Map.get(attrs, "classname")

    status =
      cond do
        String.contains?(body, "<failure") or String.contains?(body, "<error") -> :failed
        String.contains?(body, "<skipped") -> :skipped
        true -> :passed
      end

    %{
      id: nodeid(classname, name),
      name: name,
      status: status,
      message: failure_message(status, body)
    }
  end

  defp attrs(attrs_str) do
    @attr
    |> Regex.scan(attrs_str)
    |> Map.new(fn [_full, key, value] -> {key, value} end)
  end

  defp nodeid(classname, name) when classname in [nil, ""], do: name
  defp nodeid(classname, name), do: String.replace(classname, ".", "/") <> ".py::" <> name

  defp failure_message(:failed, body), do: body |> String.trim() |> String.slice(0, 500)
  defp failure_message(_status, _body), do: nil
end
