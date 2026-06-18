defmodule Conveyor.RuntimeVersions do
  @moduledoc """
  Captures the runtime version snapshot written into RunSpec and Evidence.

  A snapshot is intentionally plain data so it can be embedded in JSON artifacts
  without depending on database resource modules.
  """

  @type t :: %{
          required(:elixir_version) => String.t(),
          required(:otp_version) => String.t(),
          required(:phoenix_version) => String.t(),
          required(:ash_version) => String.t(),
          required(:oban_version) => String.t(),
          required(:docker_engine_version) => String.t(),
          required(:sandbox_runner_version) => String.t(),
          required(:agent_adapter_version) => String.t(),
          required(:toolchain_image_digest) => String.t()
        }

  @required_fields [
    :elixir_version,
    :otp_version,
    :phoenix_version,
    :ash_version,
    :oban_version,
    :docker_engine_version,
    :sandbox_runner_version,
    :agent_adapter_version,
    :toolchain_image_digest
  ]

  @spec required_fields() :: [atom()]
  def required_fields, do: @required_fields

  @spec capture!(keyword()) :: t()
  def capture!(opts) do
    toolchain_image_digest = Keyword.fetch!(opts, :toolchain_image_digest)

    %{
      elixir_version: System.version(),
      otp_version: otp_version(),
      phoenix_version: app_version(:phoenix),
      ash_version: app_version(:ash),
      oban_version: app_version(:oban),
      docker_engine_version: docker_engine_version(opts),
      sandbox_runner_version:
        Keyword.get(opts, :sandbox_runner_version, Conveyor.ToolMatrix.sandbox_runner_version()),
      agent_adapter_version:
        Keyword.get(opts, :agent_adapter_version, Conveyor.ToolMatrix.agent_adapter_version(:pi)),
      toolchain_image_digest: toolchain_image_digest
    }
  end

  @spec app_version(atom()) :: String.t()
  def app_version(app) do
    case Application.spec(app, :vsn) do
      nil -> "unavailable"
      version -> to_string(version)
    end
  end

  defp otp_version do
    :erlang.system_info(:otp_release)
    |> to_string()
  end

  defp docker_engine_version(opts) do
    case Keyword.fetch(opts, :docker_engine_version) do
      {:ok, version} -> version
      :error -> detected_docker_engine_version()
    end
  end

  defp detected_docker_engine_version do
    with docker when not is_nil(docker) <- System.find_executable("docker"),
         {version, 0} <-
           System.cmd(docker, ["version", "--format", "{{.Server.Version}}"],
             stderr_to_stdout: true
           ),
         version <- String.trim(version),
         false <- version == "" do
      version
    else
      _ -> "unavailable"
    end
  end
end
