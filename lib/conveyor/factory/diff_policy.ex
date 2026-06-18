defmodule Conveyor.Factory.DiffPolicy do
  @moduledoc """
  Bounds the allowed diff scope for a slice.
  """

  use Ash.Resource,
    otp_app: :conveyor,
    domain: Conveyor.Factory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "diff_policies"
    repo(Conveyor.Repo)
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  attributes do
    uuid_primary_key :id

    attribute :allowed_path_globs, {:array, :string} do
      allow_nil? false
      default []
      public? true
    end

    attribute :protected_path_globs, {:array, :string} do
      allow_nil? false
      default []
      public? true
    end

    attribute :max_files_changed, :integer do
      public? true
    end

    attribute :max_lines_added, :integer do
      public? true
    end

    attribute :max_lines_deleted, :integer do
      public? true
    end

    attribute :dependency_changes_allowed, :boolean do
      allow_nil? false
      default false
      public? true
    end

    attribute :migrations_allowed, :boolean do
      allow_nil? false
      default false
      public? true
    end

    attribute :generated_files_allowed, :boolean do
      allow_nil? false
      default false
      public? true
    end

    attribute :public_api_changes_allowed, :boolean do
      allow_nil? false
      default false
      public? true
    end

    attribute :notes, :string do
      public? true
    end
  end

  relationships do
    belongs_to :slice, Conveyor.Factory.Slice do
      allow_nil? true
      public? true
    end
  end
end
