#!/usr/bin/env bash
# Installs the skill from this repo into the Claude Code skills folder.
# Usage: ./install.sh            installs into ~/.claude/skills/pick-worker
#        CLAUDE_SKILLS_DIR=<dir> ./install.sh   installs into <dir>/pick-worker
# Runs the tests first and installs nothing when they fail.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
dest="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}/pick-worker"

bash "$HERE/tests/run-tests.sh"

mkdir -p "$dest/scripts"
cp "$HERE/SKILL.md" "$dest/SKILL.md"
cp "$HERE/scripts/pick-worker" "$dest/scripts/pick-worker"
cp "$HERE/scripts/codex-run" "$dest/scripts/codex-run"
cp "$HERE/scripts/codex-rules.md" "$dest/scripts/codex-rules.md"
chmod 755 "$dest/scripts/pick-worker" "$dest/scripts/codex-run"
chmod 644 "$dest/scripts/codex-rules.md"

sum() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -c1-12; }
echo "installed into $dest"
printf '  %-23s %s\n' "SKILL.md" "$(sum "$dest/SKILL.md")"
printf '  %-23s %s\n' "scripts/pick-worker" "$(sum "$dest/scripts/pick-worker")"
printf '  %-23s %s\n' "scripts/codex-run" "$(sum "$dest/scripts/codex-run")"
printf '  %-23s %s\n' "scripts/codex-rules.md" "$(sum "$dest/scripts/codex-rules.md")"
