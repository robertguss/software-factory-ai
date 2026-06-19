defmodule Conveyor.PlanningPassRegistryTest do
  use ExUnit.Case, async: true

  alias Conveyor.Planning.PassRegistry

  test "runs registered pure passes with restricted context and content-addressed cache hits" do
    registry =
      PassRegistry.new()
      |> PassRegistry.register(%{
        pass_key: "decompose",
        version: "1",
        input_stage: "planning_spec",
        output_stage: "decomposition_candidate",
        selectors: ["requirements"],
        cache_policy: :content_addressed,
        authority_effect: :none,
        run: fn context ->
          requirements = PassRegistry.read!(context, "requirements")
          %{candidate_count: length(requirements)}
        end
      })

    inputs = %{
      "requirements" => [%{"key" => "REQ-001"}],
      "semantic_digest" => digest("semantic"),
      "authority_digest" => digest("authority")
    }

    first = PassRegistry.run(registry, "decompose", inputs)
    second = PassRegistry.run(first.registry, "decompose", inputs)

    assert first.status == :ok
    assert first.hermeticity_status == :hermetic
    assert first.output == %{candidate_count: 1}
    assert first.cache_key == second.cache_key
    assert second.cache_status == :hit
    assert second.output == first.output
  end

  test "undeclared reads fail and pass version changes miss the cache" do
    registry =
      PassRegistry.new()
      |> PassRegistry.register(%{
        pass_key: "unsafe",
        version: "1",
        selectors: ["requirements"],
        cache_policy: :content_addressed,
        authority_effect: :none,
        run: fn context -> PassRegistry.read!(context, "decisions") end
      })

    inputs = %{
      "requirements" => [],
      "decisions" => [],
      "semantic_digest" => digest("semantic"),
      "authority_digest" => digest("authority")
    }

    assert_raise ArgumentError, ~r/undeclared pass read: decisions/, fn ->
      PassRegistry.run(registry, "unsafe", inputs)
    end

    version_one =
      PassRegistry.new()
      |> PassRegistry.register(passthrough_pass("versioned", "1"))
      |> PassRegistry.run("versioned", inputs)

    version_two =
      version_one.registry
      |> PassRegistry.register(passthrough_pass("versioned", "2"))
      |> PassRegistry.run("versioned", inputs)

    assert version_one.cache_key != version_two.cache_key
    assert version_two.cache_status == :miss
  end

  defp passthrough_pass(pass_key, version) do
    %{
      pass_key: pass_key,
      version: version,
      selectors: ["requirements"],
      cache_policy: :content_addressed,
      authority_effect: :none,
      run: fn context -> %{requirements: PassRegistry.read!(context, "requirements")} end
    }
  end

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
