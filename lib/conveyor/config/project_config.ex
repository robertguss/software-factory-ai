defmodule Conveyor.Config.ProjectConfig do
  @moduledoc "Validated project-level Conveyor configuration."

  alias Conveyor.Config.CommandSpec

  @type autonomy_level :: :L0 | :L1 | :L2 | :L3 | :L4

  @type t :: %__MODULE__{
          name: String.t(),
          repo_path: String.t(),
          default_branch: String.t(),
          dev_branch: String.t() | nil,
          default_autonomy_level: autonomy_level(),
          policies_dir: String.t(),
          prompts_dir: String.t(),
          runs_dir: String.t(),
          blobs_dir: String.t(),
          quality_adapter: String.t(),
          command_specs: [CommandSpec.t()]
        }

  @enforce_keys [
    :name,
    :repo_path,
    :default_branch,
    :default_autonomy_level,
    :policies_dir,
    :prompts_dir,
    :runs_dir,
    :blobs_dir,
    :quality_adapter,
    :command_specs
  ]
  defstruct name: nil,
            repo_path: nil,
            default_branch: nil,
            dev_branch: nil,
            default_autonomy_level: nil,
            policies_dir: nil,
            prompts_dir: nil,
            runs_dir: nil,
            blobs_dir: nil,
            quality_adapter: nil,
            command_specs: []
end
