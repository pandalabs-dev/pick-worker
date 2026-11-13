---
name: pick-worker
description: Load before EVERY subagent launch (an Agent tool call, a Workflow agent() call, a codex-operator task) to choose the worker. Scores the task 1 to 100, then a script picks Claude Opus 5.5, Claude Fable 5.2, Codex (gpt-6-luna, gpt-6.1-terra, gpt-6.1-sol, gpt-6-astra) or inline work from that score and the weekly usage of the active Claude account and of Codex, so both subscriptions fill at about the same pace. One pick per task; a batch of near-identical tasks gets one pick.
---

# pick-worker

Owner order of 2026-11-13: every delegated task gets a short difficulty eval, then the worker that fits the difficulty, on the side (Claude or Codex) with more weekly usage left. The ranking below is the orchestrator's design ("rangiranje odredi sam").

Use it before each subagent launch. One pick per task. A batch of near-identical tasks gets one pick for the whole batch.

## Step 1: score the task, 1 to 100

In your head, no extra model call, one line of working. Five questions, 0 to 20 each:

1. Size: how many files and steps.
2. Freedom: how much design or judgment the brief leaves open.
3. Depth: how subtle the reasoning is (concurrency, money, state machines, security).
4. Blast radius: what breaks if the result is wrong.
5. Verification: how hard it is to check the result.

Example line: `score 8+12+14+16+12 = 62`.

## Step 2: run the script

```
~/.claude/skills/pick-worker/scripts/pick-worker <score>
~/.claude/skills/pick-worker/scripts/pick-worker <score> --claude-only "<reason>"
~/.claude/skills/pick-worker/scripts/pick-worker <score> --usage "claude_week=N fable=N codex_week=N"
```

Take its answer. It prints one line: the pick, the score and tier, the reason with the numbers. It reads the live usage from `altseat list` (and runs `altseat usage refresh` once when the numbers are older than 30 minutes). `--usage` replaces that readout; a Workflow script reads the usage once at the start and passes it to each pick.

What the script does:

| Score | Tier | Codex side | Supervisor of a Codex pick | Claude side |
|---|---|---|---|---|
| 1 to 15 | inline | (none) | (none) | do it yourself |
| 16 to 35 | easy | `gpt-6-luna` | main session | Opus 5.5 |
| 36 to 60 | standard | `gpt-6.1-terra` | Sonnet 5.5 | Opus 5.5 |
| 61 to 80 | hard | `gpt-6.1-sol` | Opus 5.5 | Opus 5.5 |
| 81 to 100 | hardest | `gpt-6-astra` | Opus 5.5 | Fable 5.2 while fable is below 80 %, else Opus 5.5 |

Codex effort is always `xhigh`. The side with the lower weekly percentage gets the task; a tie goes to Claude. Overrides, in this order: `--claude-only` gives Claude; Codex usage unknown (no `codex` binary, no Codex section in Altseat, a value shown as `--`, Codex numbers still older than 30 minutes after the refresh, or a Codex login the refresh or the list marks as not usable) gives Claude; Codex week 95 % or more gives Claude; Claude week 95 % or more gives Codex.

## Step 3: launch what it says

- `claude opus`: Agent or `agent()` with `model: "opus"`.
- `claude fable`: Agent or `agent()` with `model: "fable"`.
- `codex <model> effort=xhigh supervisor=main`: no subagent. The orchestrator runs `~/.claude/skills/pick-worker/scripts/codex-run` itself in the background and verifies the result by the contract `~/.claude/agents/codex-operator.md`.
- `codex <model> effort=xhigh supervisor=sonnet` or `supervisor=opus`: agent type `codex-operator` with `model: "sonnet"` or `model: "opus"` (contract `~/.claude/agents/codex-operator.md`). The brief names the Codex model and effort `xhigh`. Where that type is not offered, `general-purpose` with the same model and the order to read the contract first.
- A supervisor that cannot close a point after two fix rounds, or is unsure about a finding, hands the task back, and it continues under an Opus supervisor.
- `inline`: do it yourself, no subagent.

How to run Codex: `codex-run --model <id> --task <file> --out <dir> [--workspace <dir>] [--resume <thread_id>] [--no-git] [--print-cmd]`. It puts the run rules (`scripts/codex-rules.md`) in front of the task, picks the sandbox (a profile that lets Codex commit and push the task's branch; `--no-git` for review and analysis runs without git writes; full access only on the box `claudeworker`), keeps the output in `--out` (never inside a repo) and prints `thread_id=`, `last=`, `events=` and `exit=`. Its exit code is Codex's; 2 means bad arguments, 3 means no sandbox is usable on this host.

Put the pick and its one-line reason into the brief or the ledger, for example `worker: codex gpt-6.1-sol (score 62 hard, claude week 74 %, codex week 12 %)`.

## Always Claude: pass `--claude-only "<reason>"`

Source: `~/.claude/rules/delegation.md` point 6.

- landing on `main`, merges into `main`, branch or tag deletion, history rewrites, releases;
- anything with secrets or live systems: Doppler, Fly, Vercel, databases, deploys, store uploads, ssh to the box;
- browser and simulator gates;
- tasks that need MCP tools.

Commits and pushes of the task's working branch are done by Codex and are no reason for `--claude-only`.

## Log

Every pick is appended as one line (UTC time, a tab, the printed line) to `${XDG_STATE_HOME:-$HOME/.local/state}/pick-worker/picks.log`. `PICK_WORKER_LOG=<path>` moves it, `PICK_WORKER_LOG=off` turns it off. A failed write never changes the pick.

## If Codex fails

When Codex turns out to be unavailable for a picked task (usage limit, auth error, crash), continue the task on Claude (Opus 5.5) and tell the owner.

## Exit codes

0 on a pick, 2 on bad arguments (score outside 1 to 100, unknown option, bad `--usage` value).
