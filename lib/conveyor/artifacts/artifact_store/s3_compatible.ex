defmodule Conveyor.Artifacts.ArtifactStore.S3Compatible do
  @moduledoc """
  Optional S3-compatible ArtifactStore backend.

  The implementation keeps the public backend contract local-testable by writing
  to a root directory laid out as bucket/prefix/object-key. The persisted
  `opaque_storage_key` has S3 locator shape, while content identity remains the
  digest.
  """

  @behaviour Conveyor.Artifacts.ArtifactStore

  alias Conveyor.Artifacts.ArtifactStore.Address
  alias Conveyor.Artifacts.BlobStore

  defstruct [:root, :bucket, :prefix, :trust_domain_id]

  @type t :: %__MODULE__{
          root: Path.t(),
          bucket: String.t(),
          prefix: String.t(),
          trust_domain_id: String.t()
        }

  @impl true
  def new(opts) do
    root = opts |> Keyword.fetch!(:root) |> Path.expand()
    bucket = Keyword.fetch!(opts, :bucket)
    prefix = opts |> Keyword.get(:prefix, "") |> String.trim("/")
    trust_domain_id = Keyword.fetch!(opts, :trust_domain_id)
    File.mkdir_p!(root)
    %__MODULE__{root: root, bucket: bucket, prefix: prefix, trust_domain_id: trust_domain_id}
  end

  @impl true
  def put!(%__MODULE__{} = backend, content) when is_binary(content) do
    digest = "sha256:" <> BlobStore.sha256(content)
    address = address_for(backend, digest, object_key(backend))
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
    pattern =
      Path.join([backend.root, backend.bucket, backend.prefix, backend.trust_domain_id, "*"])

    pattern
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.map(fn path ->
      content = File.read!(path)
      digest = "sha256:" <> BlobStore.sha256(content)
      address_for(backend, digest, object_key_from_path(backend, path))
    end)
  end

  defp address_for(%__MODULE__{} = backend, content_digest, object_key) do
    %Address{
      trust_domain_id: backend.trust_domain_id,
      content_digest: content_digest,
      opaque_storage_key: "s3://#{backend.bucket}/#{object_key}",
      storage_backend: "s3_compatible"
    }
  end

  defp object_key(%__MODULE__{} = backend) do
    Path.join([
      backend.prefix,
      backend.trust_domain_id,
      "objects",
      System.unique_integer([:positive]) |> Integer.to_string(36)
    ])
  end

  defp object_key_from_path(%__MODULE__{} = backend, path) do
    path
    |> Path.relative_to(Path.join([backend.root, backend.bucket]))
    |> Path.split()
    |> Enum.join("/")
  end

  defp path_for!(%__MODULE__{} = backend, %Address{} = address) do
    "s3://" <> rest = address.opaque_storage_key
    [bucket | key_parts] = String.split(rest, "/", trim: true)

    if bucket != backend.bucket do
      raise ArgumentError, "artifact address bucket #{bucket} does not match backend bucket"
    end

    path =
      backend.root
      |> Path.join([bucket | key_parts])
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
