defmodule Conveyor.Config.CommandSpec do
  @moduledoc "Validated command specification loaded from `.conveyor/config.toml`."

  @type profile :: :explore | :implement | :verify | :release | :maintenance
  @type network :: :none | :loopback | :egress
  @type result_format :: :junit | :tap | :json | :stdout | :custom

  @type t :: %__MODULE__{
          key: String.t(),
          argv: [String.t()],
          cwd: String.t(),
          profile: profile(),
          required: boolean(),
          timeout_ms: pos_integer(),
          network: network(),
          env_allowlist: [String.t()],
          output_limit_bytes: pos_integer(),
          result_format: result_format(),
          result_adapter: String.t() | nil
        }

  @enforce_keys [:key, :argv, :profile]
  defstruct key: nil,
            argv: [],
            cwd: ".",
            profile: nil,
            required: true,
            timeout_ms: 120_000,
            network: :none,
            env_allowlist: [],
            output_limit_bytes: 2_000_000,
            result_format: :stdout,
            result_adapter: nil
end
