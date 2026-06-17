defmodule Conveyor.AgentsMd.Linter do
  @moduledoc """
  Lints AGENTS.md against Conveyor project config and policy expectations.
  """

  alias Conveyor.AgentsMd
  alias Conveyor.Config
  alias Conveyor.Config.ProjectConfig

  defmodule Finding do
    @moduledoc "AGENTS.md lint finding."

    @type severity :: :error | :warning

    @type t :: %__MODULE__{
            severity: severity(),
            code: atom(),
            message: String.t(),
            section: String.t() | nil
          }

    @enforce_keys [:severity, :code, :message]
    defstruct [:severity, :code, :message, :section]
  end

  defmodule Result do
    @moduledoc "AGENTS.md lint result."

    @type status :: :passed | :failed

    @type t :: %__MODULE__{
            status: status(),
            findings: [Finding.t()]
          }

    @enforce_keys [:status, :findings]
    defstruct [:status, :findings]
  end

  @ambiguous_phrases ["make it good", "mobile-friendly"]

  @spec lint(Path.t()) :: {:ok, Result.t()} | {:error, Exception.t()}
  def lint(project_path) do
    with {:ok, config} <- Config.load(Config.default_path(project_path)),
         {:ok, content} <- read_agents(project_path),
         {:ok, denylist} <- load_policy_denylist(project_path, config) do
      {:ok, lint_content(content, config, denylist)}
    end
  end

  @spec lint_content(String.t(), ProjectConfig.t(), [String.t()]) :: Result.t()
  def lint_content(content, %ProjectConfig{} = config, policy_denylist \\ []) do
    findings =
      []
      |> Kernel.++(check_required_sections(content))
      |> Kernel.++(check_config_commands(content, config.command_specs))
      |> Kernel.++(check_done_criteria(content))
      |> Kernel.++(check_security_rules(content))
      |> Kernel.++(check_forbidden_actions(content, policy_denylist))
      |> Kernel.++(check_command_contradictions(content, config.command_specs))
      |> Kernel.++(check_ambiguous_phrases(content))

    %Result{status: status(findings), findings: findings}
  end

  @spec format(Result.t()) :: String.t()
  def format(%Result{status: :passed}), do: "AGENTS.md lint passed"

  def format(%Result{status: :failed, findings: findings}) do
    lines =
      Enum.map(findings, fn finding ->
        section = if finding.section, do: " [#{finding.section}]", else: ""
        "- #{finding.severity} #{finding.code}#{section}: #{finding.message}"
      end)

    Enum.join(["AGENTS.md lint failed" | lines], "\n")
  end

  defp read_agents(project_path) do
    path = Path.join(project_path, "AGENTS.md")

    case File.read(path) do
      {:ok, content} -> {:ok, content}
      {:error, reason} -> {:error, Config.ValidationError.file_error(path, reason)}
    end
  end

  defp load_policy_denylist(project_path, %ProjectConfig{policies_dir: policies_dir}) do
    path = Path.expand(policies_dir, project_path)

    if File.dir?(path) do
      denylist =
        path
        |> Path.join("*.toml")
        |> Path.wildcard()
        |> Enum.flat_map(&policy_denylist/1)
        |> Enum.uniq()

      {:ok, denylist}
    else
      {:ok, []}
    end
  end

  defp policy_denylist(path) do
    with {:ok, content} <- File.read(path),
         {:ok, decoded} <- TomlElixir.decode(content),
         %{"policy" => %{"denylist" => denylist}} when is_list(denylist) <- decoded do
      Enum.filter(denylist, &is_binary/1)
    else
      _ -> []
    end
  end

  defp check_required_sections(content) do
    Enum.flat_map(AgentsMd.required_sections(), fn section ->
      if content =~ ~r/^# #{Regex.escape(section)}\s*$/m do
        []
      else
        [finding(:error, :missing_section, "missing required section `#{section}`", section)]
      end
    end)
  end

  defp check_config_commands(content, command_specs) do
    Enum.flat_map(command_specs, fn command ->
      rendered = render_argv(command.argv)

      cond do
        not String.contains?(content, "`#{command.key}`") ->
          [
            finding(
              :error,
              :missing_config_command,
              "missing configured command key `#{command.key}`",
              "Commands"
            )
          ]

        not String.contains?(content, rendered) ->
          [
            finding(
              :error,
              :command_mismatch,
              "configured command `#{command.key}` does not show argv `#{rendered}`",
              "Commands"
            )
          ]

        true ->
          []
      end
    end)
  end

  defp check_done_criteria(content) do
    section = section(content, "Done Criteria")
    normalized = String.downcase(section)

    missing =
      [
        {"evidence", :done_missing_evidence, "Done Criteria must mention evidence"},
        {"independent verification", :done_missing_independent_verification,
         "Done Criteria must mention independent verification"}
      ]
      |> Enum.reject(fn {needle, _code, _message} -> String.contains?(normalized, needle) end)

    Enum.map(missing, fn {_needle, code, message} ->
      finding(:error, code, message, "Done Criteria")
    end)
  end

  defp check_security_rules(content) do
    section = section(content, "Security Rules")
    normalized = String.downcase(section)

    []
    |> maybe_add(
      String.contains?(normalized, "production secrets") or
        String.contains?(normalized, "prod secrets"),
      :security_missing_prod_secrets,
      "Security Rules must forbid production secrets",
      "Security Rules"
    )
    |> maybe_add(
      String.contains?(normalized, "deploy"),
      :security_missing_deploys,
      "Security Rules must forbid deploys in Phase 1",
      "Security Rules"
    )
  end

  defp check_forbidden_actions(_content, []), do: []

  defp check_forbidden_actions(content, denylist) do
    section = section(content, "Forbidden Actions")
    normalized = String.downcase(section)

    if String.contains?(normalized, "denied commands") do
      []
    else
      missing_policy_denylist(normalized, denylist)
    end
  end

  defp missing_policy_denylist(normalized, denylist) do
    denylist
    |> Enum.reject(&String.contains?(normalized, String.downcase(&1)))
    |> Enum.map(fn denied ->
      finding(
        :error,
        :missing_policy_denylist,
        "Forbidden Actions must include policy denylist item `#{denied}`",
        "Forbidden Actions"
      )
    end)
  end

  defp check_command_contradictions(content, command_specs) do
    normalized = String.downcase(content)

    command_specs
    |> Enum.flat_map(fn command ->
      key = String.downcase(command.key)
      argv = command.argv |> render_argv() |> String.downcase()

      if String.contains?(normalized, "do not run #{key}") or
           String.contains?(normalized, "do not run #{argv}") do
        [
          finding(
            :error,
            :contradictory_command,
            "AGENTS.md forbids configured command `#{command.key}`",
            "Commands"
          )
        ]
      else
        []
      end
    end)
  end

  defp check_ambiguous_phrases(content) do
    normalized = String.downcase(content)

    @ambiguous_phrases
    |> Enum.filter(&String.contains?(normalized, &1))
    |> Enum.map(fn phrase ->
      finding(
        :warning,
        :ambiguous_language,
        "ambiguous phrase `#{phrase}` should be replaced with measurable criteria"
      )
    end)
  end

  defp section(content, section) do
    pattern = ~r/^# #{Regex.escape(section)}\s*$\n(?<body>.*?)(?=^# |\z)/ms

    case Regex.named_captures(pattern, content) do
      %{"body" => body} -> body
      _ -> ""
    end
  end

  defp maybe_add(findings, true, _code, _message, _section), do: findings

  defp maybe_add(findings, false, code, message, section),
    do: [finding(:error, code, message, section) | findings]

  defp status(findings) do
    if Enum.any?(findings, &(&1.severity == :error)), do: :failed, else: :passed
  end

  defp finding(severity, code, message, section \\ nil) do
    %Finding{severity: severity, code: code, message: message, section: section}
  end

  defp render_argv(argv), do: Enum.map_join(argv, " ", &quote_arg/1)

  defp quote_arg(arg) do
    if String.match?(arg, ~r|^[A-Za-z0-9_@%+=:,./-]+$|) do
      arg
    else
      inspect(arg)
    end
  end
end
