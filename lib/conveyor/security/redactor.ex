defmodule Conveyor.Security.Redactor do
  @moduledoc """
  Secret scanning and redaction for projected evidence artifacts.

  The redactor intentionally records digest provenance rather than matched
  secret values. Findings identify source, classifier, and match digests; raw
  bytes are never copied into findings.
  """

  use Conveyor.Conductor.Child

  alias Conveyor.Artifacts.BlobStore

  defmodule Result do
    @moduledoc false

    @type policy :: :redact | :block
    @type t :: %__MODULE__{
            content: binary(),
            raw_sha256: String.t(),
            redacted_sha256: String.t(),
            findings: [map()],
            sensitivity: :internal | :redacted | :quarantined,
            blocked?: boolean(),
            policy: policy()
          }

    @enforce_keys [
      :content,
      :raw_sha256,
      :redacted_sha256,
      :findings,
      :sensitivity,
      :blocked?,
      :policy
    ]
    defstruct [
      :content,
      :raw_sha256,
      :redacted_sha256,
      :findings,
      :sensitivity,
      :blocked?,
      :policy
    ]
  end

  @type source :: String.t()
  @type policy :: Result.policy()

  @patterns [
    {:openai_api_key, ~r/\bsk-[A-Za-z0-9][A-Za-z0-9_-]{8,}\b/},
    {:github_token, ~r/\bgh[pousr]_[A-Za-z0-9_]{16,}\b/},
    {:aws_access_key_id, ~r/\b(?:AKIA|ASIA)[0-9A-Z]{16}\b/},
    {:private_key, ~r/-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----/s},
    {:secret_assignment,
     ~r/\b[A-Z][A-Z0-9_]*(?:API_)?(?:KEY|TOKEN|SECRET|PASSWORD)\s*[:=]\s*[^\s'"]+/}
  ]

  @spec scan(binary(), keyword()) :: [map()]
  def scan(content, opts \\ []) when is_binary(content) do
    source = Keyword.get(opts, :source, "unknown")
    policy = policy!(Keyword.get(opts, :policy, :redact))

    content
    |> matches()
    |> Enum.with_index(1)
    |> Enum.map(fn {match, index} -> finding(match, index, source, policy) end)
  end

  @spec redact!(binary(), keyword()) :: Result.t()
  def redact!(content, opts \\ []) when is_binary(content) do
    source = Keyword.get(opts, :source, "unknown")
    policy = policy!(Keyword.get(opts, :policy, :redact))
    raw_sha256 = BlobStore.sha256(content)
    matches = matches(content)

    findings =
      Enum.with_index(matches, 1)
      |> Enum.map(fn {match, index} -> finding(match, index, source, policy) end)

    redacted_content = redact_matches(content, matches)
    redacted_sha256 = BlobStore.sha256(redacted_content)

    {output_content, sensitivity, blocked?} =
      cond do
        matches == [] ->
          {content, :internal, false}

        policy == :block ->
          {content, :quarantined, true}

        true ->
          {redacted_content, :redacted, false}
      end

    %Result{
      content: output_content,
      raw_sha256: raw_sha256,
      redacted_sha256: redacted_sha256,
      findings: findings,
      sensitivity: sensitivity,
      blocked?: blocked?,
      policy: policy
    }
  end

  defp matches(content) do
    @patterns
    |> Enum.flat_map(fn {kind, regex} ->
      regex
      |> Regex.scan(content, return: :index)
      |> Enum.map(fn [{offset, length} | _captures] ->
        value = binary_part(content, offset, length)

        %{
          kind: kind,
          offset: offset,
          length: length,
          match_sha256: BlobStore.sha256(value)
        }
      end)
    end)
    |> Enum.sort_by(&{&1.offset, -&1.length})
    |> reject_overlaps()
  end

  defp reject_overlaps(matches) do
    {_last_end, kept} =
      Enum.reduce(matches, {0, []}, fn match, {last_end, kept} ->
        match_end = match.offset + match.length

        if match.offset < last_end do
          {last_end, kept}
        else
          {match_end, [match | kept]}
        end
      end)

    Enum.reverse(kept)
  end

  defp redact_matches(content, []), do: content

  defp redact_matches(content, matches) do
    {chunks, last_offset} =
      Enum.reduce(matches, {[], 0}, fn match, {chunks, last_offset} ->
        before_match = binary_part(content, last_offset, match.offset - last_offset)
        token = redaction_token(match)
        next_offset = match.offset + match.length
        {[before_match, token | chunks], next_offset}
      end)

    tail = binary_part(content, last_offset, byte_size(content) - last_offset)

    [tail | chunks]
    |> Enum.reverse()
    |> IO.iodata_to_binary()
  end

  defp redaction_token(match) do
    "[REDACTED:#{match.kind}:#{binary_part(match.match_sha256, 0, 12)}]"
  end

  defp finding(match, index, source, policy) do
    %{
      "category" => "secret_exposure",
      "classifier" => Atom.to_string(match.kind),
      "source" => source,
      "ordinal" => index,
      "severity" => severity(policy),
      "policy" => Atom.to_string(policy),
      "match_sha256" => match.match_sha256,
      "redaction" => redaction_token(match)
    }
  end

  defp severity(:block), do: "blocking"
  defp severity(:redact), do: "warning"

  defp policy!(policy) when policy in [:redact, :block], do: policy

  defp policy!(policy) do
    raise ArgumentError, "redaction policy must be :redact or :block, got: #{inspect(policy)}"
  end
end
