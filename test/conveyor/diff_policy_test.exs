defmodule Conveyor.Factory.DiffPolicyTest do
  @moduledoc "nyrl.1: always_allowed_path_classes persists and round-trips on the DiffPolicy."
  use Conveyor.DataCase, async: false

  alias Conveyor.Factory
  alias Conveyor.Factory.DiffPolicy

  test "always_allowed_path_classes round-trips through the database" do
    classes = [%{"name" => "docs", "globs" => ["docs/**"]}]

    created =
      Ash.create!(
        DiffPolicy,
        %{allowed_path_globs: ["lib/**"], always_allowed_path_classes: classes},
        domain: Factory
      )

    assert Ash.get!(DiffPolicy, created.id, domain: Factory).always_allowed_path_classes ==
             classes
  end

  test "always_allowed_path_classes defaults to an empty list" do
    created = Ash.create!(DiffPolicy, %{allowed_path_globs: ["lib/**"]}, domain: Factory)
    assert created.always_allowed_path_classes == []
  end
end
