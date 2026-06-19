defmodule Conveyor.Eval.WorkGraphToStationPlan do
  @moduledoc """
  MINIMAL, ON-PATH lowering of a `work_graph@2` Slice into a provisional executable
  `station_plan` (idea #2, the bridge).

  > **Divergence (read `docs/3_evals/IMPLEMENTATION-PLAN-RUNGS-0-1.md` §B2).**
  > `station_plan` is **not** the architecture's intended runtime form. The program
  > plan intends `Source → Intent → Candidate → Work → Contract → Authority`
  > (ADR-14), where the `Work → Contract` lowering is owned by the **P2-B Contract
  > Forge**, producing `ContractLock + AgentBrief` (+ `TestPack`). This module is a
  > stand-in for that eventual contract: ContractLock issuance, hierarchical
  > approval, RoleView compilation, and TestPack forging are **deferred to P2-B**.
  > The lowering **code is permanent** (on the real path); the **contract content is
  > crude** (tracer-sanctioned).

  Pure (ADR-14): a function of the `work_graph` + `run_spec_sha256` only — no
  Repo/FS/env/clock/RNG; deterministic; declared inputs only. The output matches the
  runtime validator `Conveyor.Factory.StationPlan.validate/2` (per station: `key`,
  `input`, `output`, with `input["run_spec_sha256"] == output["run_spec_sha256"] ==
  run_spec_sha256`) — NOT the unused `conveyor.station_plan@1.json` schema.

  Tracer scope: one Slice lowered into a fixed `["agent", "verify"]` station
  sequence. Multi-station ordering would use execution-hard edges only (ADR-16).
  """

  alias Conveyor.CanonicalJson

  @doc """
  Lower a single-slice `work_graph@2` into a provisional `station_plan` bound to
  `run_spec_sha256`. Returns `{:ok, station_plan}` or `{:error, reason}`.
  """
  @spec lower(map(), String.t(), keyword()) :: {:ok, map()} | {:error, map()}
  def lower(work_graph, run_spec_sha256, _opts \\ []) do
    with {:ok, slice} <- single_slice(work_graph) do
      io = %{"run_spec_sha256" => run_spec_sha256, "artifact_refs" => []}

      {:ok,
       %{
         "schema_version" => "conveyor.station_plan@1",
         "stations" => [
           %{"key" => "agent", "kind" => "agent", "input" => io, "output" => io},
           %{"key" => "verify", "kind" => "verify", "input" => io, "output" => io}
         ],
         # Provenance back-link to the IR, so the run is traceable to the plan.
         "work_graph_digest" => CanonicalJson.digest(work_graph),
         "slice_stable_key" => fetch(slice, "stable_key")
       }}
    end
  end

  defp single_slice(work_graph) do
    case fetch(work_graph, "slices") do
      [slice] ->
        {:ok, slice}

      [_ | _] = slices ->
        {:error, %{reason: :multi_slice_unsupported, slice_count: length(slices)}}

      _ ->
        {:error, %{reason: :no_slices}}
    end
  end

  # work_graph@2 from lower/2 is atom-keyed; a JSON round-trip is string-keyed. Accept both.
  defp fetch(map, key) when is_map(map),
    do: Map.get(map, key) || Map.get(map, String.to_atom(key))

  defp fetch(_map, _key), do: nil
end
