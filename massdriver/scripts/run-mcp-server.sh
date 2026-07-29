#!/usr/bin/env bash
set -euo pipefail

# Launches the Massdriver MCP server via Docker (stdio transport).
# stdout is reserved for the MCP protocol — all diagnostics MUST go to stderr.

if ! command -v docker >/dev/null 2>&1; then
  echo "massdriver-mcp: docker not found on PATH. Install Docker: https://docs.docker.com/get-started/get-docker/" >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "massdriver-mcp: the Docker daemon is not running. Start Docker Desktop (macOS/Windows) or the docker service (Linux) and retry." >&2
  exit 1
fi

ARGS=(
  run -i --rm --pull always
  --user "$(id -u):$(id -g)"
  -e MASSDRIVER_API_KEY
  -e MASSDRIVER_ORGANIZATION_ID
  -e MASSDRIVER_URL
  -e MASSDRIVER_PROFILE
  -e XDG_CONFIG_HOME=/config
)

# Mount the Massdriver CLI config read-only so profile auth works in the
# container. Conditional: mounting a nonexistent path would make Docker create
# a root-owned directory on the host.
if [ -d "${HOME:-}/.config/massdriver" ]; then
  ARGS+=(-v "${HOME}/.config/massdriver:/config/massdriver:ro")
fi

exec docker "${ARGS[@]}" docker.io/massdrivercloud/mcp-server "$@"
