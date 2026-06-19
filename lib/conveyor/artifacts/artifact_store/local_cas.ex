defmodule Conveyor.Artifacts.ArtifactStore.LocalCAS do
  @moduledoc """
  Local content-addressed ArtifactStore backend.
  """

  @behaviour Conveyor.Artifacts.ArtifactStore

  alias Conveyor.Artifacts.ArtifactStore.Address
  alias Conveyor.Artifacts.BlobStore

  defstruct [:root, :trust_domain_id]

  @type t :: %__MODULE__{root: Path.t(), trust_domain_id: String.t()}

  @impl true
  def new(opts) do
    root = opts |> Keyword.fetch!(:root) |> Path.expand()
    trust_domain_id = Keyword.fetch!(opts, :trust_domain_id)
    File.mkdir_p!(root)
    %__MODULE__{root: root, trust_domain_id: trust_domain_id}
  end

  @impl true
  def put!(%__MODULE__{} = backend, content) when is_binary(content) do
    digest = "sha256:" <> BlobStore.sha256(content)
    address = address_for(backend, digest)
    path = path_for!(backend, address)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
    address
  end

  @impl true
  def get!(%__MODULE__{} = backend, %Address{} = address) do
    content = File.read!(path_for!(backend, address))
    actual_digest = "sha256:" <> BlobStore.sha256(content)

    if actual_digest != address.content_digest do
      raise ArgumentError,
            "artifact digest mismatch: expected #{address.content_digest}, got #{actual_digest}"
    end

    content
  end

  @impl true
  def head!(%__MODULE__{} = backend, %Address{} = address) do
    content = get!(backend, address)

    %{
      content_digest: address.content_digest,
      size_bytes: byte_size(content),
      storage_backend: address.storage_backend,
      trust_domain_id: address.trust_domain_id
    }
  end

  @impl true
  def copy!(%__MODULE__{} = backend, %Address{} = address, opts) do
    trust_domain_id = Keyword.fetch!(opts, :trust_domain_id)
    content = get!(backend, address)
    put!(%{backend | trust_domain_id: trust_domain_id}, content)
  end

  @impl true
  def secure_delete!(%__MODULE__{} = backend, %Address{} = address) do
    File.rm!(path_for!(backend, address))
    :ok
  end

  @impl true
  def list_segments!(%__MODULE__{} = backend) do
    pattern = Path.join([backend.root, backend.trust_domain_id, "sha256", "*", "*"])

    pattern
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.map(fn path ->
      digest = Path.basename(path)
      address_for(backend, "sha256:" <> digest)
    end)
  end

  defp address_for(%__MODULE__{} = backend, "sha256:" <> digest = content_digest) do
    %Address{
      trust_domain_id: backend.trust_domain_id,
      content_digest: content_digest,
      opaque_storage_key:
        Path.join([backend.trust_domain_id, "sha256", binary_part(digest, 0, 2), digest]),
      storage_backend: "local_cas"
    }
  end

  defp path_for!(%__MODULE__{} = backend, %Address{} = address) do
    path =
      backend.root
      |> Path.join(address.opaque_storage_key)
      |> Path.expand()

    ensure_under_root!(path, backend.root)
  end

  defp ensure_under_root!(path, root) do
    root = Path.expand(root)

    if path == root or String.starts_with?(path, root <> "/") do
      path
    else
      raise ArgumentError, "artifact address escapes store root"
    end
  end
end
