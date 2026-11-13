# Rules for this run

They come from the owner and override anything in the task that conflicts with them. This is a non-interactive run: ask no questions, make routine calls yourself and state each assumption in your report.

## Scope
- Work only inside the workspace you were started in and the folders the task names. Never read or write another project's folder.
- Never open `.env*` files, key files, credential stores or token files, and never print a secret or a token. Never run `gh auth token` or `gh auth status --show-token`, and never read `~/.config/gh`, `~/.codex/auth.json` or `~/.codex/config.toml`.
- No deploys and nothing against a live system: no `fly`, `vercel`, `doppler`, `eas`, no database writes, no package publishes.
- Never kill a process you did not start, and never by pattern (`pkill`, `killall`). No global installs, no changes to system files or to git config.
- Run output, logs, reports and scratch files go to the folder the task names for them, never into the repo.

## Git: you may commit and push the task's branch
- Commit only on the branch the task names. If the checkout is on another branch, stop and report; do not switch branches. Never commit on or push to `main` or the repo's default branch. If the task says "no commits", make none.
- Stage explicit paths only (never `git add -A`, `git add .` or `-u`). Read `git status --short` before each commit and commit only files in the task's scope. Never commit `.env*`, secrets, `.local/`, `.worktrees/`, logs, build output, or work records (plans, reports, handoffs).
- Commit messages follow the repo's existing style. The author is the configured git identity. No co-author line and no mention of an AI, a model or a tool, anywhere.
- Push only with `git push origin <that branch>` (`-u` the first time). Never force push, never delete or rename a branch or a tag, local or remote, never rewrite pushed history (rebase, amend, reset).
- Never run `git stash`, `git clean`, `git reset --hard` or `git checkout -- <path>` on changes you did not make in this run. Changes you find in the checkout that are not yours stay as they are: report them.
- Merge or rebase only when the task orders it by name. Never merge into `main`, never land, no tags, no releases.

## GitHub (`gh`)
- Reading inside this repo is free: `gh pr view|list|diff|checks`, `gh run list|view|watch`, `gh run view --log-failed`, `gh issue view|list`, `gh api` with GET.
- Anything other people see (opening a pull request, a comment, an issue, a review, re-running or starting a workflow) only when the task orders it by name.
- Never: `gh pr merge`, `gh repo` with a write effect, `gh secret`, `gh variable`, `gh release`, `gh auth`, `gh api` with a write method.

If a rule blocks a step, skip that step, write the exact command you would have run into your report, and carry on with the rest.
