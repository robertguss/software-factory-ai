defmodule Conveyor.Artifacts.BlobStoreTest do
  use ExUnit.Case, async: true

  alias Conveyor.Artifacts.BlobStore

  test "writes and reads blobs by sharded sha256 ref" do
    blob_root = temp_dir!("roundtrip")
    content = "artifact bytes\n"
    sha256 = BlobStore.sha256(content)

    blob = BlobStore.write!(content, blob_root: blob_root)

    assert blob.ref == Path.join(["sha256", binary_part(sha256, 0, 2), sha256])
    assert blob.sha256 == sha256
    assert blob.size_bytes == byte_size(content)
    assert File.exists?(BlobStore.path_for!(blob.ref, blob_root: blob_root))
    assert BlobStore.read!(blob.ref, blob_root: blob_root) == content
  end

  test "tampered blobs fail digest verification on read" do
    blob_root = temp_dir!("tamper")
    blob = BlobStore.write!("expected", blob_root: blob_root)

    blob.ref
    |> BlobStore.path_for!(blob_root: blob_root)
    |> File.write!("corrupted")

    assert_raise ArgumentError, ~r/digest mismatch/, fn ->
      BlobStore.read!(blob.ref, blob_root: blob_root)
    end
  end

  test "verify checks caller-expected digest and size" do
    blob_root = temp_dir!("verify")
    blob = BlobStore.write!("verified", blob_root: blob_root)

    assert %{content: "verified"} =
             BlobStore.verify!(blob.ref, "sha256:#{blob.sha256}", blob.size_bytes,
               blob_root: blob_root
             )

    assert_raise ArgumentError, ~r/size mismatch/, fn ->
      BlobStore.verify!(blob.ref, blob.sha256, blob.size_bytes + 1, blob_root: blob_root)
    end
  end

  test "can read legacy cas refs while new writes use sha256 refs" do
    blob_root = temp_dir!("legacy")
    content = "legacy"
    sha256 = BlobStore.sha256(content)
    legacy_ref = "cas/#{sha256}"
    legacy_path = Path.join([blob_root, "cas", sha256])

    File.mkdir_p!(Path.dirname(legacy_path))
    File.write!(legacy_path, content)

    assert BlobStore.read!(legacy_ref, blob_root: blob_root) == content
  end

  defp temp_dir!(label) do
    path =
      Path.join(
        System.tmp_dir!(),
        "conveyor-blob-store-#{label}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(path)
    path
  end
end
