#!/usr/bin/env bash
set -euo pipefail

# Launches the Massdriver MCP server via Docker (stdio transport).
# stdout is reserved for the MCP protocol — all diagnostics MUST go to stderr.

# Tracks :latest by default — the server is refreshed on every boot (see the
# best-effort pull below) so new capabilities ship without a plugin update.
# Set MASSDRIVER_MCP_SERVER_TAG to pin a version for reproducibility, or
# MASSDRIVER_MCP_IMAGE (full ref) to point at another registry.
MCP_SERVER_TAG="${MASSDRIVER_MCP_SERVER_TAG:-latest}"
IMAGE="${MASSDRIVER_MCP_IMAGE:-docker.io/massdrivercloud/mcp-server:${MCP_SERVER_TAG}}"

if ! command -v docker >/dev/null 2>&1; then
  echo "massdriver-mcp: docker not found on PATH. Install Docker: https://docs.docker.com/get-started/get-docker/" >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "massdriver-mcp: the Docker daemon is not running. Start Docker Desktop (macOS/Windows) or the docker service (Linux) and retry." >&2
  exit 1
fi

# Best-effort pull on every boot so the server tracks the latest release.
# If the registry is unreachable, fall back to the local image rather than
# refusing to start; fail hard only when no image is available at all.
if ! docker pull "$IMAGE" >&2; then
  if docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "massdriver-mcp: pull failed; starting with the local ${IMAGE}. It may be stale." >&2
  else
    echo "massdriver-mcp: cannot pull ${IMAGE} and no local copy exists. Check network/registry access and retry." >&2
    exit 1
  fi
fi

ARGS=(
  run -i --rm
  --user "$(id -u):$(id -g)"
  -e MASSDRIVER_API_KEY
  -e MASSDRIVER_ORGANIZATION_ID
  -e MASSDRIVER_URL
  -e MASSDRIVER_PROFILE
  -e XDG_CONFIG_HOME=/config
)

# Least privilege: the CLI config holds API keys for EVERY configured profile.
# Only mount it when profile-based auth is actually needed (no explicit API
# key in the environment). Conditional on existence: mounting a nonexistent
# path would make Docker create a root-owned directory on the host.
if [ -z "${MASSDRIVER_API_KEY:-}" ] && [ -d "${HOME:-}/.config/massdriver" ]; then
  ARGS+=(-v "${HOME}/.config/massdriver:/config/massdriver:ro")
fi

exec docker "${ARGS[@]}" "$IMAGE" "$@"
