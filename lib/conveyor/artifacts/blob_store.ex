defmodule Conveyor.Artifacts.BlobStore do
  @moduledoc """
  Local content-addressed blob storage for artifact bytes.

  The canonical on-disk layout is `.conveyor/blobs/sha256/<prefix>/<digest>`.
  Blob refs are relative paths under the blob root, so they can be persisted in
  database rows without trusting projection paths as identity.
  """

  defmodule Blob do
    @moduledoc false

    @type t :: %__MODULE__{
            ref: String.t(),
            sha256: String.t(),
            size_bytes: non_neg_integer(),
            content: binary() | nil
          }

    @enforce_keys [:ref, :sha256, :size_bytes]
    defstruct [:ref, :sha256, :size_bytes, :content]
  end

  @sha256_regex ~r/^[0-9a-f]{64}$/

  @spec write!(binary(), keyword()) :: Blob.t()
  def write!(content, opts \\ []) when is_binary(content) do
    sha256 = sha256(content)
    ref = ref_for_sha256!(sha256)
    path = path_for!(ref, opts)

    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)

    %Blob{ref: ref, sha256: sha256, size_bytes: byte_size(content)}
  end

  @spec read!(String.t(), keyword()) :: binary()
  def read!(blob_ref, opts \\ []) when is_binary(blob_ref) do
    path = path_for!(blob_ref, opts)
    content = File.read!(path)
    expected_sha256 = digest_from_ref!(blob_ref)
    actual_sha256 = sha256(content)

    if actual_sha256 != expected_sha256 do
      raise ArgumentError,
            "blob #{blob_ref} digest mismatch: expected #{expected_sha256}, got #{actual_sha256}"
    end

    content
  end

  @spec verify!(String.t(), String.t(), non_neg_integer(), keyword()) :: Blob.t()
  def verify!(blob_ref, expected_sha256, expected_size, opts \\ [])
      when is_binary(blob_ref) and is_integer(expected_size) and expected_size >= 0 do
    content = read!(blob_ref, opts)
    actual_sha256 = sha256(content)
    expected_sha256 = normalize_sha256!(expected_sha256)
    actual_size = byte_size(content)

    if actual_sha256 != expected_sha256 do
      raise ArgumentError,
            "blob #{blob_ref} digest mismatch: expected #{expected_sha256}, got #{actual_sha256}"
    end

    if actual_size != expected_size do
      raise ArgumentError,
            "blob #{blob_ref} size mismatch: expected #{expected_size}, got #{actual_size}"
    end

    %Blob{ref: blob_ref, sha256: actual_sha256, size_bytes: actual_size, content: content}
  end

  @spec path_for!(String.t(), keyword()) :: String.t()
  def path_for!(blob_ref, opts \\ []) when is_binary(blob_ref) do
    blob_root = opts |> Keyword.get(:blob_root, ".conveyor/blobs") |> Path.expand()
    relative_path = relative_path_for!(blob_ref)

    blob_root
    |> Path.join(relative_path)
    |> Path.expand()
    |> ensure_under_root!(blob_root)
  end

  @spec ref_for_sha256!(String.t()) :: String.t()
  def ref_for_sha256!(sha256) when is_binary(sha256) do
    sha256 = normalize_sha256!(sha256)
    Path.join(["sha256", binary_part(sha256, 0, 2), sha256])
  end

  @spec sha256(binary()) :: String.t()
  def sha256(content) when is_binary(content) do
    Base.encode16(:crypto.hash(:sha256, content), case: :lower)
  end

  defp relative_path_for!(blob_ref) do
    case String.split(blob_ref, "/", trim: true) do
      ["sha256", shard, digest] when byte_size(shard) == 2 ->
        digest = normalize_sha256!(digest)

        if shard != binary_part(digest, 0, 2) do
          raise ArgumentError, "blob_ref shard does not match digest"
        end

        Path.join(["sha256", shard, digest])

      ["cas", digest] ->
        Path.join(["cas", normalize_sha256!(digest)])

      [digest] ->
        ref_for_sha256!(digest)

      _other ->
        raise ArgumentError, "blob_ref must be a content-addressed sha256 ref"
    end
  end

  defp digest_from_ref!(blob_ref) do
    case String.split(blob_ref, "/", trim: true) do
      ["sha256", shard, digest] when byte_size(shard) == 2 ->
        digest = normalize_sha256!(digest)

        if shard != binary_part(digest, 0, 2) do
          raise ArgumentError, "blob_ref shard does not match digest"
        end

        digest

      ["cas", digest] ->
        normalize_sha256!(digest)

      [digest] ->
        normalize_sha256!(digest)

      _other ->
        raise ArgumentError, "blob_ref must contain a sha256 digest"
    end
  end

  defp normalize_sha256!("sha256:" <> digest), do: normalize_sha256!(digest)

  defp normalize_sha256!(digest) when is_binary(digest) do
    digest = String.downcase(digest)

    if digest =~ @sha256_regex do
      digest
    else
      raise ArgumentError, "sha256 digest must be 64 lowercase hex characters"
    end
  end

  defp ensure_under_root!(path, root) do
    root = Path.expand(root)

    if path == root or String.starts_with?(path, root <> "/") do
      path
    else
      raise ArgumentError, "blob_ref escapes blob root"
    end
  end
end
