defmodule Conveyor.Planning.RunSpecAssembler do
  @moduledoc """
  Builds the immutable RunSpec for one production width-1 slice attempt.
  """

  alias Conveyor.CanonicalJson
  alias Conveyor.Factory

  alias Conveyor.Factory.{
    ContractLock,
    Epic,
    Plan,
    Project,
    RunSpec,
    Slice,
    TestPack
  }

  alias Conveyor.Planning.WorkGraphToStationPlan

  @doc """
  Assemble and persist a `RunSpec` for a single slice.

  Required opts:

    * `:work_graph` - the single-slice work graph to lower.

  Runtime opts such as `:workspace_path`, `:base_commit`, `:blob_root`,
  `:patch_ref`, `:plan_path`, and `:agent_adapter` override derived defaults.
  """
  @spec assemble!(Slice.t() | Ecto.UUID.t(), keyword()) :: RunSpec.t()
  def assemble!(slice_or_id, opts \\ [])

  def assemble!(%Slice{} = slice, opts) do
    work_graph = Keyword.fetch!(opts, :work_graph)
    context = context_for!(slice)
    workspace_path = Keyword.get(opts, :workspace_path, context.project.local_path)
    base_commit = Keyword.get_lazy(opts, :base_commit, fn -> git_head!(workspace_path) end)
    attempt_no = Keyword.get(opts, :attempt_no, 1)
    blob_root = Keyword.get(opts, :blob_root, ".conveyor/blobs")

    run_spec_sha256 =
      Keyword.get_lazy(opts, :run_spec_sha256, fn ->
        run_spec_digest(slice, work_graph, base_commit, attempt_no)
      end)

    station_plan =
      work_graph
      |> WorkGraphToStationPlan.lower(run_spec_sha256)
      |> case do
        {:ok, plan} -> augment_station_plan(plan, workspace_path, base_commit, blob_root, opts)
        {:error, reason} -> raise ArgumentError, "cannot assemble RunSpec: #{inspect(reason)}"
      end

    Ash.create!(
      RunSpec,
      run_spec_attrs(
        slice,
        context,
        base_commit,
        attempt_no,
        run_spec_sha256,
        station_plan,
        opts
      ),
      domain: Factory
    )
  end

  def assemble!(slice_id, opts) when is_binary(slice_id) do
    slice_id
    |> get_by_id!(Slice)
    |> assemble!(opts)
  end

  defp augment_station_plan(plan, workspace_path, base_commit, blob_root, opts) do
    patch_ref = Keyword.get(opts, :patch_ref)
    plan_path = Keyword.get(opts, :plan_path, Path.join(workspace_path, "conveyor.plan.yml"))
    adapter = Keyword.get(opts, :agent_adapter)

    stations =
      Enum.map(plan["stations"], fn station ->
        extra =
          case station["key"] do
            "context_scout" ->
              %{}

            "baseline_health" ->
              %{"blob_root" => blob_root}

            "acceptance_calibration" ->
              %{"blob_root" => blob_root}

            "implement" ->
              %{
                "workspace_path" => workspace_path,
                "base_commit" => base_commit,
                "blob_root" => blob_root
              }
              |> maybe_put("patch_ref", patch_ref)
              |> maybe_put("adapter", module_name(adapter))

            "verify" ->
              %{"workspace_path" => workspace_path, "plan_path" => plan_path}

            "record_evidence" ->
              %{"blob_root" => blob_root}

            _ ->
              %{}
          end

        Map.update!(station, "input", &Map.merge(&1, extra))
      end)

    %{plan | "stations" => stations}
  end

  defp run_spec_attrs(
         slice,
         context,
         base_commit,
         attempt_no,
         run_spec_sha256,
         station_plan,
         opts
       ) do
    contract_lock = latest_contract_lock(slice.id)
    test_pack = latest_test_pack(slice.id)

    %{
      slice_id: slice.id,
      attempt_no: attempt_no,
      run_spec_json_ref:
        Keyword.get(
          opts,
          :run_spec_json_ref,
          "artifacts/run-specs/#{slice.id}-attempt-#{attempt_no}.json"
        ),
      run_spec_sha256: run_spec_sha256,
      base_commit: base_commit,
      contract_lock_sha256:
        Keyword.get_lazy(opts, :contract_lock_sha256, fn ->
          contract_lock_sha256(contract_lock, context.plan)
        end),
      prompt_template_version:
        Keyword.get(opts, :prompt_template_version, "implementation-prompt@1"),
      agent_profile_snapshot:
        Keyword.get(opts, :agent_profile_snapshot, %{
          "adapter" =>
            module_name(Keyword.get(opts, :agent_adapter)) || "Conveyor.AgentRunner.Codex"
        }),
      policy_sha256:
        Keyword.get_lazy(opts, :policy_sha256, fn -> policy_sha256(contract_lock) end),
      diff_policy_sha256: Keyword.get(opts, :diff_policy_sha256, digest("diff-policy")),
      test_pack_sha256:
        Keyword.get_lazy(opts, :test_pack_sha256, fn -> test_pack_sha256(test_pack) end),
      station_plan: station_plan,
      station_plan_sha256: CanonicalJson.digest(station_plan),
      container_image_ref:
        Keyword.get(
          opts,
          :container_image_ref,
          "ghcr.io/conveyor/sample-python-runner:2026-06-17"
        ),
      container_image_digest: Keyword.get(opts, :container_image_digest, digest("image")),
      sandbox_profile: Keyword.get(opts, :sandbox_profile, "verify"),
      budget_sha256: Keyword.get(opts, :budget_sha256, digest("budget")),
      code_quality_profile:
        Keyword.get(opts, :code_quality_profile, context.project.code_quality_profile),
      canary_suite_version: Keyword.get(opts, :canary_suite_version, "canary@1")
    }
  end

  defp context_for!(slice) do
    epic = get_by_id!(slice.epic_id, Epic)
    plan = get_by_id!(epic.plan_id, Plan)
    project = get_by_id!(plan.project_id, Project)
    %{epic: epic, plan: plan, project: project}
  end

  defp latest_contract_lock(slice_id) do
    ContractLock
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.slice_id == slice_id))
    |> Enum.sort_by(&DateTime.to_unix(&1.locked_at, :microsecond), :desc)
    |> List.first()
  end

  defp latest_test_pack(slice_id) do
    TestPack
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.slice_id == slice_id))
    |> Enum.sort_by(&{&1.version, DateTime.to_unix(&1.locked_at, :microsecond)}, :desc)
    |> List.first()
  end

  defp contract_lock_sha256(nil, plan), do: plan.contract_sha256

  defp contract_lock_sha256(%ContractLock{} = lock, _plan) do
    lock
    |> Map.take([
      :plan_contract_sha256,
      :brief_sha256,
      :acceptance_criteria_sha256,
      :required_tests_sha256,
      :test_pack_sha256,
      :verification_commands_sha256,
      :agents_md_sha256,
      :policy_sha256
    ])
    |> CanonicalJson.digest()
  end

  defp policy_sha256(%ContractLock{policy_sha256: sha256}), do: sha256
  defp policy_sha256(nil), do: digest("policy")

  defp test_pack_sha256(%TestPack{test_pack_sha256: sha256}), do: sha256
  defp test_pack_sha256(nil), do: digest("test-pack")

  defp run_spec_digest(slice, work_graph, base_commit, attempt_no) do
    CanonicalJson.digest(%{
      "schema_version" => "conveyor.run_spec_seed@1",
      "slice_id" => slice.id,
      "attempt_no" => attempt_no,
      "base_commit" => base_commit,
      "work_graph_digest" => CanonicalJson.digest(work_graph)
    })
  end

  defp git_head!(workspace_path) do
    {output, 0} =
      System.cmd("git", ["-C", workspace_path, "rev-parse", "HEAD"], stderr_to_stdout: true)

    String.trim(output)
  end

  defp get_by_id!(id, resource) do
    resource
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == id)) ||
      raise ArgumentError, "#{inspect(resource)} #{id} was not found"
  end

  defp module_name(nil), do: nil
  defp module_name(module) when is_atom(module), do: inspect(module)
  defp module_name(module) when is_binary(module), do: String.trim_leading(module, "Elixir.")

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
