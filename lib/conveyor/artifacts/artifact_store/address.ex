defmodule Conveyor.Artifacts.ArtifactStore.Address do
  @moduledoc """
  Trust-domain scoped artifact address.
  """

  @type t :: %__MODULE__{
          trust_domain_id: String.t(),
          content_digest: String.t(),
          ciphertext_digest: String.t() | nil,
          opaque_storage_key: String.t(),
          encryption_key_ref: String.t() | nil,
          storage_backend: String.t()
        }

  @enforce_keys [:trust_domain_id, :content_digest, :opaque_storage_key, :storage_backend]
  defstruct [
    :trust_domain_id,
    :content_digest,
    :ciphertext_digest,
    :opaque_storage_key,
    :encryption_key_ref,
    :storage_backend
  ]
end
