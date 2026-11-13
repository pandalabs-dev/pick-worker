# pick-worker

A Claude Code skill that chooses the worker for every delegated task: which model does it, and on which subscription. Owner order of 2026-11-13: each task gets a short difficulty score from 1 to 100, then the worker that fits the difficulty, on the side (Claude or Codex) that has used less of its week, so both subscriptions fill at about the same pace.

This repo is the source of the skill. The installed copy lives in `~/.claude/skills/pick-worker/`.

## What it does

The orchestrator loads the skill before each subagent launch (an Agent call, a Workflow `agent()` call, a `codex-operator` task), scores the task in its head and runs one command:

```
~/.claude/skills/pick-worker/scripts/pick-worker 62
codex gpt-6.1-sol effort=xhigh | score 62 hard | claude week 74 %, codex week 12 %: codex is behind
```

| Score | Tier | Codex side | Claude side |
|---|---|---|---|
| 1 to 15 | inline | (none) | the orchestrator does it itself |
| 16 to 35 | easy | `gpt-6-luna` | Opus 5.5 |
| 36 to 60 | standard | `gpt-6.1-terra` | Opus 5.5 |
| 61 to 80 | hard | `gpt-6.1-sol` | Opus 5.5 |
| 81 to 100 | hardest | `gpt-6-astra` | Fable 5.2 while the Fable share is below 80 %, else Opus 5.5 |

- The side with the lower weekly percentage gets the task; a tie goes to Claude.
- `--claude-only "<reason>"` keeps a task on Claude: git writes, secrets and live systems, browser and simulator gates, tasks that need MCP tools.
- Codex is skipped when its usage is unknown (no `codex` binary, no Codex account in Altseat, numbers still older than 30 minutes after one refresh, a login the refresh reports as not usable) or at 95 % of its week or more. Claude at 95 % or more sends the task to Codex.
- Codex effort is always `xhigh`. A Codex pick runs through the agent type `codex-operator` (an Opus supervisor that verifies the result and does the git writes).

The full instructions for the orchestrator are in `SKILL.md`. The rule that orders its use is `~/.claude/rules/delegation.md`, points 2 and 3.

## Requirements

- Altseat on PATH or at `~/.local/bin/altseat`. The script reads `altseat list` and runs `altseat usage refresh` once when the numbers are older than 30 minutes.
- For Codex picks: the `codex` CLI on PATH and a Codex account registered in Altseat (`altseat list` shows a `Codex` section with a weekly number). Without it every pick is a Claude pick, and the output line says why.
- bash 3.2 or later. No other dependencies. The same file runs on macOS and Linux.

## Install

```
./install.sh
```

It runs the tests, then copies `SKILL.md` and `scripts/pick-worker` into `~/.claude/skills/pick-worker/`. On the owner's machines `~/.claude/skills` is synced between the Mac and the box `claudeworker` (Mutagen session `claude-skills`), so one install reaches both; running it on both is harmless.

## Change it

1. Edit `scripts/pick-worker` or `SKILL.md` here, never the installed copy.
2. `bash tests/run-tests.sh`. The cases are in `tests/cases.sh`; they use `--usage` or the stand-in `tests/fake-altseat`, never the real Altseat or Codex. After an intended change of behaviour: `bash tests/cases.sh > tests/expected.tsv`, read the diff.
3. `./install.sh`, commit, push.

When the tiers, the model ids or the limits change, change the table in `SKILL.md`, this README and `~/.claude/rules/delegation.md` point 3 together.

## State and decisions

- 2026-11-13: built on the owner's order, installed on the Mac and on the box `claudeworker` (`~/.claude/skills/pick-worker/`, the same files on both; 42 test cases pass on both). The rules `~/.claude/rules/delegation.md` (points 2, 3, 5, 6, 10) and `~/.claude/agents/codex-operator.md` (point 5) point at it. Sessions on the box use it since that day.
- The ranking (the five score questions, the tier bounds, the model per tier, the 95 % and 80 % limits) is the orchestrator's design; the owner left it open ("rangiranje odredi sam").
- Codex is compared with the ACTIVE Claude account only. On 2026-11-13 three of four Claude accounts stood at 100 % and the active one at 8 %, against Codex at 5 %, so picks were split about evenly. Comparing with the average of all Claude accounts was offered and the owner declined: "pick-worker onda radi good, top onda to je to tako i treba". Do not change this without his word.
- A Codex pick runs through `codex-operator` (an Opus supervisor plus `codex exec`), not through the Codex plugin, whose forwarder does not verify results. So part of the usage of a Codex task still lands on Claude.
- The box needed one setup step: its Codex login was not registered in Altseat, so every pick there was a Claude pick. Fixed with `altseat add personal --provider codex --primary`. A new machine needs the same.
- On the box the Codex sandbox cannot run commands (`bwrap`, see `delegation.md` point 10a); `codex-operator` uses `--sandbox danger-full-access` there by the owner's permission. The skill does not know about this; it only picks.
- Not built: a pick log (which worker got which task), and a check that a Codex pick really ran on Codex.
