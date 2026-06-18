defmodule Conveyor.Policy.Profiles do
  @moduledoc """
  Loads Conveyor policy profile TOML files into Policy records.
  """

  alias Conveyor.Config.ValidationError
  alias Conveyor.Factory
  alias Conveyor.Factory.Policy

  @required_profiles [:explore, :implement, :verify, :release, :maintenance]
  @profile_strings Enum.map(@required_profiles, &Atom.to_string/1)

  @spec load_dir!(Path.t()) :: [Policy.t()]
  def load_dir!(policy_dir) do
    policy_dir
    |> load_dir()
    |> case do
      {:ok, policies} -> policies
      {:error, error} -> raise error
    end
  end

  @spec load_dir(Path.t()) :: {:ok, [Policy.t()]} | {:error, ValidationError.t()}
  def load_dir(policy_dir) do
    policy_dir
    |> Path.join("*.toml")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.reduce_while({:ok, []}, &parse_policy_file/2)
    |> case do
      {:ok, attrs} ->
        with :ok <- require_complete_profile_set(attrs) do
          {:ok, attrs |> Enum.map(&upsert_policy!/1) |> sort_profiles()}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  defp parse_policy_file(path, {:ok, acc}) do
    case parse_policy_file(path) do
      {:ok, attrs} -> {:cont, {:ok, [attrs | acc]}}
      {:error, error} -> {:halt, {:error, error}}
    end
  end

  defp parse_policy_file(path) do
    with {:ok, content} <- read_file(path),
         {:ok, decoded} <- decode_toml(content),
         {:ok, policy} <- required_map(decoded, ["policy"]),
         {:ok, name} <- required_string(policy, ["policy", "name"]),
         {:ok, profile} <- required_profile(policy),
         {:ok, autonomy_ceiling} <- required_autonomy_ceiling(policy),
         {:ok, allowlist} <-
           optional_string_list(policy, "allowlist", [], ["policy", "allowlist"]),
         {:ok, denylist} <- optional_string_list(policy, "denylist", [], ["policy", "denylist"]),
         {:ok, network} <- optional_string(policy, "network", "none", ["policy", "network"]) do
      future_gated? =
        Map.get(policy, "future_gated", profile in [:release, :maintenance])

      budget_policy =
        policy
        |> Map.get("budget", %{})
        |> Map.put("future_gated", future_gated?)

      {:ok,
       %{
         name: name,
         profile: profile,
         allowlist: allowlist,
         denylist: denylist,
         env_policy: Map.get(policy, "env", %{}),
         network_policy: %{"default" => network},
         budget_policy: budget_policy,
         autonomy_ceiling: autonomy_ceiling
       }}
    end
  end

  defp upsert_policy!(attrs) do
    case existing_policy(attrs.profile) do
      nil -> Ash.create!(Policy, attrs, domain: Factory)
      policy -> Ash.update!(policy, attrs, domain: Factory)
    end
  end

  defp existing_policy(profile) do
    Policy
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.profile == profile))
  end

  defp sort_profiles(policies) do
    Enum.sort_by(
      policies,
      &Enum.find_index(@required_profiles, fn profile -> profile == &1.profile end)
    )
  end

  defp require_complete_profile_set(attrs) do
    present = MapSet.new(attrs, & &1.profile)

    missing =
      @required_profiles
      |> Enum.reject(&MapSet.member?(present, &1))

    if missing == [] do
      :ok
    else
      {:error,
       ValidationError.invalid(
         ["policy"],
         "missing policy profiles: #{missing |> Enum.map(&Atom.to_string/1) |> Enum.join(", ")}"
       )}
    end
  end

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

  defp required_profile(policy) do
    with {:ok, profile} <- required_string(policy, ["policy", "profile"]) do
      if profile in @profile_strings do
        {:ok, String.to_existing_atom(profile)}
      else
        {:error,
         ValidationError.invalid(
           ["policy", "profile"],
           "one of #{Enum.join(@profile_strings, ", ")}"
         )}
      end
    end
  end

  defp required_autonomy_ceiling(policy) do
    with {:ok, value} <- required_string(policy, ["policy", "autonomy_ceiling"]) do
      case value do
        "L" <> level when level in ["0", "1", "2", "3", "4"] ->
          {:ok, String.to_integer(level)}

        _other ->
          {:error,
           ValidationError.invalid(["policy", "autonomy_ceiling"], "L0, L1, L2, L3, or L4")}
      end
    end
  end

  defp required_map(map, path), do: required_value(map, path, &is_map/1, "table")

  defp required_string(map, path) do
    required_value(map, path, &(is_binary(&1) and String.trim(&1) != ""), "non-empty string")
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

  defp optional_string(map, key, default, path) do
    case Map.fetch(map, key) do
      {:ok, value} when is_binary(value) -> {:ok, value}
      :error -> {:ok, default}
      {:ok, _value} -> {:error, ValidationError.invalid(path, "string")}
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
end
