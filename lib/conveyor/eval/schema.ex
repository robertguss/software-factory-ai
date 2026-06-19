defmodule Conveyor.Eval.Schema do
  @moduledoc """
  Shared jsv schema-validation helper for eval artifacts.

  Resolves a schema id (e.g. `"conveyor.eval_scorecard@1"`) to
  `docs/schemas/<id>.json`, builds a validator, and validates a decoded map.
  Mirrors the jsv usage in `Conveyor.PlanContract` so the eval namespace does not
  re-roll its own validation. Build is cached per schema id (validators are pure
  for a given schema file within a release).
  """

  @schemas_dir Path.expand("../../../docs/schemas", __DIR__)

  @doc "Absolute path to a schema file by id (without the `.json` suffix)."
  @spec path(String.t()) :: String.t()
  def path(schema_id), do: Path.join(@schemas_dir, schema_id <> ".json")

  @doc "Whether a schema file exists on disk for `schema_id`."
  @spec exists?(String.t()) :: boolean()
  def exists?(schema_id), do: schema_id |> path() |> File.exists?()

  @doc """
  Validate `map` against the schema id.

  Returns `:ok` or `{:error, normalized_error}`. Raises if the schema file is
  missing or malformed — that is a build error in the eval program, not a data
  error, and should fail loudly.
  """
  @spec validate(map(), String.t()) :: :ok | {:error, term()}
  def validate(map, schema_id) do
    case JSV.validate(map, root(schema_id)) do
      {:ok, _validated} -> :ok
      {:error, error} -> {:error, JSV.normalize_error(error)}
    end
  end

  @doc "Like `validate/2` but raises `ArgumentError` on validation failure."
  @spec validate!(map(), String.t()) :: :ok
  def validate!(map, schema_id) do
    case validate(map, schema_id) do
      :ok -> :ok
      {:error, error} -> raise ArgumentError, "#{schema_id} failed validation: #{inspect(error)}"
    end
  end

  # Build + cache the jsv root for a schema id. Cached in :persistent_term keyed
  # by id so repeated validations (e.g. a corpus replay) don't rebuild.
  defp root(schema_id) do
    key = {__MODULE__, :root, schema_id}

    case :persistent_term.get(key, :none) do
      :none ->
        built =
          schema_id |> path() |> File.read!() |> Jason.decode!() |> JSV.build!(warnings: :silent)

        :persistent_term.put(key, built)
        built

      built ->
        built
    end
  end
end
