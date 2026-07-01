#!/bin/sh
# Conveyor agent entrypoint (fix for bug sqwm).
#
# ContainedExec bind-mounts the host's subscription credential read-only at a NEUTRAL path
# (/tmp/.conveyor-creds/credentials.json) — not $HOME/.claude, because a bind-mount there makes
# docker create a root-owned $HOME/.claude that the non-root agent cannot write into. Here, as
# the agent uid, we copy that credential into an agent-owned $HOME/.claude so Claude Code's Bash
# tool can create $HOME/.claude/session-env and friends.
set -e
CREDS=/tmp/.conveyor-creds/credentials.json
if [ -f "$CREDS" ]; then
  mkdir -p "$HOME/.claude"
  cp "$CREDS" "$HOME/.claude/.credentials.json"
  chmod 600 "$HOME/.claude/.credentials.json" 2>/dev/null || true
fi
exec "$@"
