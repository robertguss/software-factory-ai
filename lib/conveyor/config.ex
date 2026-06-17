defmodule Conveyor.Config do
  @moduledoc "Runtime configuration service and project config loader."
  use Conveyor.Conductor.Child

  alias Conveyor.Config.CommandSpec
  alias Conveyor.Config.ProjectConfig
  alias Conveyor.Config.ValidationError

  @profiles ~w(explore implement verify release maintenance)
  @autonomy_levels ~w(L0 L1 L2 L3 L4)
  @networks ~w(none loopback egress)
  @result_formats ~w(junit tap json stdout custom)

  @spec default_path(Path.t()) :: Path.t()
  def default_path(root_path \\ File.cwd!()) do
    Path.join([root_path, ".conveyor", "config.toml"])
  end

  @spec load(Path.t()) :: {:ok, ProjectConfig.t()} | {:error, ValidationError.t()}
  def load(path \\ default_path()) do
    with {:ok, content} <- read_file(path),
         {:ok, decoded} <- decode_toml(content),
         {:ok, config} <- validate(decoded) do
      {:ok, config}
    end
  end

  @spec load!(Path.t()) :: ProjectConfig.t()
  def load!(path \\ default_path()) do
    case load(path) do
      {:ok, config} -> config
      {:error, error} -> raise error
    end
  end

  @spec validate(map()) :: {:ok, ProjectConfig.t()} | {:error, ValidationError.t()}
  def validate(decoded) when is_map(decoded) do
    with {:ok, project} <- required_map(decoded, ["project"]),
         {:ok, command_specs} <- required_list(project, ["project", "command_specs"]),
         {:ok, parsed_commands} <- validate_command_specs(command_specs),
         {:ok, name} <- required_string(project, ["project", "name"]),
         {:ok, repo_path} <- required_string(project, ["project", "repo_path"]),
         {:ok, default_branch} <- required_string(project, ["project", "default_branch"]),
         {:ok, autonomy} <-
           required_enum(project, ["project", "default_autonomy_level"], @autonomy_levels),
         {:ok, policies_dir} <- required_string(project, ["project", "policies_dir"]),
         {:ok, prompts_dir} <- required_string(project, ["project", "prompts_dir"]),
         {:ok, runs_dir} <- required_string(project, ["project", "runs_dir"]),
         {:ok, blobs_dir} <- required_string(project, ["project", "blobs_dir"]),
         {:ok, quality_adapter} <- required_string(project, ["project", "quality_adapter"]) do
      {:ok,
       %ProjectConfig{
         name: name,
         repo_path: repo_path,
         default_branch: default_branch,
         dev_branch: optional_string_value(project, "dev_branch"),
         default_autonomy_level: String.to_atom(autonomy),
         policies_dir: policies_dir,
         prompts_dir: prompts_dir,
         runs_dir: runs_dir,
         blobs_dir: blobs_dir,
         quality_adapter: quality_adapter,
         sample_repo_path: optional_string_value(project, "sample_repo_path"),
         sample_base_ref: optional_string_value(project, "sample_base_ref"),
         command_specs: parsed_commands
       }}
    end
  end

  def validate(_decoded), do: {:error, ValidationError.invalid([], "TOML document map")}

  defp read_file(path) do
    case File.read(path) do
      {:ok, content} -> {:ok, content}
      {:error, reason} -> {:error, ValidationError.file_error(path, reason)}
    end
  end

  defp decode_toml(content) do
    case TomlElixir.decode(content) do
      {:ok, decoded} when is_map(decoded) -> {:ok, decoded}
      {:error, reason} -> {:error, ValidationError.parse_error(inspect(reason))}
    end
  rescue
    error -> {:error, ValidationError.parse_error(Exception.message(error))}
  end

  defp validate_command_specs([]) do
    {:error, ValidationError.invalid(["project", "command_specs"], "non-empty list")}
  end

  defp validate_command_specs(command_specs) do
    command_specs
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {command_spec, index}, {:ok, acc} ->
      case validate_command_spec(command_spec, index) do
        {:ok, parsed} -> {:cont, {:ok, [parsed | acc]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, parsed} -> {:ok, Enum.reverse(parsed)}
      {:error, error} -> {:error, error}
    end
  end

  defp validate_command_spec(command_spec, index) when is_map(command_spec) do
    root = ["project", "command_specs", Integer.to_string(index)]

    with {:ok, key} <- required_string(command_spec, root ++ ["key"]),
         {:ok, argv} <- required_string_list(command_spec, root ++ ["argv"]),
         {:ok, profile} <- required_enum(command_spec, root ++ ["profile"], @profiles),
         {:ok, cwd} <- optional_string(command_spec, "cwd", ".", root ++ ["cwd"]),
         {:ok, required} <- optional_boolean(command_spec, "required", true, root ++ ["required"]),
         {:ok, timeout_ms} <-
           optional_positive_integer(command_spec, "timeout_ms", 120_000, root ++ ["timeout_ms"]),
         {:ok, network} <-
           optional_enum(command_spec, "network", "none", @networks, root ++ ["network"]),
         {:ok, env_allowlist} <-
           optional_string_list(command_spec, "env_allowlist", [], root ++ ["env_allowlist"]),
         {:ok, output_limit_bytes} <-
           optional_positive_integer(
             command_spec,
             "output_limit_bytes",
             2_000_000,
             root ++ ["output_limit_bytes"]
           ),
         {:ok, result_format} <-
           optional_enum(
             command_spec,
             "result_format",
             "stdout",
             @result_formats,
             root ++ ["result_format"]
           ),
         {:ok, result_adapter} <-
           optional_nullable_string(command_spec, "result_adapter", root ++ ["result_adapter"]) do
      {:ok,
       %CommandSpec{
         key: key,
         argv: argv,
         cwd: cwd,
         profile: String.to_atom(profile),
         required: required,
         timeout_ms: timeout_ms,
         network: String.to_atom(network),
         env_allowlist: env_allowlist,
         output_limit_bytes: output_limit_bytes,
         result_format: String.to_atom(result_format),
         result_adapter: result_adapter
       }}
    end
  end

  defp validate_command_spec(_command_spec, index) do
    {:error,
     ValidationError.invalid(["project", "command_specs", Integer.to_string(index)], "table")}
  end

  defp required_map(map, path), do: required_value(map, path, &is_map/1, "table")
  defp required_list(map, path), do: required_value(map, path, &is_list/1, "list")

  defp required_string(map, path),
    do: required_value(map, path, &valid_string?/1, "non-empty string")

  defp required_string_list(map, path),
    do: required_value(map, path, &valid_string_list?/1, "non-empty string list")

  defp required_enum(map, path, allowed) do
    with {:ok, value} <- required_string(map, path) do
      if value in allowed do
        {:ok, value}
      else
        {:error, ValidationError.invalid(path, "one of #{Enum.join(allowed, ", ")}")}
      end
    end
  end

  defp required_value(map, path, predicate, expected) do
    key = List.last(path)

    case Map.fetch(map, key) do
      {:ok, value} ->
        if predicate.(value) do
          {:ok, value}
        else
          {:error, ValidationError.invalid(path, expected)}
        end

      :error ->
        {:error, ValidationError.missing(path)}
    end
  end

  defp optional_string_value(map, key, default \\ nil) do
    case Map.fetch(map, key) do
      {:ok, value} when is_binary(value) -> value
      :error -> default
      {:ok, _value} -> default
    end
  end

  defp optional_string(map, key, default, path) do
    case Map.fetch(map, key) do
      {:ok, value} when is_binary(value) -> {:ok, value}
      :error -> {:ok, default}
      {:ok, _value} -> {:error, ValidationError.invalid(path, "string")}
    end
  end

  defp optional_boolean(map, key, default, path) do
    case Map.fetch(map, key) do
      {:ok, value} when is_boolean(value) -> {:ok, value}
      :error -> {:ok, default}
      {:ok, _value} -> {:error, ValidationError.invalid(path, "boolean")}
    end
  end

  defp optional_positive_integer(map, key, default, path) do
    case Map.fetch(map, key) do
      {:ok, value} when is_integer(value) and value > 0 -> {:ok, value}
      :error -> {:ok, default}
      {:ok, _value} -> {:error, ValidationError.invalid(path, "positive integer")}
    end
  end

  defp optional_enum(map, key, default, allowed, path) do
    case Map.fetch(map, key) do
      {:ok, value} when is_binary(value) ->
        if value in allowed do
          {:ok, value}
        else
          {:error, ValidationError.invalid(path, "one of #{Enum.join(allowed, ", ")}")}
        end

      :error ->
        {:ok, default}

      {:ok, _value} ->
        {:error, ValidationError.invalid(path, "one of #{Enum.join(allowed, ", ")}")}
    end
  end

  defp optional_string_list(map, key, default, path) do
    case Map.fetch(map, key) do
      {:ok, value} when is_list(value) ->
        if Enum.all?(value, &is_binary/1) do
          {:ok, value}
        else
          {:error, ValidationError.invalid(path, "string list")}
        end

      :error ->
        {:ok, default}

      {:ok, _value} ->
        {:error, ValidationError.invalid(path, "string list")}
    end
  end

  defp optional_nullable_string(map, key, path) do
    case Map.fetch(map, key) do
      {:ok, value} when is_binary(value) -> {:ok, value}
      :error -> {:ok, nil}
      {:ok, _value} -> {:error, ValidationError.invalid(path, "string")}
    end
  end

  defp valid_string?(value), do: is_binary(value) and String.trim(value) != ""

  defp valid_string_list?(value),
    do: is_list(value) and value != [] and Enum.all?(value, &valid_string?/1)
end
