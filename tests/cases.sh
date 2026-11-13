#!/usr/bin/env bash
# Prints one line per test case: arguments, exit code, output of scripts/pick-worker.
# run-tests.sh compares this with expected.tsv. No case touches the real altseat or codex.
HERE="$(cd "$(dirname "$0")" && pwd)"
P="$HERE/../scripts/pick-worker"
F="$HERE/fake-altseat"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export PICK_WORKER_LOG=off   # the log cases at the end set their own file
t() { out="$("$P" "$@" 2>&1)"; rc=$?; printf '%s\texit %s\t%s\n' "$*" "$rc" "$(echo "$out" | head -1)"; }
U() { echo "claude_week=$1 fable=$2 codex_week=$3"; }
# Claude side per tier (claude behind)
t 10 --usage "$(U 20 10 60)"
t 25 --usage "$(U 20 10 60)"
t 45 --usage "$(U 20 10 60)"
t 70 --usage "$(U 20 10 60)"
t 90 --usage "$(U 20 10 60)"
# Codex side per tier (codex behind)
t 16 --usage "$(U 60 10 20)"
t 35 --usage "$(U 60 10 20)"
t 36 --usage "$(U 60 10 20)"
t 60 --usage "$(U 60 10 20)"
t 61 --usage "$(U 60 10 20)"
t 80 --usage "$(U 60 10 20)"
t 81 --usage "$(U 60 10 20)"
t 100 --usage "$(U 60 10 20)"
# tie
t 50 --usage "$(U 40 10 40)"
# overrides
t 40 --claude-only "landing on main" --usage "$(U 90 10 5)"
t 90 --claude-only "ssh to the box" --usage "$(U 90 10 5)"
t 50 --usage "claude_week=30 fable=10 codex_week=--"
t 50 --usage "claude_week=30 fable=10"
t 50 --usage "$(U 99 10 96)"
t 50 --usage "$(U 30 10 95)"
t 50 --usage "$(U 95 10 94)"
# fable guard
t 85 --usage "$(U 30 79 50)"
t 85 --usage "$(U 30 80 50)"
t 85 --usage "claude_week=30 codex_week=50"
# bad arguments
t
t 0
t 101
t abc
t 50 --bogus
t 50 60
t 50 --claude-only
t 50 --usage "claude_week=x"
t 50 --usage "foo=1"
# live path with a stand-in altseat
L_FRESH='Claude Code
* a@x  ~/.claude  session 0 %  week 70 %  fable 40 %  (2 min ago)
Codex
* personal  ~/.codex  session --  week 20 %  (3 min ago)'
L_STALE='Claude Code
* a@x  ~/.claude  session 0 %  week 70 %  fable 40 %  (2 min ago)
Codex
* personal  ~/.codex  session --  week 0 %  (4 d ago)'
L_DASH='Claude Code
* a@x  ~/.claude  session 0 %  week 70 %  fable 40 %  (2 min ago)
Codex
* personal  ~/.codex  session --  week --'
L_NOCODEX='Claude Code
* a@x  ~/.claude  session 0 %  week 70 %  fable 40 %  (2 min ago)'
lt() { label="$1"; shift; out="$(PICK_WORKER_ALTSEAT="$F" "$P" "$@" 2>&1)"; rc=$?; printf '%s\texit %s\t%s\n' "stand-in: $label; $*" "$rc" "$out"; }
FAKE_LIST="$L_FRESH" lt "fresh numbers" 70
FAKE_LIST="$L_STALE" FAKE_REFRESH='ok   a@x: usage updated' lt "codex 4 d old, refresh ok but still old" 70
FAKE_LIST="$L_STALE" FAKE_REFRESH='warn personal: usage request failed' lt "codex 4 d old, refresh warns" 70
FAKE_LIST="$L_FRESH" FAKE_REFRESH='skip personal: no usable login' lt "fresh codex, no refresh needed" 30
FAKE_LIST="$L_DASH" lt "codex week --" 70
FAKE_LIST="$L_NOCODEX" lt "no Codex section" 70
L_MARKED='Claude Code
* a@x  ~/.claude  session 0 %  week 70 %  fable 40 %  (2 min ago)
Codex
* personal  ~/.codex  session --  week 20 %  login expired  (3 min ago)'
L_CSTALE='Claude Code
* a@x  ~/.claude  session 0 %  week 70 %  fable 40 %  (45 min ago)
Codex
* personal  ~/.codex  session --  week 20 %  (3 min ago)'
FAKE_LIST="$L_MARKED" lt "list marks codex login expired" 70
FAKE_LIST="$L_CSTALE" FAKE_REFRESH='ok   a@x: usage updated' lt "claude numbers 45 min old after refresh" 70
mkdir -p "$TMP/nocodex-bin" && for b in awk grep head bash env; do ln -s "$(command -v $b)" "$TMP/nocodex-bin"/$b; done
out="$(FAKE_LIST="$L_FRESH" PICK_WORKER_ALTSEAT="$F" PATH="$TMP/nocodex-bin" /bin/bash "$P" 70 2>&1)"; printf '%s\texit %s\t%s\n' "stand-in: no codex on PATH; 70" "$?" "$out"
# pick log
lg() { label="$1"; shift; out="$(cd "$TMP" && XDG_STATE_HOME="$TMP/xdg" PICK_WORKER_LOG="$LOGF" "$P" "$@" 2>&1)"; rc=$?; printf '%s\texit %s\t%s\n' "log: $label; $*" "$rc" "$(echo "$out" | head -1)"; }
LOGF="$TMP/state/picks.log"
lg "written" 20 --usage "$(U 60 10 20)"
lg "written" 10
printf '%s\t%s\n' "log: file after two picks" "$(sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z/<time>/' "$LOGF" | tr '\n' '|')"
LOGF=off
lg "off" 20 --usage "$(U 60 10 20)"
printf '%s\t%s\n' "log: nothing written when off" "$(ls "$TMP" | grep -cE '^(off|xdg)$')"
LOGF=/dev/null/picks.log
lg "unwritable path" 20 --usage "$(U 60 10 20)"
LOGF="$TMP/state/picks.log"
lg "bad arguments are not logged" 0
printf '%s\t%s\n' "log: lines after a bad call" "$(wc -l < "$LOGF" | tr -d ' ')"
