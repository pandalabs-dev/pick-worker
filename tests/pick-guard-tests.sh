#!/usr/bin/env bash
# Checks the guard with local hook inputs and workflow files. No network calls.
HERE="$(cd "$(dirname "$0")" && pwd)"
G="$HERE/../scripts/pick-guard"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { pass=$((pass + 1)); }
no() { fail=$((fail + 1)); echo "FAIL: $case_name: $1" >&2; }
input() { jq -nc --arg tool "$1" --arg type "$2" --arg prompt "$3" --arg model "$4" '{tool_name:$tool,tool_input:{subagent_type:$type,prompt:$prompt,model:$model}}'; }
check() {
  local expected="$1" reason="${2:-}" output rc
  output="$("$G" < "$TMP/input" 2>"$TMP/stderr")"; rc=$?
  if [ "$rc" != 0 ]; then no "exit $rc"; return; fi
  if [ "$expected" = allow ]; then
    [ -z "$output" ] && ok || no "expected no output, got $output"
  elif printf '%s\n' "$output" | jq -es --arg reason "$reason" 'length == 1 and (.[0] | type == "object" and keys == ["hookSpecificOutput"] and (.hookSpecificOutput | keys == ["hookEventName", "permissionDecision", "permissionDecisionReason"] and .hookEventName == "PreToolUse" and .permissionDecision == "deny" and .permissionDecisionReason == $reason))' >/dev/null 2>&1; then
    ok
  else
    no "invalid denial or reason: $output"
  fi
}
agent() { case_name="$1"; input "$2" "$3" "$4" "$5" > "$TMP/input"; check "$6" "${7:-}"; }
workflow() { case_name="$1"; jq -nc --arg script "$2" --arg path "$3" '{tool_name:"Workflow",tool_input:{script:$script,scriptPath:$path}}' > "$TMP/input"; check "$4" "${5:-}"; }
no_pick='No worker pick in this brief. Before every subagent launch: 1) score the task 1 to 100 (size, freedom, depth, blast radius, verification: 0 to 20 each); 2) run ~/.claude/skills/pick-worker/scripts/pick-worker <score> (add --claude-only "<reason>" for landing on main, secrets, live systems, browser or simulator gates, MCP tools); 3) launch what it prints and put its output line into the brief as: Worker pick: <line>. Details: ~/.claude/skills/pick-worker/SKILL.md.'
no_workflow='This workflow script never mentions pick-worker. Every agent() call gets its worker from ~/.claude/skills/pick-worker/scripts/pick-worker (read the usage once at the start and pass it with --usage), and each agent prompt carries the line: Worker pick: <line>. Details: ~/.claude/skills/pick-worker/SKILL.md.'
opus='claude opus | score 50 standard | reason'
fable='claude fable | score 90 hardest | reason'
sonnet='codex gpt-6.1-terra effort=xhigh supervisor=sonnet | score 45 standard | reason'
copus='codex gpt-6-astra effort=xhigh supervisor=opus | score 90 hardest | reason'
main='codex gpt-6-luna effort=xhigh supervisor=main | score 20 easy | reason'
for type in web-fetch claude-code-guide statusline-setup; do agent "exempt $type" Agent "$type" '' '' allow; done
agent 'missing pick' Agent worker 'do work' opus deny "$no_pick"
agent 'opus right' Agent worker "Worker pick: $opus" opus allow
agent 'opus wrong' Agent worker "$opus" sonnet deny 'The pick says claude opus, so this launch must pass model: "opus" (it passed: sonnet).'
agent 'opus missing model' Agent worker "$opus" '' deny 'The pick says claude opus, so this launch must pass model: "opus" (it passed: none).'
agent 'fable right' Agent worker "$fable" fable allow
agent 'fable wrong' Agent worker "$fable" opus deny 'The pick says claude fable, so this launch must pass model: "fable" (it passed: opus).'
agent 'sonnet right' Agent worker "$sonnet" sonnet allow
agent 'sonnet wrong' Agent worker "$sonnet" opus deny 'The pick says codex gpt-6.1-terra effort=xhigh supervisor=sonnet, so this launch must pass model: "sonnet" (it passed: opus).'
agent 'codex opus right' Agent worker "$copus" opus allow
agent 'codex opus wrong' Agent worker "$copus" sonnet deny 'The pick says codex gpt-6-astra effort=xhigh supervisor=opus, so this launch must pass model: "opus" (it passed: sonnet).'
agent 'fork skips model' Agent fork "$opus" arbitrary allow
agent 'fork still needs pick' Agent fork '' opus deny "$no_pick"
agent 'inline' Agent worker 'inline | score 10 inline | reason' opus deny 'The pick says inline: do this task yourself, without a subagent.'
agent 'main supervisor' Agent worker "$main" opus deny 'The pick says supervisor=main: no subagent. Run ~/.claude/skills/pick-worker/scripts/codex-run yourself and verify the result by the contract ~/.claude/agents/codex-operator.md.'
agent 'task tool' Task worker "$opus" opus allow
agent 'task without pick' Task worker '' opus deny "$no_pick"
agent 'first match' Agent worker "$opus then $fable" fable deny 'The pick says claude opus, so this launch must pass model: "opus" (it passed: fable).'
agent 'trailing newline model' Agent worker "$opus" $'opus\n' deny $'The pick says claude opus, so this launch must pass model: "opus" (it passed: opus\n).'
agent 'escaped model' Agent worker "$opus" '"bad"' deny 'The pick says claude opus, so this launch must pass model: "opus" (it passed: "bad").'
workflow 'script mentions picker' 'run pick-worker' '' allow
workflow 'script lacks picker' 'agent()' '' deny "$no_workflow"
workflow 'script has pick' "$opus" '' allow
printf 'run pick-worker\n' > "$TMP/with"
printf 'agent()\n' > "$TMP/without"
workflow 'path mentions picker' '' "$TMP/with" allow
workflow 'path lacks picker' '' "$TMP/without" deny "$no_workflow"
workflow 'newline script wins over path' $'\n' "$TMP/with" deny "$no_workflow"
workflow 'script wins over path' 'agent()' "$TMP/with" deny "$no_workflow"
workflow 'no script or path' '' '' allow
workflow 'unreadable path' '' "$TMP/missing" allow
case_name='invalid JSON'; printf '{' > "$TMP/input"; check allow
case_name='NUL in JSON'; printf '{"tool_name":"Agent","tool_input":{"model":"opus\\u0000"}}' > "$TMP/input"; check allow
case_name='multiple JSON values'; printf '{} {}' > "$TMP/input"; check allow
case_name='off'; input Agent worker '' '' > "$TMP/input"; PICK_GUARD=off check allow
case_name='other tool'; input Bash worker '' '' > "$TMP/input"; check allow
case_name='no jq'; mkdir -p "$TMP/empty"; output="$(PATH="$TMP/empty" /bin/bash "$G" < "$TMP/input")"; rc=$?; [ "$rc" = 0 ] && [ -z "$output" ] && ok || no 'did not fail open'
case_name='jq failure'; mkdir -p "$TMP/bin"; printf '#!/bin/sh\nexit 1\n' > "$TMP/bin/jq"; chmod 755 "$TMP/bin/jq"; output="$(PATH="$TMP/bin:$PATH" /bin/bash "$G" < "$TMP/input")"; rc=$?; [ "$rc" = 0 ] && [ -z "$output" ] && ok || no 'did not fail open'
if [ "$fail" = 0 ]; then
  echo "ok: pick-guard, $pass checks pass"
else
  echo "FAIL: pick-guard, $fail of $((pass + fail)) checks fail" >&2
  exit 1
fi
