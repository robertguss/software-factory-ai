defmodule Conveyor.PlanContract do
  @moduledoc """
  Loads and validates normalized Conveyor plan contracts.

  A human-readable plan explains intent, but the normalized `conveyor.plan@1`
  contract is the execution surface. This module accepts either a sidecar
  `conveyor.plan.yml`/`.yaml`/`.json` next to a markdown plan or a fenced
  `conveyor-plan@1` block embedded in the markdown file.
  """

  @supported_schema_version "conveyor.plan@1"
  @sidecar_names ["conveyor.plan.yml", "conveyor.plan.yaml", "conveyor.plan.json"]
  @schema_path Path.expand("../../docs/schemas/conveyor.plan@1.json", __DIR__)

  defmodule Result do
    @moduledoc "Validated normalized plan contract."

    @type t :: %__MODULE__{
            source_path: Path.t(),
            contract: map(),
            contract_sha256: String.t()
          }

    @enforce_keys [:source_path, :contract, :contract_sha256]
    defstruct [:source_path, :contract, :contract_sha256]
  end

  defmodule Error do
    @moduledoc "Plan contract loading or validation error."

    @type code ::
            :file_error
            | :decode_error
            | :missing_normalized_contract
            | :unsupported_schema_version
            | :schema_validation_failed
            | :invalid_work_dependencies

    @type t :: %__MODULE__{
            code: code(),
            message: String.t(),
            source_path: Path.t() | nil,
            details: term()
          }

    @enforce_keys [:code, :message]
    defstruct [:code, :message, :source_path, :details]
  end

  @spec load(Path.t()) :: {:ok, Result.t()} | {:error, Error.t()}
  def load(path) do
    path = Path.expand(path)

    with {:ok, source_path, content, format} <- read_source(path),
         {:ok, contract} <- decode(content, format, source_path),
         :ok <- check_schema_version(contract, source_path),
         :ok <- validate_schema(contract, source_path),
         :ok <- validate_work_dependencies(contract, source_path) do
      {:ok,
       %Result{
         source_path: source_path,
         contract: contract,
         contract_sha256: sha256(canonical_json(contract))
       }}
    end
  end

  @spec supported_schema_version() :: String.t()
  def supported_schema_version, do: @supported_schema_version

  defp read_source(path) do
    cond do
      Path.extname(path) in [".json", ".yml", ".yaml"] ->
        read_contract_file(path)

      sidecar = find_sidecar(path) ->
        read_contract_file(sidecar)

      true ->
        read_fenced_contract(path)
    end
  end

  defp read_contract_file(path) do
    case File.read(path) do
      {:ok, content} -> {:ok, path, content, format_for(path)}
      {:error, reason} -> {:error, error(:file_error, "cannot read #{path}: #{reason}", path)}
    end
  end

  defp read_fenced_contract(path) do
    with {:ok, markdown} <- File.read(path),
         {:ok, body, format} <- extract_fenced_contract(markdown) do
      {:ok, path, body, format}
    else
      {:error, %Error{} = error} ->
        {:error, error}

      {:error, reason} ->
        {:error, error(:file_error, "cannot read #{path}: #{reason}", path)}

      :error ->
        {:error,
         error(
           :missing_normalized_contract,
           "missing conveyor.plan.yml sidecar or fenced conveyor-plan@1 block",
           path
         )}
    end
  end

  defp find_sidecar(path) do
    dir = Path.dirname(path)

    Enum.find_value(@sidecar_names, fn name ->
      candidate = Path.join(dir, name)
      if File.regular?(candidate), do: candidate
    end)
  end

  defp extract_fenced_contract(markdown) do
    fence = ~r/^```(?<info>[^\n`]*)\n(?<body>.*?)(?:\n|\r\n)```/ms

    fence
    |> Regex.scan(markdown, capture: :all_names)
    |> Enum.find_value(:error, fn [body, info] ->
      if info =~ "conveyor-plan@1" do
        {:ok, body, fence_format(info)}
      end
    end)
  end

  defp fence_format(info) do
    if info =~ "json", do: :json, else: :yaml
  end

  defp format_for(path) do
    case Path.extname(path) do
      ".json" -> :json
      _other -> :yaml
    end
  end

  defp decode(content, :json, source_path) do
    case Jason.decode(content) do
      {:ok, decoded} when is_map(decoded) ->
        {:ok, decoded}

      {:ok, _decoded} ->
        {:error, error(:decode_error, "plan contract must decode to an object", source_path)}

      {:error, error} ->
        {:error, error(:decode_error, "invalid JSON: #{Exception.message(error)}", source_path)}
    end
  end

  defp decode(content, :yaml, source_path) do
    case YamlElixir.read_from_string(content) do
      {:ok, decoded} when is_map(decoded) ->
        {:ok, decoded}

      {:ok, _decoded} ->
        {:error, error(:decode_error, "plan contract must decode to an object", source_path)}

      {:error, error} ->
        {:error, error(:decode_error, "invalid YAML: #{Exception.message(error)}", source_path)}
    end
  end

  defp check_schema_version(%{"schema_version" => @supported_schema_version}, _source_path),
    do: :ok

  defp check_schema_version(%{"schema_version" => version}, source_path) do
    {:error,
     error(
       :unsupported_schema_version,
       "unsupported plan schema_version #{inspect(version)}",
       source_path
     )}
  end

  defp check_schema_version(_contract, source_path) do
    {:error,
     error(
       :unsupported_schema_version,
       "missing plan schema_version; expected #{@supported_schema_version}",
       source_path
     )}
  end

  defp validate_schema(contract, source_path) do
    schema = @schema_path |> File.read!() |> Jason.decode!()
    root = JSV.build!(schema, warnings: :silent)

    case JSV.validate(contract, root) do
      {:ok, _validated} ->
        :ok

      {:error, validation_error} ->
        {:error,
         error(
           :schema_validation_failed,
           "plan contract failed schema validation",
           source_path,
           JSV.normalize_error(validation_error)
         )}
    end
  end

  # Semantic validation the JSON schema cannot express: work_dependencies edges must
  # reference existing slices, must not self-loop, and must form a DAG. Without this a
  # schema-valid-but-broken hand-authored graph (dangling ref, self-loop, or cycle)
  # would either be silently dropped (dangling) or crash SerialDriver.do_topo mid-run
  # AFTER Project/Plan/Epic/Slice records are created. Failing here keeps it a clean,
  # pre-execution load error.
  defp validate_work_dependencies(contract, source_path) do
    deps = Map.get(contract, "work_dependencies", [])

    slice_keys =
      contract
      |> Map.get("slices", [])
      |> Enum.map(&Map.get(&1, "key"))
      |> MapSet.new()

    with :ok <- check_dependency_refs(deps, slice_keys, source_path),
         :ok <- check_no_self_loops(deps, source_path) do
      check_dependencies_acyclic(deps, source_path)
    end
  end

  defp check_dependency_refs(deps, slice_keys, source_path) do
    unknown =
      deps
      |> Enum.flat_map(fn dep -> [dep["from"], dep["to"]] end)
      |> Enum.reject(&MapSet.member?(slice_keys, &1))
      |> Enum.uniq()

    case unknown do
      [] ->
        :ok

      keys ->
        {:error,
         error(
           :invalid_work_dependencies,
           "work_dependencies reference unknown slice(s): #{Enum.join(keys, ", ")}",
           source_path,
           %{unknown_slices: keys}
         )}
    end
  end

  defp check_no_self_loops(deps, source_path) do
    self_loops =
      deps
      |> Enum.filter(&(&1["from"] == &1["to"]))
      |> Enum.map(& &1["from"])
      |> Enum.uniq()

    case self_loops do
      [] ->
        :ok

      keys ->
        {:error,
         error(
           :invalid_work_dependencies,
           "work_dependencies contain self-loop(s) on slice(s): #{Enum.join(keys, ", ")}",
           source_path,
           %{self_loops: keys}
         )}
    end
  end

  defp check_dependencies_acyclic(deps, source_path) do
    edges = Enum.map(deps, &{&1["from"], &1["to"]})
    nodes = edges |> Enum.flat_map(fn {from, to} -> [from, to] end) |> Enum.uniq()

    if topological_remainder(MapSet.new(nodes), edges) == 0 do
      :ok
    else
      {:error,
       error(
         :invalid_work_dependencies,
         "work_dependencies contain a cycle (no topological order exists)",
         source_path,
         %{cyclic: true}
       )}
    end
  end

  # Kahn-style peel: each round removes every node with no remaining incoming edge.
  # Returns the count of nodes left unremoved — 0 iff the graph is acyclic.
  defp topological_remainder(remaining, edges) do
    has_incoming =
      edges
      |> Enum.filter(fn {from, to} ->
        MapSet.member?(remaining, from) and MapSet.member?(remaining, to)
      end)
      |> Enum.map(fn {_from, to} -> to end)
      |> MapSet.new()

    ready = Enum.reject(remaining, &MapSet.member?(has_incoming, &1))

    case ready do
      [] -> MapSet.size(remaining)
      _ -> topological_remainder(MapSet.difference(remaining, MapSet.new(ready)), edges)
    end
  end

  defp canonical_json(value) when is_map(value) do
    body =
      value
      |> Enum.sort_by(fn {key, _value} -> key end)
      |> Enum.map(fn {key, nested} -> Jason.encode!(key) <> ":" <> canonical_json(nested) end)
      |> Enum.join(",")

    "{" <> body <> "}"
  end

  defp canonical_json(value) when is_list(value) do
    "[" <> Enum.map_join(value, ",", &canonical_json/1) <> "]"
  end

  defp canonical_json(value), do: Jason.encode!(value)

  defp sha256(content) do
    "sha256:" <> Base.encode16(:crypto.hash(:sha256, content), case: :lower)
  end

  defp error(code, message, source_path, details \\ nil) do
    %Error{code: code, message: message, source_path: source_path, details: details}
  end
end
