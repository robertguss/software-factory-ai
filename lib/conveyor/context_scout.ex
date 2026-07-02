defmodule Conveyor.ContextScout do
  @moduledoc """
  Builds cited, read-only context packs for implementation slices.
  """

  require Logger

  alias Conveyor.ContextScout.Signatures
  alias Conveyor.Factory
  alias Conveyor.Factory.AgentBrief
  alias Conveyor.Factory.ContextPack
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.HumanDecision
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.Requirement
  alias Conveyor.Factory.Slice
  alias Conveyor.Security.Redactor

  @scout_version "context-scout@1"

  # aabq.1 excerpt budget. Code defaults; overridable in one config place
  # (config :conveyor, Conveyor.ContextScout, ...) or per-call opts. Kept deliberately small —
  # excerpts are an interface anchor, not a repo dump; the tool-using agent reads more itself.
  @default_excerpt_max_files 5
  @default_excerpt_max_bytes 1200
  @excluded_dirs MapSet.new([
                   ".conveyor",
                   ".git",
                   ".pytest_cache",
                   ".venv",
                   "__pycache__",
                   "_build",
                   "deps",
                   "node_modules"
                 ])

  @spec run!(Slice.t() | Ecto.UUID.t(), keyword()) :: ContextPack.t()
  def run!(slice_or_id, opts \\ [])

  def run!(%Slice{} = slice, opts) do
    context = context_for!(slice)
    files = discover_files(context.project.local_path)
    brief = context.agent_brief
    existing_tests = existing_tests(brief, files)
    relevant_files = relevant_files(context, files, existing_tests)
    file_excerpts = file_excerpts(relevant_files, context.project.local_path, opts)
    suggested_validation = suggested_validation(brief, context.project)
    risks = risks(context)

    Ash.create!(
      ContextPack,
      %{
        slice_id: slice.id,
        scout_version: Keyword.get(opts, :scout_version, @scout_version),
        confidence: confidence(relevant_files, existing_tests, suggested_validation),
        relevant_files: relevant_files,
        file_excerpts: file_excerpts,
        key_interfaces: key_interfaces(brief),
        existing_tests: existing_tests,
        risks: risks,
        suggested_validation: suggested_validation,
        code_quality_refs: Keyword.get(opts, :code_quality_refs, [])
      },
      domain: Factory
    )
  end

  def run!(slice_id, opts) when is_binary(slice_id) do
    Slice
    |> get_by_id!(slice_id)
    |> run!(opts)
  end

  defp context_for!(slice) do
    epic = get_by_id!(Epic, slice.epic_id)
    plan = get_by_id!(Plan, epic.plan_id)
    project = get_by_id!(Project, plan.project_id)

    %{
      slice: slice,
      epic: epic,
      plan: plan,
      project: project,
      agent_brief: latest_brief(slice.id),
      requirements: requirements(plan.id),
      human_decisions: human_decisions(plan.id)
    }
  end

  defp discover_files(project_root) do
    project_root
    |> Path.expand()
    |> walk_files()
    |> Enum.map(&Path.relative_to(&1, project_root))
    |> Enum.sort()
  end

  defp walk_files(path) do
    case File.ls(path) do
      {:ok, entries} ->
        entries
        |> Enum.reject(&excluded_path?/1)
        |> Enum.flat_map(&walk_entry(path, &1))

      {:error, _reason} ->
        []
    end
  end

  defp walk_entry(parent_path, entry) do
    child = Path.join(parent_path, entry)

    cond do
      File.dir?(child) -> walk_files(child)
      File.regular?(child) -> [child]
      true -> []
    end
  end

  defp excluded_path?(entry), do: MapSet.member?(@excluded_dirs, entry)

  defp relevant_files(context, files, existing_tests) do
    brief = context.agent_brief

    existing_tests
    |> test_candidates()
    |> Enum.concat(source_candidates(files, context.slice, brief))
    |> Enum.concat(config_candidates(files))
    |> Enum.uniq_by(& &1["path"])
    |> Enum.take(8)
  end

  # aabq.1/aabq.2: bounded, redacted, interface-bearing excerpts for the top-K source files —
  # per-language signatures (Signatures.extract), falling back to the file head, byte-capped. Order
  # follows relevant_files (already deterministic) so prompt digests stay replayable. Repo content
  # is UNTRUSTED, so it is redacted.
  defp file_excerpts(relevant_files, project_root, opts) do
    {max_files, max_bytes} = excerpt_config(opts)
    root = Path.expand(project_root)

    relevant_files
    |> Enum.filter(&source_file?(&1["path"]))
    |> Enum.take(max_files)
    |> Enum.flat_map(&build_excerpt(&1["path"], root, max_bytes))
  end

  defp build_excerpt(path, root, max_bytes) do
    case File.read(Path.join(root, path)) do
      {:ok, content} ->
        {raw, truncated?} = interface_or_head(content, path, max_bytes)
        redacted = Redactor.redact!(raw, source: path).content

        if truncated? do
          Logger.info("context_scout: excerpt truncated for #{path} (> #{max_bytes} bytes)")
        end

        [
          %{
            "path" => path,
            "excerpt" => redacted,
            "truncated" => truncated?,
            "bytes" => byte_size(redacted)
          }
        ]

      {:error, _reason} ->
        []
    end
  end

  # aabq.2: prefer the interface-bearing signatures for the file's language; fall back to the file
  # head when the language is unknown or has no extractable signatures. Both are byte-capped.
  defp interface_or_head(content, path, max_bytes) do
    case Signatures.extract(content, path) do
      nil -> truncate_utf8(content, max_bytes)
      signatures -> truncate_utf8(signatures, max_bytes)
    end
  end

  defp excerpt_config(opts) do
    env = Application.get_env(:conveyor, __MODULE__, [])

    max_files =
      Keyword.get(opts, :excerpt_max_files) || Keyword.get(env, :excerpt_max_files) ||
        @default_excerpt_max_files

    max_bytes =
      Keyword.get(opts, :excerpt_max_bytes) || Keyword.get(env, :excerpt_max_bytes) ||
        @default_excerpt_max_bytes

    {max_files, max_bytes}
  end

  # Deterministic head truncation on a UTF-8 boundary (never splits a multibyte codepoint).
  defp truncate_utf8(content, max_bytes) when byte_size(content) <= max_bytes,
    do: {content, false}

  defp truncate_utf8(content, max_bytes),
    do: {valid_prefix(binary_part(content, 0, max_bytes)), true}

  defp valid_prefix(binary) do
    if String.valid?(binary),
      do: binary,
      else: valid_prefix(binary_part(binary, 0, byte_size(binary) - 1))
  end

  defp source_candidates(files, slice, nil) do
    likely_file_candidates(files, slice.likely_files)
  end

  defp source_candidates(files, slice, %AgentBrief{} = brief) do
    interface_text = Enum.join(brief.key_interfaces, " ")

    files
    |> likely_file_candidates(slice.likely_files)
    |> Enum.concat(interface_candidates(files, interface_text))
    |> Enum.uniq_by(& &1["path"])
  end

  defp likely_file_candidates(files, likely_files) do
    likely_files
    |> Enum.flat_map(&expand_likely_file(&1, files))
    |> Enum.map(fn path ->
      source_reason(path, "Listed by the slice as a likely affected file")
    end)
  end

  defp expand_likely_file(path, files) do
    cond do
      path in files ->
        [path]

      String.ends_with?(path, "/**") ->
        prefix = String.trim_trailing(path, "/**")
        Enum.filter(files, &String.starts_with?(&1, prefix <> "/"))

      true ->
        []
    end
  end

  # Language-neutral entrypoint/router and model file stems (aabq.2, de-Python-bias). Matched on the
  # basename stem across any source extension, not hardcoded *.py names.
  @entrypoint_stems ~w(main app server router routes index)
  @model_stems ~w(model models schema schemas task tasks entity entities domain)

  defp interface_candidates(files, interface_text) do
    Enum.flat_map(files, fn path ->
      cond do
        source_file?(path) and route_or_model_file?(path, interface_text) ->
          [source_reason(path, "Defines key router/model behavior for #{interface_text}")]

        source_file?(path) and entrypoint_file?(path) ->
          [source_reason(path, "Likely application entrypoint and API router")]

        true ->
          []
      end
    end)
  end

  defp route_or_model_file?(path, interface_text) do
    endpoint_hint? = Regex.match?(~r/\b(GET|POST|PATCH|PUT|DELETE)\b/, interface_text)
    model_hint? = String.contains?(interface_text, ".")
    stem = file_stem(path)

    (endpoint_hint? and stem in @entrypoint_stems) or
      (model_hint? and stem in (@entrypoint_stems ++ @model_stems))
  end

  defp entrypoint_file?(path), do: file_stem(path) in @entrypoint_stems

  defp file_stem(path), do: path |> Path.basename() |> Path.rootname() |> String.downcase()

  defp source_reason(path, prefix) do
    reason =
      cond do
        entrypoint_file?(path) ->
          "#{prefix}; names the API router and task model/state surface"

        Regex.match?(~r/(model|schema|task)/, path) ->
          "#{prefix}; names the domain model/state surface"

        true ->
          prefix
      end

    %{"path" => path, "reason" => reason}
  end

  defp test_candidates(existing_tests) do
    Enum.map(existing_tests, fn path ->
      %{
        "path" => path,
        "reason" => "Existing tests and locked acceptance coverage for the slice"
      }
    end)
  end

  defp config_candidates(files) do
    files
    |> Enum.filter(&config_file?/1)
    |> Enum.take(2)
    |> Enum.map(fn path ->
      %{"path" => path, "reason" => "Project configuration for validation commands"}
    end)
  end

  defp existing_tests(nil, files), do: test_files(files)

  defp existing_tests(%AgentBrief{} = brief, files) do
    brief.required_tests
    |> Enum.flat_map(&test_refs/1)
    |> Enum.concat(test_files(files))
    |> Enum.map(&test_file_path/1)
    |> Enum.filter(&(&1 in files))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp test_refs(test) do
    [test["source_ref"], test["ref"]]
    |> Enum.reject(&is_nil/1)
  end

  defp test_file_path(ref) do
    ref
    |> String.split("::", parts: 2)
    |> List.first()
    |> strip_project_prefix()
  end

  defp strip_project_prefix(path) do
    case String.split(path, "/", parts: 2) do
      ["samples", rest] ->
        case String.split(rest, "/", parts: 2) do
          [_sample_name, relative_path] -> relative_path
          _other -> path
        end

      _other ->
        path
    end
  end

  defp test_files(files) do
    files
    |> Enum.filter(&test_file?/1)
    |> Enum.sort()
  end

  defp suggested_validation(%AgentBrief{} = brief, project) do
    brief.verification_commands
    |> command_lines()
    |> fallback_validation(project)
  end

  defp suggested_validation(nil, project), do: fallback_validation([], project)

  defp fallback_validation([], project), do: command_lines(project.command_specs)
  defp fallback_validation(commands, _project), do: commands

  defp command_lines(commands) do
    commands
    |> Enum.map(&command_line/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp command_line(%{"argv" => argv}) when is_list(argv), do: Enum.join(argv, " ")
  defp command_line(%{argv: argv}) when is_list(argv), do: Enum.join(argv, " ")
  defp command_line(_command), do: ""

  defp risks(context) do
    []
    |> maybe_add_brief_risk(context.agent_brief)
    |> maybe_add_requirements(context.requirements)
    |> maybe_add_decisions(context.human_decisions)
    |> Enum.uniq()
  end

  defp maybe_add_brief_risk(risks, nil), do: risks

  defp maybe_add_brief_risk(risks, %AgentBrief{} = brief) do
    [
      "#{brief.risk} risk: preserve current behavior while implementing #{brief.desired_behavior}"
      | risks
    ]
  end

  defp maybe_add_requirements(risks, requirements) do
    requirements
    |> Enum.map(&"#{&1.stable_key}: #{&1.text}")
    |> Enum.concat(risks)
  end

  defp maybe_add_decisions(risks, decisions) do
    decisions
    |> Enum.map(&"Decision #{&1.stable_key}: #{&1.decision}")
    |> Enum.concat(risks)
  end

  defp confidence(relevant_files, existing_tests, suggested_validation) do
    score =
      Decimal.new("0.40")
      |> maybe_increase(has_source?(relevant_files), "0.20")
      |> maybe_increase(has_model?(relevant_files), "0.12")
      |> maybe_increase(existing_tests != [], "0.18")
      |> maybe_increase(suggested_validation != [], "0.10")

    Decimal.min(score, Decimal.new("0.95"))
  end

  defp maybe_increase(score, true, increment), do: Decimal.add(score, Decimal.new(increment))
  defp maybe_increase(score, false, _increment), do: score

  defp has_source?(relevant_files) do
    Enum.any?(relevant_files, &(source_file?(&1["path"]) and not test_file?(&1["path"])))
  end

  defp has_model?(relevant_files) do
    Enum.any?(relevant_files, fn entry ->
      path = entry["path"]
      reason = entry["reason"]

      Regex.match?(~r/(model|schema|task)/, path) or
        String.contains?(String.downcase(reason), "model")
    end)
  end

  defp key_interfaces(%AgentBrief{} = brief), do: brief.key_interfaces
  defp key_interfaces(nil), do: []

  defp source_file?(path),
    do: Path.extname(path) in [".ex", ".exs", ".js", ".jsx", ".py", ".ts", ".tsx"]

  defp test_file?(path) do
    String.contains?(path, "/test") or
      String.contains?(path, "test_") or
      String.ends_with?(path, "_test.exs")
  end

  defp config_file?(path) do
    Path.basename(path) in [
      "mix.exs",
      "package.json",
      "pyproject.toml",
      "requirements.txt",
      "requirements.lock"
    ]
  end

  defp latest_brief(slice_id) do
    AgentBrief
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.slice_id == slice_id))
    |> Enum.sort_by(&{&1.version, DateTime.to_unix(&1.locked_at, :microsecond)}, :desc)
    |> List.first()
  end

  defp requirements(plan_id) do
    Requirement
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.plan_id == plan_id))
    |> Enum.sort_by(& &1.stable_key)
  end

  defp human_decisions(plan_id) do
    HumanDecision
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.plan_id == plan_id and &1.status == :active))
    |> Enum.sort_by(& &1.stable_key)
  end

  defp get_by_id!(resource, id) do
    resource
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == id)) ||
      raise ArgumentError, "#{inspect(resource)} #{id} was not found"
  end
end
