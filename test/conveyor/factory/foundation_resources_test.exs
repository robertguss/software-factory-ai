defmodule Conveyor.Factory.FoundationResourcesTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.Factory
  alias Conveyor.Factory.CacheMount
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.ToolchainProfile

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
            command_specs: [
              %{"name" => "test", "argv" => ["mix", "test"]}
            ],
            code_quality_profile: "strict",
            default_autonomy_level: 2
          },
          domain: Factory
        )

      assert project.status == :active
      assert project.command_specs == [%{"name" => "test", "argv" => ["mix", "test"]}]

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
end
