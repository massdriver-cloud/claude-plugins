#!/usr/bin/env bash
# Test suite for massdriver-safety-check.sh.
#
# Each case feeds a PreToolUse payload to the guard and asserts the decision:
#   deny  -> stdout contains "permissionDecision":"deny"
#   allow -> stdout contains "permissionDecision":"allow"
#   pass  -> stdout is empty (no opinion; normal permission flow decides)
#
# Run: ./test-safety-check.sh

set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/massdriver-safety-check.sh"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

PASS=0
FAIL=0

mcp() { # tool, input-json
  printf '{"session_id":"t","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"mcp__plugin_massdriver_massdriver__%s","tool_input":%s}' "$WORKDIR" "$1" "$2"
}

bashcmd() { # command string (single-quote-free for simplicity)
  printf '{"session_id":"t","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"%s","description":"test"}}' "$WORKDIR" "$1"
}

check() { # name, expected(deny|allow|pass), payload
  local name="$1" expected="$2" payload="$3" out decision
  out="$(printf '%s' "$payload" | bash "$SCRIPT")"
  case "$out" in
    *'"permissionDecision":"deny"'*) decision=deny ;;
    *'"permissionDecision":"allow"'*) decision=allow ;;
    "") decision=pass ;;
    *) decision="malformed($out)" ;;
  esac
  if [ "$decision" = "$expected" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $name — expected $expected, got $decision"
  fi
}

### MCP: reads auto-allow ###
check "get_instance on prod is read-only"        allow "$(mcp get_instance '{"id":"ecomm-prod-db"}')"
check "list_projects"                            allow "$(mcp list_projects '{}')"
check "compare_environments vs prod"             allow "$(mcp compare_environments '{"source_id":"ecomm-prod","target_id":"ecomm-testa"}')"
check "get_deployment_logs follow"               allow "$(mcp get_deployment_logs '{"id":"x","follow":true}')"
check "evaluate_policy"                          allow "$(mcp evaluate_policy '{"action":"project:view","entity_id":"p"}')"
check "export_resource needs the prompt"         pass  "$(mcp export_resource '{"id":"abc"}')"

### MCP: prod mutations deny ###
check "update_environment prod"                  deny  "$(mcp update_environment '{"id":"mcptest-prod","description":"x"}')"
check "delete_environment prod"                  deny  "$(mcp delete_environment '{"id":"mcptest-prod"}')"
check "deploy_environment prod"                  deny  "$(mcp deploy_environment '{"id":"mcptest-prod"}')"
check "decommission_environment prod"            deny  "$(mcp decommission_environment '{"id":"mcptest-prod"}')"
check "create_deployment PROVISION prod"         deny  "$(mcp create_deployment '{"instance_id":"mcptest-prod-demo","action":"PROVISION"}')"
check "propose_deployment DECOMMISSION prod"     deny  "$(mcp propose_deployment '{"instance_id":"mcptest-prod-demo","action":"DECOMMISSION"}')"
check "set_instance_secret prod"                 deny  "$(mcp set_instance_secret '{"instance_id":"mcptest-prod-demo","name":"k","value":"v"}')"
check "update_instance prod"                     deny  "$(mcp update_instance '{"id":"mcptest-prod-demo","version":"latest"}')"
check "orphan_instance prod"                     deny  "$(mcp orphan_instance '{"instance_id":"mcptest-prod-demo"}')"
check "copy_instance prod destination"           deny  "$(mcp copy_instance '{"source_id":"mcptest-testa-demo","destination_id":"mcptest-prod-demo"}')"
check "set_environment_default prod"             deny  "$(mcp set_environment_default '{"environment_id":"mcptest-prod","resource_id":"u"}')"
check "delete_project prod-matching id"          deny  "$(mcp delete_project '{"id":"prodsvc"}')"
check "create_environment named prod"            deny  "$(mcp create_environment '{"project_id":"mcptest","id":"prod","name":"Production"}')"
check "approve_deployment always"                deny  "$(mcp approve_deployment '{"id":"7f3e0000-0000-0000-0000-000000000000"}')"
check "update_resource on prod instance"         deny  "$(mcp update_resource '{"id":"mcptest-prod-demo.bucket","name":"x"}')"
check "create_resource_grant prod resource"      deny  "$(mcp create_resource_grant '{"resource_id":"mcptest-prod-demo.bucket","action":"resource:export"}')"

### MCP: intended allows / pass-throughs ###
check "create_deployment PLAN on prod"           pass  "$(mcp create_deployment '{"instance_id":"mcptest-prod-demo","action":"PLAN"}')"
check "copy_instance FROM prod source"           pass  "$(mcp copy_instance '{"source_id":"mcptest-prod-demo","destination_id":"mcptest-testa-demo"}')"
check "fork_environment from prod parent"        pass  "$(mcp fork_environment '{"parent_id":"mcptest-prod","id":"agentx7","name":"Fork"}')"
check "plan_deployment (uuid)"                   pass  "$(mcp plan_deployment '{"id":"u"}')"
check "rollback_deployment (uuid)"               pass  "$(mcp rollback_deployment '{"id":"u"}')"
check "reject_deployment (uuid)"                 pass  "$(mcp reject_deployment '{"id":"u"}')"
check "abort_deployment (uuid)"                  pass  "$(mcp abort_deployment '{"id":"u"}')"
check "update_environment non-prod"              pass  "$(mcp update_environment '{"id":"mcptest-testa","description":"prep for prod rollout"}')"
check "create_deployment PROVISION non-prod"     pass  "$(mcp create_deployment '{"instance_id":"mcptest-testa-demo","action":"PROVISION"}')"
check "delete_project non-prod"                  pass  "$(mcp delete_project '{"id":"mcptest"}')"
check "create_project (design op)"               pass  "$(mcp create_project '{"id":"myproj","name":"My Project"}')"
check "update_resource by uuid"                  pass  "$(mcp update_resource '{"id":"9f75ac92-fd92-4152-ae5b-9e30400e8830","name":"x"}')"
check "create_group (out of scope)"              pass  "$(mcp create_group '{"name":"g"}')"

### MCP: segment extraction (judge bugs from 2026-07-30 session) ###
check "component named prodcache, env testa"     pass  "$(mcp set_instance_secret '{"instance_id":"mcptest-testa-prodcache","name":"k","value":"v"}')"
check "env preprod blocked (substring)"          deny  "$(mcp update_environment '{"id":"mcptest-preprod","description":"x"}')"
check "project named prodsvc, env testa"         pass  "$(mcp update_environment '{"id":"prodsvc-testa","description":"x"}')"

### Bash: mass CLI ###
check "stable publish blocked"                   deny  "$(bashcmd 'cd bundles/b && mass bundle publish')"
check "dev publish allowed"                      pass  "$(bashcmd 'mass bundle publish --development')"
check "dev publish -d allowed"                   pass  "$(bashcmd 'mass bundle publish -d')"
check "publish w/ other flags still blocked"     deny  "$(bashcmd 'mass bundle publish --skip-lint')"
check "instance deploy prod"                     deny  "$(bashcmd 'mass instance deploy ecomm-prod-db -m msg')"
check "instance deploy prod --plan"              pass  "$(bashcmd 'mass instance deploy ecomm-prod-db --plan -m msg')"
check "instance destroy prod (alias pkg)"        deny  "$(bashcmd 'mass pkg destroy ecomm-prod-db --force')"
check "instance deploy test env"                 pass  "$(bashcmd 'mass instance deploy ecomm-agentx7k2-db -m msg')"
check "env update prod (alias env)"              deny  "$(bashcmd 'mass env update ecomm-prod -d desc')"
check "environment default prod"                 deny  "$(bashcmd 'mass environment default ecomm-prod res-id')"
check "project delete prod-matching"             deny  "$(bashcmd 'mass project delete prodsvc')"
check "read-only mass commands"                  pass  "$(bashcmd 'mass instance get ecomm-prod-db')"
check "non-mass command untouched"               pass  "$(bashcmd 'tofu plan -out tf.plan')"
check "compound cmd hides publish"               deny  "$(bashcmd 'echo hi && mass bundle publish')"
check "env-var prefixed mass cmd"                deny  "$(bashcmd 'MASSDRIVER_PROFILE=x mass bundle publish')"
check "massive not mass"                         pass  "$(bashcmd 'massive-tool run mass-transit')"
check "publish --help is read-only"              pass  "$(bashcmd 'mass bundle publish --help')"
check "publish -h in compound cmd"               pass  "$(bashcmd 'grep -rl x . 2>/dev/null; echo ---; mass bundle publish -h 2>&1 | head -60')"

### Custom production_pattern from .claude/massdriver.local.md ###
mkdir -p "$WORKDIR/.claude"
cat > "$WORKDIR/.claude/massdriver.local.md" <<'EOF'
---
production_pattern: (live|prd)
---
EOF
check "custom: live blocked"                     deny  "$(mcp update_environment '{"id":"mcptest-live","description":"x"}')"
check "custom: prod now allowed"                 pass  "$(mcp update_environment '{"id":"mcptest-prod","description":"x"}')"
check "custom: prd instance deploy blocked"      deny  "$(bashcmd 'mass instance deploy shop-prd-db -m msg')"
rm -rf "$WORKDIR/.claude"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
