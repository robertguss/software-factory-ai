defmodule Conveyor.Planning.ScopeCapTest do
  @moduledoc "nyrl.3: per-slice max_files_changed derived from declared scope."
  use ExUnit.Case, async: true

  alias Conveyor.Planning.ScopeCap

  test "cap = declared scope + always-allowed headroom + margin (default 3 + 1)" do
    assert ScopeCap.max_files_changed(0) == 4
    assert ScopeCap.max_files_changed(2) == 6
    assert ScopeCap.max_files_changed(10) == 14
  end

  test "the dxgw-shape slice (2 declared) passes at its honest size (impl+errors+barrel)" do
    # dogfood run 4: 4 files were the honest size; a flat cap of 3 wrongly parked it.
    assert ScopeCap.max_files_changed(2) >= 4
  end

  test "declared scope beyond the profile bound is an authoring smell" do
    refute ScopeCap.over_declared_bound?(ScopeCap.max_declared_files())
    assert ScopeCap.over_declared_bound?(ScopeCap.max_declared_files() + 1)
  end
end
