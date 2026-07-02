defmodule Conveyor.Verification.EngineDispatch do
  @moduledoc """
  tt6v.2: pick the verify-station engine from the toolchain profile's `language`.

  `python` (and the absent/default case) use the pytest-specialized `Eval.ToolchainRunner`; every
  other language uses the generic `CommandSuiteRunner` seam over the slice's locked command_specs.
  Keeping this decision at the profile keeps language selection out of per-slice config, where it
  would drift.
  """

  @python ["python", :python]

  @spec engine_for(String.t() | atom() | nil) :: :pytest | :command
  def engine_for(nil), do: :pytest
  def engine_for(language) when language in @python, do: :pytest
  def engine_for(_language), do: :command
end
