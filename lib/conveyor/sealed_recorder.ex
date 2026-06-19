defmodule Conveyor.SealedRecorder do
  @moduledoc """
  Redaction gate for reusable recordings before they are sealed.
  """

  alias Conveyor.Security.Redactor

  @spec seal(binary(), keyword()) :: {:ok, Redactor.Result.t()} | {:error, Redactor.Result.t()}
  def seal(content, opts \\ []) when is_binary(content) do
    result = Redactor.redact!(content, opts)

    if result.blocked? do
      {:error, result}
    else
      {:ok, result}
    end
  end
end
