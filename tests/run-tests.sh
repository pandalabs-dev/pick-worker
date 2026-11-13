#!/usr/bin/env bash
# Runs every case in cases.sh and compares the output with expected.tsv,
# then the codex-run and pick-guard checks.
# Exit 0 when all pass, 1 otherwise.
# After an intended change of behaviour: bash tests/cases.sh > tests/expected.tsv, read the diff, commit.
HERE="$(cd "$(dirname "$0")" && pwd)"
actual="$(bash "$HERE/cases.sh")"
if diff <(printf '%s\n' "$actual") "$HERE/expected.tsv"; then
  echo "ok: $(printf '%s\n' "$actual" | wc -l | tr -d ' ') cases match"
else
  echo "FAIL: output differs from tests/expected.tsv (lines with < are the current output)" >&2
  exit 1
fi
bash "$HERE/codex-run-tests.sh" || exit 1
bash "$HERE/pick-guard-tests.sh" || exit 1
