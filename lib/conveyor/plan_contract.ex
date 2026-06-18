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
         :ok <- validate_schema(contract, source_path) do
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
