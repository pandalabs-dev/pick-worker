#!/usr/bin/env bash
# Checks scripts/codex-run against a stand-in codex (tests/fake-codex) on PATH.
# Nothing here calls the real Codex. Exit 0 when every check passes, 1 otherwise.
HERE="$(cd "$(dirname "$0")" && pwd)"
R="$HERE/../scripts/codex-run"
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/bin" "$TMP/rec"
cp "$HERE/fake-codex" "$TMP/bin/codex"
export PATH="$TMP/bin:$PATH" FAKE_CODEX_DIR="$TMP/rec" CODEX_HOME="$TMP/codex-home"
unset FAKE_SANDBOX_RC FAKE_EXEC_RC CODEX_RUN_UNAME CODEX_RUN_HOST

pass=0; fail=0
ok()  { pass=$((pass + 1)); }
no()  { fail=$((fail + 1)); echo "FAIL: $case_name: $1" >&2; }
has()    { grep -qxF -- "$2" "$1" && ok || no "$(basename "$1") lacks line: $2"; }
hasnot() { grep -qxF -- "$2" "$1" && no "$(basename "$1") has line: $2" || ok; }
contains()    { grep -qF -- "$2" "$1" && ok || no "$(basename "$1") lacks text: $2"; }
notcontains() { grep -qF -- "$2" "$1" && no "$(basename "$1") has text: $2" || ok; }
eq() { [ "$1" = "$2" ] && ok || no "expected '$2', got '$1'"; }

# A git repo with one commit, a worktree in .worktrees/wt, an ignored .local/.
G="$TMP/repo"
mkdir -p "$G"
( cd "$G" && git init -q -b main && printf '.local/\n' > .gitignore && git add .gitignore \
  && git -c user.name=t -c user.email=t@example.com commit -qm init \
  && mkdir -p .worktrees && git worktree add -q -b feat/x .worktrees/wt )
WT="$G/.worktrees/wt"
NG="$TMP/plain"; mkdir -p "$NG"
echo "Do the thing." > "$TMP/task.md"
echo "Report git status." > "$TMP/follow.md"
OUT="$TMP/out"
FS_PREFIX='permissions.git-write.filesystem='

run() {  # run codex-run, keep its stdout in $TMP/stdout and its exit code in $rc
  rm -f "$TMP/rec/args" "$TMP/rec/stdin" "$TMP/rec/sandbox-args"
  /bin/bash "$R" "$@" >"$TMP/stdout" 2>"$TMP/stderr"; rc=$?
}
fsline() { grep -F -- "$FS_PREFIX" "$TMP/rec/args"; }
profile_checks() {  # profile on, no -s next to it
  has "$TMP/rec/args" 'default_permissions="git-write"'
  has "$TMP/rec/args" 'permissions.git-write.extends=":workspace"'
  has "$TMP/rec/args" 'permissions.git-write.network.enabled=true'
  hasnot "$TMP/rec/args" '-s'
  hasnot "$TMP/rec/args" '--sandbox'
  notcontains "$TMP/rec/args" 'sandbox_mode'
}

case_name="darwin main checkout"
CODEX_RUN_UNAME=Darwin run --model gpt-6-luna --task "$TMP/task.md" --out "$OUT" --workspace "$G"
eq "$rc" 0
profile_checks
has "$TMP/rec/args" '-m'; has "$TMP/rec/args" 'gpt-6-luna'
has "$TMP/rec/args" 'model_reasoning_effort="xhigh"'
has "$TMP/rec/args" '--json'
has "$TMP/rec/args" "$OUT/codex-last.md"
has "$TMP/rec/args" "$G"
eq "$(sed -n 1,2p "$TMP/rec/args" | tr '\n' ' ')" "exec --json "
eq "$(tail -1 "$TMP/rec/args")" "-"
eq "$(fsline)" "$FS_PREFIX"'{":workspace_roots"={"."="write",".git"="write"},"~/Library/pnpm/store"="write","~/.local/share/pnpm/store"="write","~/.npm"="write","~/.nuget/packages"="write"}'
hasnot "$TMP/rec/args" '--skip-git-repo-check'
eq "$(head -1 "$TMP/rec/stdin")" "# Rules for this run"
has "$TMP/rec/stdin" "Workspace: $G. Branch: main."
eq "$(tail -1 "$TMP/rec/stdin")" "Do the thing."
cmp -s <(head -n "$(wc -l < "$HERE/../scripts/codex-rules.md")" "$TMP/rec/stdin") "$HERE/../scripts/codex-rules.md" && ok || no "stdin does not start with the whole rules file"
eq "$(cat "$TMP/rec/cwd")" "$G"
eq "$(cat "$TMP/stdout")" "thread_id=0000-fake-thread
last=$OUT/codex-last.md
events=$OUT/codex-events.jsonl
exit=0"
[ -s "$OUT/codex-events.jsonl" ] && [ -s "$OUT/codex-last.md" ] && [ -f "$OUT/codex-stderr.log" ] && ok || no "output files missing"

case_name="second run numbers its files"
CODEX_RUN_UNAME=Darwin run --model gpt-6-luna --task "$TMP/task.md" --out "$OUT" --workspace "$G"
has "$TMP/stdout" "events=$OUT/codex-events-2.jsonl"
has "$TMP/stdout" "last=$OUT/codex-last-2.md"

case_name="darwin worktree"
CODEX_RUN_UNAME=Darwin run --model gpt-6.1-sol --task "$TMP/task.md" --out "$OUT" --workspace "$WT"
eq "$rc" 0
profile_checks
eq "$(fsline)" "$FS_PREFIX"'{":workspace_roots"={"."="write",".git"="write"},"'"$G"'/.git"="write","'"$G"'/.git/worktrees/wt"="write","~/Library/pnpm/store"="write","~/.local/share/pnpm/store"="write","~/.npm"="write","~/.nuget/packages"="write"}'
has "$TMP/rec/stdin" "Workspace: $WT. Branch: feat/x."

case_name="darwin --no-git"
CODEX_RUN_UNAME=Darwin run --model gpt-6.1-terra --task "$TMP/task.md" --out "$OUT" --workspace "$WT" --no-git
eq "$rc" 0
profile_checks
eq "$(fsline)" "$FS_PREFIX"'{":workspace_roots"={"."="write"},"~/Library/pnpm/store"="write","~/.local/share/pnpm/store"="write","~/.npm"="write","~/.nuget/packages"="write"}'

case_name="darwin plain folder"
CODEX_RUN_UNAME=Darwin run --model gpt-6-astra --task "$TMP/task.md" --out "$OUT" --workspace "$NG"
eq "$rc" 0
notcontains "$TMP/rec/args" '.git"'
has "$TMP/rec/args" '--skip-git-repo-check'
has "$TMP/rec/stdin" "Workspace: $NG. Branch: none."

case_name="darwin resume"
CODEX_RUN_UNAME=Darwin run --model gpt-6-luna --task "$TMP/follow.md" --out "$OUT" --workspace "$WT" --resume 1111-thread
eq "$rc" 0
profile_checks
eq "$(sed -n 1,3p "$TMP/rec/args" | tr '\n' ' ')" "exec resume --json "
eq "$(tail -2 "$TMP/rec/args" | tr '\n' ' ')" "1111-thread - "
hasnot "$TMP/rec/args" '-C'
contains "$TMP/rec/args" "\"$G/.git/worktrees/wt\"=\"write\""
eq "$(cat "$TMP/rec/stdin")" "The run rules from the start of this session still hold.

Report git status."
eq "$(cat "$TMP/rec/cwd")" "$WT"

case_name="linux, allowed host, profile fails"
CODEX_RUN_UNAME=Linux CODEX_RUN_HOST=claudeworker.example FAKE_SANDBOX_RC=1 run --model gpt-6-luna --task "$TMP/task.md" --out "$OUT" --workspace "$WT"
eq "$rc" 0
[ -f "$TMP/rec/sandbox-args" ] && ok || no "profile was not probed"
contains "$TMP/rec/sandbox-args" 'default_permissions="git-write"'
eq "$(tail -2 "$TMP/rec/sandbox-args" | tr '\n' ' ')" "-- true "
has "$TMP/rec/args" '--sandbox'; has "$TMP/rec/args" 'danger-full-access'
notcontains "$TMP/rec/args" 'default_permissions'

case_name="linux, allowed host, resume"
CODEX_RUN_UNAME=Linux CODEX_RUN_HOST=claudeworker FAKE_SANDBOX_RC=1 run --model gpt-6-luna --task "$TMP/follow.md" --out "$OUT" --workspace "$WT" --resume 2222
eq "$rc" 0
has "$TMP/rec/args" 'sandbox_mode="danger-full-access"'
hasnot "$TMP/rec/args" '--sandbox'
notcontains "$TMP/rec/args" 'default_permissions'

case_name="linux, profile works"
CODEX_RUN_UNAME=Linux CODEX_RUN_HOST=otherbox FAKE_SANDBOX_RC=0 run --model gpt-6-luna --task "$TMP/task.md" --out "$OUT" --workspace "$WT"
eq "$rc" 0
profile_checks

case_name="linux, other host, profile fails"
CODEX_RUN_UNAME=Linux CODEX_RUN_HOST=otherbox FAKE_SANDBOX_RC=1 run --model gpt-6-luna --task "$TMP/task.md" --out "$OUT" --workspace "$WT"
eq "$rc" 3
[ -f "$TMP/rec/args" ] && no "codex exec ran" || ok
contains "$TMP/stderr" "no Codex sandbox works on this host (otherbox)"

case_name="bad model"
CODEX_RUN_UNAME=Darwin run --model gpt-5 --task "$TMP/task.md" --out "$OUT" --workspace "$G"
eq "$rc" 2
[ -f "$TMP/rec/args" ] && no "codex exec ran" || ok

case_name="missing task file"
CODEX_RUN_UNAME=Darwin run --model gpt-6-luna --task "$TMP/nope.md" --out "$OUT" --workspace "$G"
eq "$rc" 2

case_name="--out inside a repo"
CODEX_RUN_UNAME=Darwin run --model gpt-6-luna --task "$TMP/task.md" --out "$G/run-out" --workspace "$G"
eq "$rc" 2
[ -e "$G/run-out" ] && no "created the folder inside the repo" || ok
[ -f "$TMP/rec/args" ] && no "codex exec ran" || ok

case_name="--out inside a worktree"
CODEX_RUN_UNAME=Darwin run --model gpt-6-luna --task "$TMP/task.md" --out "$WT/sub/run" --workspace "$WT"
eq "$rc" 2

case_name="--out in an ignored folder of a repo"
CODEX_RUN_UNAME=Darwin run --model gpt-6-luna --task "$TMP/task.md" --out "$G/.local/run" --workspace "$G"
eq "$rc" 0
[ -s "$G/.local/run/codex-events.jsonl" ] && ok || no "no events file in the ignored folder"

case_name="exit code of codex is passed on"
CODEX_RUN_UNAME=Darwin FAKE_EXEC_RC=7 run --model gpt-6-luna --task "$TMP/task.md" --out "$OUT" --workspace "$G"
eq "$rc" 7
has "$TMP/stdout" "exit=7"

case_name="--print-cmd runs nothing"
CODEX_RUN_UNAME=Darwin run --model gpt-6-luna --task "$TMP/task.md" --out "$TMP/out-print" --workspace "$WT" --print-cmd
eq "$rc" 0
[ -f "$TMP/rec/args" ] && no "codex exec ran" || ok
[ -e "$TMP/out-print" ] && no "created the output folder" || ok
has "$TMP/stdout" "sandbox=profile"
has "$TMP/stdout" "codex"
has "$TMP/stdout" 'default_permissions="git-write"'

if [ "$fail" = 0 ]; then
  echo "ok: codex-run, $pass checks pass"
else
  echo "FAIL: codex-run, $fail of $((pass + fail)) checks fail" >&2
  exit 1
fi
