defmodule Conveyor.Eval do
  @moduledoc """
  Home and shared conventions for the Conveyor eval program (Rungs 0–1).

  Every artifact under `Conveyor.Eval.*` follows the same rules so reports stay
  deterministic, content-addressed, and CI-friendly:

    * **Canonicalization & digests** — use `Conveyor.CanonicalJson.encode/1` and
      `Conveyor.CanonicalJson.digest/1` (→ `"sha256:" <> lowerhex`). Do not inline
      a private `canonical_json`/`sha256`; `Conveyor.EvalSuites` predates this
      convention and must not be copied.
    * **Schema validation** — `Conveyor.Eval.Schema.validate/2` (jsv). New schemas
      live under `docs/schemas/conveyor.eval_*@1.json` and reference
      `conveyor.digest_ref@1` via `*_digest` fields (legacy `*_sha256` are
      migration aliases only). See `docs/schemas/CANONICALIZATION.md` + ADR-04.
    * **Reports** — versioned, deterministic maps carrying a `"schema_version"`
      token plus structured blocker lists, so a prose summary can never hide a
      blocker.
    * **Data** — committed datasets live under `eval/` (`corpora/`, `cassettes/`,
      `scorecards/`); generated scorecard inputs under `eval/scorecards/inputs/`.

  See `ROADMAP.md` for current eval-program status and direction.
  """

  @doc "Canonical-JSON sha256 digest (`\"sha256:\" <> lowerhex`) of any term."
  @spec digest(term()) :: String.t()
  defdelegate digest(term), to: Conveyor.CanonicalJson

  @doc "Deterministic canonical-JSON encoding of any term."
  @spec canonical_encode(term()) :: binary()
  defdelegate canonical_encode(term), to: Conveyor.CanonicalJson, as: :encode
end
