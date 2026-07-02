# tt6v.2: per-language runner image pattern (the elixir counterpart to sample-python-runner).
# Pinned base + hex/rebar so `mix test` is reproducible across the agent and the gate (the D1
# one-image-for-agent-and-gate rule). Building, pushing, and pinning the digest — plus the
# fixture-repo e2e that exercises it — is tt6v.3.
FROM elixir:1.20.1-otp-27-slim

RUN mix local.hex --force && mix local.rebar --force

WORKDIR /workspace

# Dependency locks are baked at build time from the slice's mix.lock; env-prep ("elixir_mix")
# runs `mix deps.get --only test && mix deps.compile` inside this image.
CMD ["mix", "test"]
