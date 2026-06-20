defmodule Conveyor.RunSpecForge do
  @moduledoc """
  Forges immutable retry RunSpecs from the previous attempt's frozen spec.
  """

  alias Conveyor.Factory
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.RunSpec

  @spec forge_retry!(RunAttempt.t(), RunSpec.t(), keyword()) :: RunSpec.t()
  def forge_retry!(%RunAttempt{} = prior_attempt, %RunSpec{} = prior_spec, opts \\ []) do
    if prior_attempt.run_spec_id != prior_spec.id do
      raise ArgumentError, "prior RunSpec must belong to the prior RunAttempt"
    end

    attempt_no = prior_attempt.attempt_no + 1
    rung = Keyword.get(opts, :rung, %{"rung" => "same_effort", "agent_profile_patch" => %{}})
    run_spec_sha256 = run_spec_digest(prior_spec, attempt_no, rung)
    station_plan = station_plan_for_attempt(prior_spec.station_plan, run_spec_sha256)

    Ash.create!(
      RunSpec,
      %{
        slice_id: prior_spec.slice_id,
        attempt_no: attempt_no,
        run_spec_json_ref:
          "artifacts/run-specs/#{prior_spec.slice_id}-attempt-#{attempt_no}.json",
        run_spec_sha256: run_spec_sha256,
        base_commit: prior_spec.base_commit,
        contract_lock_sha256: prior_spec.contract_lock_sha256,
        prompt_template_version: prior_spec.prompt_template_version,
        agent_profile_snapshot: agent_profile_snapshot(prior_spec, rung),
        policy_sha256: prior_spec.policy_sha256,
        diff_policy_sha256: prior_spec.diff_policy_sha256,
        test_pack_sha256: prior_spec.test_pack_sha256,
        station_plan: station_plan,
        station_plan_sha256: Conveyor.CanonicalJson.digest(station_plan),
        container_image_ref: prior_spec.container_image_ref,
        container_image_digest: prior_spec.container_image_digest,
        sandbox_profile: prior_spec.sandbox_profile,
        budget_sha256: prior_spec.budget_sha256,
        code_quality_profile: prior_spec.code_quality_profile,
        canary_suite_version: prior_spec.canary_suite_version
      },
      domain: Factory
    )
  end

  defp run_spec_digest(prior_spec, attempt_no, rung) do
    Conveyor.CanonicalJson.digest(%{
      "prior_run_spec_id" => prior_spec.id,
      "slice_id" => prior_spec.slice_id,
      "attempt_no" => attempt_no,
      "base_commit" => prior_spec.base_commit,
      "contract_lock_sha256" => prior_spec.contract_lock_sha256,
      "rung" => Map.get(rung, "rung")
    })
  end

  defp station_plan_for_attempt(%{"stations" => stations} = station_plan, run_spec_sha256) do
    Map.put(
      station_plan,
      "stations",
      Enum.map(stations, &station_for_attempt(&1, run_spec_sha256))
    )
  end

  defp station_for_attempt(station, run_spec_sha256) do
    station
    |> Map.update("input", %{"run_spec_sha256" => run_spec_sha256}, fn input ->
      Map.put(input, "run_spec_sha256", run_spec_sha256)
    end)
    |> Map.update("output", %{"run_spec_sha256" => run_spec_sha256}, fn output ->
      Map.put(output, "run_spec_sha256", run_spec_sha256)
    end)
  end

  defp agent_profile_snapshot(prior_spec, rung) do
    Map.merge(prior_spec.agent_profile_snapshot, Map.get(rung, "agent_profile_patch", %{}))
  end
end
