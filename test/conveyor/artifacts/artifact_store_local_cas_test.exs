defmodule Conveyor.Artifacts.ArtifactStoreLocalCASTest do
  use ExUnit.Case, async: true

  alias Conveyor.Artifacts.ArtifactStore
  alias Conveyor.Artifacts.ArtifactStore.LocalCAS

  test "LocalCAS implements the artifact store backend contract" do
    assert :ok = ArtifactStore.assert_backend!(LocalCAS)
  end

  test "LocalCAS stores content by digest behind trust-domain isolated addresses" do
    root = temp_dir!("local-cas")
    backend = LocalCAS.new(root: root, trust_domain_id: "td-a")

    address = LocalCAS.put!(backend, "artifact bytes")

    assert address.trust_domain_id == "td-a"
    assert address.content_digest =~ ~r/^sha256:[0-9a-f]{64}$/
    assert address.opaque_storage_key =~ "td-a/"
    assert address.storage_backend == "local_cas"

    assert LocalCAS.get!(backend, address) == "artifact bytes"

    head = LocalCAS.head!(backend, address)
    assert head.size_bytes == 14
    assert head.content_digest == address.content_digest

    assert LocalCAS.list_segments!(backend) == [address]

    copied = LocalCAS.copy!(backend, address, trust_domain_id: "td-b")

    assert copied.trust_domain_id == "td-b"
    assert copied.content_digest == address.content_digest
    assert copied.opaque_storage_key != address.opaque_storage_key

    assert :ok = LocalCAS.secure_delete!(backend, address)

    assert_raise File.Error, fn ->
      LocalCAS.get!(backend, address)
    end

    # The td-b copy is readable only through a backend scoped to td-b: trust-domain isolation
    # means a td-a backend must not resolve a td-b address (ADR-09 authorize-before-reveal).
    td_b_backend = %{backend | trust_domain_id: "td-b"}
    assert LocalCAS.get!(td_b_backend, copied) == "artifact bytes"

    assert_raise ArgumentError, fn -> LocalCAS.get!(backend, copied) end
  end

  defp temp_dir!(label) do
    path = Path.join(System.tmp_dir!(), "conveyor-#{label}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    path
  end
end
