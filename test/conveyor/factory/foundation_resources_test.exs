defmodule Conveyor.Factory.FoundationResourcesTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.Factory
  alias Conveyor.Factory.CacheMount
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.ToolchainProfile

  @runner_profile Path.expand("../../../toolchains/sample-python-runner/profile.toml", __DIR__)
  @runner_lock Path.expand("../../../toolchains/sample-python-runner/requirements.lock", __DIR__)
  @sample_lock Path.expand("../../../samples/tasks_service/requirements.lock", __DIR__)

  describe "Project" do
    test "creates, reads, updates, and destroys a project through Ash" do
      project =
        Ash.create!(
          Project,
          %{
            name: "Sample",
            repo_url: "https://example.com/sample.git",
            local_path: "/tmp/sample",
            default_branch: "main",
            dev_branch: "factory/dev",
            command_specs: [command_spec("test", ["mix", "test"])],
            code_quality_profile: "strict",
            default_autonomy_level: 2
          },
          domain: Factory
        )

      assert project.status == :active
      assert [%{"key" => "test", "argv" => ["mix", "test"]}] = project.command_specs

      assert [read_project] = Ash.read!(Project, domain: Factory)
      assert read_project.id == project.id

      updated = Ash.update!(project, %{status: :archived}, domain: Factory)
      assert updated.status == :archived

      assert :ok = Ash.destroy!(updated, domain: Factory)
      assert [] = Ash.read!(Project, domain: Factory)
    end
  end

  describe "ToolchainProfile" do
    test "belongs to a project and stores pinned image/cache identity" do
      project =
        Ash.create!(
          Project,
          %{
            name: "Toolchain owner",
            local_path: "/tmp/toolchain-owner",
            default_branch: "main"
          },
          domain: Factory
        )

      profile =
        Ash.create!(
          ToolchainProfile,
          %{
            project_id: project.id,
            key: "sample-python-runner",
            image_ref: "ghcr.io/conveyor/sample-python-runner:2026-06-01",
            image_digest: "sha256:" <> String.duplicate("a", 64),
            dependency_lock_refs: ["requirements.lock"],
            dependency_lock_sha256: "sha256:" <> String.duplicate("b", 64),
            cache_policy: %{"mode" => "read_only", "roots" => ["/cache/pip"]},
            sbom_ref: "artifacts/sbom.cyclonedx.json"
          },
          domain: Factory
        )

      assert profile.project_id == project.id
      assert profile.cache_policy["mode"] == "read_only"

      updated = Ash.update!(profile, %{sbom_ref: "artifacts/sbom-v2.cdx.json"}, domain: Factory)
      assert updated.sbom_ref == "artifacts/sbom-v2.cdx.json"

      assert [read_profile] = Ash.read!(ToolchainProfile, domain: Factory)
      assert read_profile.id == profile.id
    end

    test "sample Python runner profile records pinned image, lock, and SBOM identity" do
      profile = runner_profile!()

      assert profile["key"] == "sample-python-runner"
      assert profile["image_ref"] == "ghcr.io/conveyor/sample-python-runner:2026-06-17"
      assert profile["image_digest"] =~ ~r/^sha256:[0-9a-f]{64}$/
      assert profile["sbom_ref"] == "toolchains/sample-python-runner/sbom.cyclonedx.json"
      assert File.regular?(Path.expand("../../../#{profile["sbom_ref"]}", __DIR__))
      assert File.read!(@runner_lock) == File.read!(@sample_lock)
      assert profile["dependency_lock_sha256"] == "sha256:#{sha256_file(@runner_lock)}"
      assert profile["cache_policy"]["mode"] == "read_only"

      project =
        Ash.create!(
          Project,
          %{
            name: "Sample runner owner",
            local_path: "/tmp/sample-runner-owner",
            default_branch: "main"
          },
          domain: Factory
        )

      toolchain =
        Ash.create!(
          ToolchainProfile,
          %{
            project_id: project.id,
            key: profile["key"],
            image_ref: profile["image_ref"],
            image_digest: profile["image_digest"],
            dependency_lock_refs: profile["dependency_lock_refs"],
            dependency_lock_sha256: profile["dependency_lock_sha256"],
            cache_policy: profile["cache_policy"],
            sbom_ref: profile["sbom_ref"]
          },
          domain: Factory
        )

      assert toolchain.image_digest == Conveyor.ToolMatrix.default_toolchain_image().digest
      assert toolchain.sbom_ref == Conveyor.ToolMatrix.default_toolchain_image().sbom_ref
    end
  end

  describe "CacheMount" do
    test "stores content-addressed cache mount metadata" do
      mount =
        Ash.create!(
          CacheMount,
          %{
            run_spec_id: Ash.UUID.generate(),
            station_run_id: Ash.UUID.generate(),
            cache_key: "pip:#{String.duplicate("c", 64)}",
            mount_path: "/cache/pip",
            mode: :read_only,
            content_digest: "sha256:" <> String.duplicate("d", 64),
            hit: true
          },
          domain: Factory
        )

      assert mount.mode == :read_only
      assert mount.hit

      updated = Ash.update!(mount, %{mode: :read_write, hit: false}, domain: Factory)
      assert updated.mode == :read_write
      refute updated.hit
    end

    test "rejects unknown cache mount modes" do
      assert_raise Ash.Error.Invalid, fn ->
        Ash.create!(
          CacheMount,
          %{
            run_spec_id: Ash.UUID.generate(),
            cache_key: "bad-mode",
            mount_path: "/cache",
            mode: :ambient_mutable
          },
          domain: Factory
        )
      end
    end
  end

  defp command_spec(key, argv) do
    %{
      "key" => key,
      "argv" => argv,
      "cwd" => ".",
      "profile" => "verify",
      "required" => true,
      "timeout_ms" => 120_000,
      "network" => "none",
      "env_allowlist" => [],
      "output_limit_bytes" => 2_000_000,
      "repeat" => 1,
      "flake_policy" => "fail_closed",
      "infra_retry_policy" => %{"max_retries" => 0, "retry_on" => []},
      "result_format" => "stdout"
    }
  end

  defp runner_profile! do
    @runner_profile
    |> File.read!()
    |> TomlElixir.decode!()
    |> Map.fetch!("toolchain_profile")
  end

  defp sha256_file(path) do
    path
    |> File.read!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
