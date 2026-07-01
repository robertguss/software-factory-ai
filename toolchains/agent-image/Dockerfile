# Conveyor agent container image (U8 containment).
#
# Bundles the coding-agent CLI (`claude`) plus the tools a Python greenfield slice
# needs to build and self-check its work. Conveyor runs this image via
# `Conveyor.AgentRunner.ContainedExec`: --read-only rootfs, tmpfs /tmp, --cap-drop ALL,
# non-root (host uid:gid), network per policy. HOME is forced to /tmp; the host's
# `claude` subscription credential file is bind-mounted read-only at
# /tmp/.claude/.credentials.json.
#
# Build:  docker build -t conveyor-agent:latest toolchains/agent-image
FROM node:22-slim

# git: diff capture + the agent's own VCS use. python3/pip/venv + ripgrep: slice work
# and `claude`'s file search. ca-certificates: TLS to the model API over the bridge.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      git python3 python3-pip python3-venv ripgrep ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# pytest available system-wide so a slice can run tests without building a venv first.
RUN pip3 install --no-cache-dir --break-system-packages pytest

# The agent CLI itself. Pinned-ish to the major line; global install lands on PATH
# (/usr/local/bin/claude) for any uid.
RUN npm install -g @anthropic-ai/claude-code

# Entrypoint copies the read-only mounted credential into an agent-owned $HOME/.claude (bug sqwm).
COPY entrypoint.sh /usr/local/bin/conveyor-agent-entrypoint.sh
RUN chmod +x /usr/local/bin/conveyor-agent-entrypoint.sh
ENTRYPOINT ["/usr/local/bin/conveyor-agent-entrypoint.sh"]

# No USER directive: ContainedExec passes --user <host-uid>:<host-gid> at runtime so
# workspace writes are host-owned. HOME=/tmp is injected at runtime.
