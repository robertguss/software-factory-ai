defmodule Conveyor.Config.ValidationError do
  @moduledoc "Structured validation error returned by the project config loader."

  defexception [:message, :path, :reason]

  @type t :: %__MODULE__{
          message: String.t(),
          path: [String.t()],
          reason: atom()
        }

  @spec missing([String.t()]) :: t()
  def missing(path) do
    %__MODULE__{
      message: "missing required config key #{Enum.join(path, ".")}",
      path: path,
      reason: :missing_required_key
    }
  end

  @spec invalid([String.t()], String.t()) :: t()
  def invalid(path, expected) do
    %__MODULE__{
      message: "invalid config key #{Enum.join(path, ".")}: expected #{expected}",
      path: path,
      reason: :invalid_value
    }
  end

  @spec parse_error(String.t()) :: t()
  def parse_error(message) do
    %__MODULE__{
      message: "invalid TOML config: #{message}",
      path: [],
      reason: :parse_error
    }
  end

  @spec file_error(String.t(), term()) :: t()
  def file_error(path, reason) do
    %__MODULE__{
      message: "could not read config file #{path}: #{inspect(reason)}",
      path: [path],
      reason: :file_error
    }
  end
end
