#!/usr/bin/env bash
# Deterministic PreToolUse safety guard for the Massdriver plugin.
#
# Reads a Claude Code PreToolUse hook payload on stdin and emits a permission
# decision on stdout:
#
#   "allow"  -> auto-approve (skips the permission prompt). Only used for
#               read-only MCP tools.
#   "deny"   -> block the call with a one-line reason.
#   (silent) -> no opinion; the normal permission flow (user prompt /
#               settings allowlist) decides.
#
# Policy (mirrors templates/massdriver.local.md):
#   * Mutations targeting a production-matching environment are denied.
#   * The production pattern is read from .claude/massdriver.local.md
#     (production_pattern: <regex>) relative to the session cwd, defaulting
#     to (prod|production).
#   * Matching is SUBSTRING matching against the ENV SEGMENT of a slug —
#     never the whole slug, never free text. "preprod" is blocked by the
#     default pattern; a component named "prodcache" in env "testa" is not.
#   * approve_deployment and non-development `mass bundle publish` are
#     always denied — those are human authorization steps.
#   * Ambiguous cases fall through to the normal permission prompt rather
#     than guessing.
#
# Slug shapes (ids are lowercase alphanumeric, so '-' only separates segments):
#   instance    <project>-<env>-<component>          env = segment 2 of 3
#   environment <project>-<env>                      env = segment 2 of 2
#   resource    <project>-<env>-<component>.<field>  env = segment 2 of slug part
#
# Dependencies: bash 3.2+ and POSIX awk/sed only (macOS + Linux out of the box).

set -euo pipefail
set -f # no globbing — command tokens like '*' must stay literal

PAYLOAD="$(cat)"

# Extract a string value for a key from the JSON payload. Sequential
# tokenizer with escape handling: text inside string values is consumed
# atomically, so a key name appearing inside another value never matches.
# Prints the first match; prints nothing if the key is absent.
json_get() {
  printf '%s' "$PAYLOAD" | awk -v key="$1" '
    { buf = buf $0 "\n" }
    END {
      n = length(buf); i = 1
      while (i <= n) {
        c = substr(buf, i, 1)
        if (c != "\"") { i++; continue }
        # parse a string token
        s = ""; i++
        while (i <= n) {
          c = substr(buf, i, 1)
          if (c == "\\") {
            d = substr(buf, i + 1, 1)
            if (d == "n") s = s "\n"
            else if (d == "t") s = s "\t"
            else if (d == "r") s = s "\r"
            else if (d == "u") { s = s substr(buf, i, 6); i += 4 }
            else s = s d
            i += 2; continue
          }
          if (c == "\"") { i++; break }
          s = s c; i++
        }
        # is this string a key for our target?
        j = i
        while (j <= n && substr(buf, j, 1) ~ /[ \t\n\r]/) j++
        if (substr(buf, j, 1) != ":" || s != key) continue
        j++
        while (j <= n && substr(buf, j, 1) ~ /[ \t\n\r]/) j++
        if (substr(buf, j, 1) == "\"") {
          v = ""; j++
          while (j <= n) {
            c = substr(buf, j, 1)
            if (c == "\\") {
              d = substr(buf, j + 1, 1)
              if (d == "n") v = v "\n"
              else if (d == "t") v = v "\t"
              else if (d == "r") v = v "\r"
              else if (d == "u") { v = v substr(buf, j, 6); j += 4 }
              else v = v d
              j += 2; continue
            }
            if (c == "\"") break
            v = v c; j++
          }
          print v; exit
        } else {
          v = ""
          while (j <= n) {
            c = substr(buf, j, 1)
            if (c ~ /[,}\]]/ || c ~ /[ \t\n\r]/) break
            v = v c; j++
          }
          print v; exit
        }
      }
    }'
}

DEFAULT_PATTERN='(prod|production)'
PATTERN="$DEFAULT_PATTERN"

load_pattern() {
  local cwd local_md p rc
  cwd="$(json_get cwd)"
  local_md="${cwd:-.}/.claude/massdriver.local.md"
  [ -f "$local_md" ] || return 0
  p="$(sed -n 's/^[[:space:]]*production_pattern:[[:space:]]*//p' "$local_md" | head -n 1 | sed "s/^[\"']//; s/[\"']\$//")"
  [ -n "$p" ] || return 0
  rc=0
  ( [[ probe =~ $p ]] ) 2>/dev/null || rc=$?
  if [ "$rc" -le 1 ]; then # 0/1 = valid regex; 2 = unusable, keep default
    PATTERN="$p"
  fi
}

matches() {
  [ -n "$1" ] && [[ $1 =~ $PATTERN ]]
}

# Env segment of a slug with the expected segment count; falls back to the
# whole slug when the shape is unexpected (conservative).
env_of() {
  local slug="$1" expected="$2"
  local IFS='-'
  # shellcheck disable=SC2206
  local parts=($slug)
  if [ "${#parts[@]}" -eq "$expected" ]; then
    printf '%s' "${parts[1]}"
  else
    printf '%s' "$slug"
  fi
}

slug_is_prod() { # slug, expected_segments
  local env
  [ -n "$1" ] || return 1
  env="$(env_of "$1" "$2")"
  matches "$env"
}

emit() { # decision, reason
  # Reasons are plugin-authored constants (no user input), safe to inline.
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":"%s"}}\n' "$1" "$2"
  exit 0
}

deny() { emit deny "$1"; }
allow() { emit allow "$1"; }

check_mcp() {
  local tool="$1" slug env action

  case "$tool" in
    approve_deployment)
      deny "Approving deployments is a human authorization step. Approve in the Massdriver UI, or reject with reject_deployment." ;;
    get_*|list_*|compare_*|evaluate_*|explain_*)
      allow "Read-only Massdriver tool; safe on any environment." ;;
    export_resource)
      # A read, but returns unmasked secrets — leave it to the permission prompt.
      exit 0 ;;
    plan_deployment|rollback_deployment|reject_deployment|abort_deployment)
      # Dry-runs, proposals needing approval, and stop operations.
      exit 0 ;;
    fork_environment)
      # Reads the parent (even prod) and creates a NEW environment.
      exit 0 ;;
    create_deployment|propose_deployment)
      action="$(json_get action)"
      [ "$action" = "PLAN" ] && exit 0 # dry-run; safe on any environment
      slug="$(json_get instance_id)"
      if slug_is_prod "$slug" 3; then
        deny "$slug targets a production environment (pattern: $PATTERN). Use a non-production environment, or action: PLAN for a dry-run."
      fi ;;
    update_instance)
      slug="$(json_get id)"
      if slug_is_prod "$slug" 3; then
        deny "$slug targets a production environment (pattern: $PATTERN); refusing to mutate a production instance."
      fi ;;
    set_instance_secret|remove_instance_secret|set_remote_reference|remove_remote_reference|orphan_instance)
      slug="$(json_get instance_id)"
      if slug_is_prod "$slug" 3; then
        deny "$slug targets a production environment (pattern: $PATTERN); refusing to mutate a production instance."
      fi ;;
    copy_instance)
      # A production source is a read and is fine; only the destination is a write.
      slug="$(json_get destination_id)"
      if slug_is_prod "$slug" 3; then
        deny "Destination $slug targets a production environment (pattern: $PATTERN); refusing to overwrite its params."
      fi ;;
    update_environment|delete_environment|deploy_environment|decommission_environment)
      slug="$(json_get id)"
      if slug_is_prod "$slug" 2; then
        deny "$slug matches the production pattern ($PATTERN); refusing to mutate a production environment."
      fi ;;
    set_environment_default)
      slug="$(json_get environment_id)"
      if slug_is_prod "$slug" 2; then
        deny "$slug matches the production pattern ($PATTERN); refusing to mutate a production environment."
      fi ;;
    create_environment)
      slug="$(json_get id)"
      if matches "$slug"; then
        deny "Environment id '$slug' matches the production pattern ($PATTERN). Agents may not create production-named environments; create it in the Massdriver UI if intended."
      fi ;;
    delete_project)
      slug="$(json_get id)"
      if matches "$slug"; then
        deny "Project id '$slug' matches the production pattern ($PATTERN); refusing to delete a production project."
      fi ;;
    update_resource|delete_resource)
      slug="$(json_get id)"
      case "$slug" in
        *.*) # "<instance-slug>.<field>" — provisioned by an instance
          env="$(env_of "${slug%%.*}" 3)"
          if matches "$env"; then
            deny "Resource belongs to a production instance (env '$env' matches $PATTERN); refusing to mutate it."
          fi ;;
      esac ;;
    create_resource_grant)
      slug="$(json_get resource_id)"
      case "$slug" in
        *.*)
          env="$(env_of "${slug%%.*}" 3)"
          if matches "$env"; then
            deny "Resource belongs to a production instance (env '$env' matches $PATTERN); refusing to mutate it."
          fi ;;
      esac ;;
  esac
  # Everything else (design ops, groups, policies, OCI repos, ...) goes
  # through the normal permission flow.
  exit 0
}

check_bash() {
  local cmd seg action slug tok
  cmd="$(json_get command)"
  case " $cmd" in
    *[\ \;\&\|\(]mass\ *) : ;; # contains a mass invocation
    *) exit 0 ;;
  esac

  # Split compound commands into simple segments, one per line.
  printf '%s\n' "$cmd" | awk '{ gsub(/&&|\|\||;|\|/, "\n"); print }' | while IFS= read -r seg; do
    # shellcheck disable=SC2086
    set -- $seg
    while [ "$#" -gt 0 ] && case "$1" in -*) false ;; *=*) true ;; *) false ;; esac; do
      shift # leading VAR=val assignments
    done
    [ "$#" -ge 2 ] && [ "$1" = "mass" ] || continue

    case "$2" in
      bundle)
        if [ "${3:-}" = "publish" ]; then
          shift 3
          local dev=""
          for tok in "$@"; do
            case "$tok" in --development|-d) dev=1 ;; esac
          done
          if [ -z "$dev" ]; then
            deny "Missing --development flag. Stable releases need human authorization. Use: mass bundle publish --development"
          fi
        fi ;;
      instance|inst|package|pkg)
        action="${3:-}"
        case "$action" in
          deploy|destroy|version)
            case " $seg " in *" --plan "*)
              [ "$action" = "deploy" ] && continue ;; # dry-run; safe anywhere
            esac
            shift 3
            slug=""
            for tok in "$@"; do
              case "$tok" in -*) ;; *) slug="$tok"; break ;; esac
            done
            if slug_is_prod "$slug" 3; then
              deny "$slug targets a production environment (pattern: $PATTERN). Use a non-production environment."
            fi ;;
        esac ;;
      environment|env)
        action="${3:-}"
        case "$action" in
          update|delete|default)
            shift 3
            slug=""
            for tok in "$@"; do
              case "$tok" in -*) ;; *) slug="$tok"; break ;; esac
            done
            if slug_is_prod "$slug" 2; then
              deny "$slug matches the production pattern ($PATTERN); refusing to mutate a production environment."
            fi ;;
        esac ;;
      project)
        if [ "${3:-}" = "delete" ]; then
          shift 3
          slug=""
          for tok in "$@"; do
            case "$tok" in -*) ;; *) slug="$tok"; break ;; esac
          done
          if matches "$slug"; then
            deny "Project '$slug' matches the production pattern ($PATTERN); refusing to delete a production project."
          fi
        fi ;;
    esac
  done
  exit 0
}

main() {
  local tool_name
  tool_name="$(json_get tool_name)"
  load_pattern

  case "$tool_name" in
    Bash)
      check_bash ;;
    mcp__plugin_massdriver_massdriver__*|mcp__massdriver__*)
      check_mcp "${tool_name##*__}" ;;
  esac
  exit 0
}

main
