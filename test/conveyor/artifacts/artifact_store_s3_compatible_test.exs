defmodule Conveyor.Artifacts.ArtifactStoreS3CompatibleTest do
  use ExUnit.Case, async: true

  alias Conveyor.Artifacts.ArtifactStore
  alias Conveyor.Artifacts.ArtifactStore.S3Compatible

  test "S3Compatible implements the artifact store backend contract" do
    assert :ok = ArtifactStore.assert_backend!(S3Compatible)
  end

  test "S3Compatible keeps digest identity separate from storage locator" do
    root = temp_dir!("s3-compatible")

    backend =
      S3Compatible.new(
        root: root,
        bucket: "artifact-bucket",
        prefix: "tenant-a",
        trust_domain_id: "td-a"
      )

    address = S3Compatible.put!(backend, "remote artifact bytes")

    assert address.storage_backend == "s3_compatible"
    assert address.content_digest =~ ~r/^sha256:[0-9a-f]{64}$/
    assert address.opaque_storage_key =~ "s3://artifact-bucket/tenant-a/td-a/"

    refute address.opaque_storage_key =~
             String.replace_prefix(address.content_digest, "sha256:", "")

    assert S3Compatible.get!(backend, address) == "remote artifact bytes"

    copied = S3Compatible.copy!(backend, address, trust_domain_id: "td-b")
    assert copied.content_digest == address.content_digest
    assert copied.opaque_storage_key =~ "/td-b/"
    assert copied.opaque_storage_key != address.opaque_storage_key
  end

  defp temp_dir!(label) do
    path = Path.join(System.tmp_dir!(), "conveyor-#{label}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    path
  end
end
