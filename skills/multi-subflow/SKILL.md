---
name: multi-subflow
description: Use the multi-subflow file-lock IPC to suspend/approve/wake subagents at 0 token cost, with bidirectional failure handling and a compliance linter that reminds the Director or subagent when the other side breaks protocol. Use when running the multi-subflow handshake, driving subagents via .multi-subflow locks, approving/rejecting a fork, detecting a dead worker, or checking that Director/subagent are following the protocol.
---

Drive the **multi-subflow IPC** — agents coordinate via lock files under
`.multi-subflow/` instead of SendMessage (which subagents lack and which burns
tokens). The waiting side blocks in a `bash` poll → the model doesn't generate →
**0 tokens** while suspended. Scripts live at `.claude/skills/multi-subflow/ipc/`.
Self-test driver: `.claude/skills/multi-subflow/smoke.sh`.
Compliance linter: `.claude/skills/multi-subflow/lint.sh`.

All paths below are relative to the repo root, and **all IPC scripts use
`./.multi-subflow` in the current dir — run them from the repo root** so every
role shares one lock dir.

## Prerequisites

None beyond `bash`. Verified on macOS `bash 3.2`; `lint.sh` auto-falls-back
between BSD `stat -f %m` and GNU `stat -c %Y`.

## Verify the protocol (agent path — run this first)

One command exercises the full handshake + both failure directions + the linter,
driving the real `ipc/*.sh` (both roles simulated by background shells):

```bash
bash .claude/skills/multi-subflow/smoke.sh
```

Expected tail (verified this container): `RESULT: 9 passed, 0 failed` / `GATE: PASS`.

## The trigger order (who does what)

| step | who | action |
|---|---|---|
| arm | Director | launch `await_events.sh` via **`run_in_background`**, then **YIELD the turn** |
| suspend | subagent | write spec → **foreground** `await_director_review.sh <slug>` (blocks, 0 token) |
| wake-Director | Director | watcher exits on `review_request` → re-invoked → review spec on disk |
| key | Director | `approve_fork.sh <slug>` (writes the APPROVED key) → re-arm watcher → yield |
| flip | subagent | poll returns the key on stdout → become implementer → write `task_completed` |

🔴 **Director never foreground-blocks** (it would freeze itself — it can neither
write the key nor be re-invoked). **Subagents are fresh `general-purpose`, NOT
forks** (forks inherit the whole context, drift, and cost ~3×).

## Run: Director

```bash
# 1. arm the multiplexer in the BACKGROUND, then END YOUR TURN (do not foreground it)
#    (Bash tool, run_in_background: true)
bash .claude/skills/multi-subflow/ipc/await_events.sh

# 2. when re-invoked with a review_request: approve (or reject) the slug
bash .claude/skills/multi-subflow/ipc/approve_fork.sh <slug> "optional extra instructions"
#    to REJECT instead, write a response that contains REJECTED:
echo "[STATUS: REJECTED] <why>" > .multi-subflow/review_response_<slug>.json

# 3. guard one worker for a terminal signal with a DEADLINE (run_in_background, then yield)
bash .claude/skills/multi-subflow/ipc/await_terminal.sh <slug> 1800
#    exit 0 = completed/failed (read status); exit 42 = worker presumed DEAD → handle it

# 4. before trusting any worker, lint subagent compliance
bash .claude/skills/multi-subflow/lint.sh director
```

**Trust the `status` field, not file presence** — a tier-1-red worker also writes
`task_completed` (`"status":"failed"`).

## Run: subagent

```bash
# after writing the spec — FOREGROUND, blocks until the Director answers (0 token)
bash .claude/skills/multi-subflow/ipc/await_director_review.sh <slug>
```

The script returns the key on stdout and self-handles failure:

| script result | meaning | what you do |
|---|---|---|
| key contains `[STATUS: APPROVED]` | approved | become implementer, write code |
| `[REJECTED]` / `[BADKEY]` / `[FAILED-NOKEY]` | not approved (it already wrote `task_failed_<slug>.json`) | **write ZERO production code**, end your turn |

On success, end by writing a **status-carrying** terminal signal:

```bash
echo '{"slug":"<slug>","status":"ok","tier1_rc":0}' > .multi-subflow/task_completed_<slug>.json
# tier-1 red? report honestly:
echo '{"slug":"<slug>","status":"failed","reason":"tier1_red","tier1_rc":1}' > .multi-subflow/task_completed_<slug>.json
```

Before giving up on an `approval_timeout`, lint the Director and fold the reminder
into your failure so the Director sees it:

```bash
bash .claude/skills/multi-subflow/lint.sh subagent
```

## Bidirectional compliance reminders (`lint.sh`)

Each role runs the linter to catch the **other** side breaking protocol and emit
a `→ REMIND …` line to surface. Verified output:

```bash
# DIRECTOR view — catches subagents (and itself):
$ LINT_THRESH=0 bash .claude/skills/multi-subflow/lint.sh director
⚠️  'plan-x' wrote a NAKED completion (no status field).
    → REMIND SUBAGENT: 完工必须带 {"status":"ok|failed","tier1_rc":N}；裸 'done' 不被当作通过。
⚠️  'plan-y' has been waiting 0s for your key.
    → REMIND DIRECTOR(自己): approve_fork 放行或写 REJECTED 回应；别让子代空等到超时。

# SUBAGENT view — catches the Director:
$ LINT_THRESH=0 bash .claude/skills/multi-subflow/lint.sh subagent
⚠️  Director has NOT answered 'plan-y' for 0s (no review_response).
    → REMIND DIRECTOR: 用 run_in_background 挂 await_events 并【让出 turn】…
```

`LINT_THRESH` (seconds, default 30) = how long a pending item may sit before it
counts as a violation. Exit 0 = clean, 1 = issues. The subagent's strongest
reminder channel is the `reason` field of its own `task_failed_<slug>.json` —
the Director reads it when the failure wakes the总机.

## Gotchas

- **Director foreground-blocking = deadlock.** Foreground `await_events.sh`
  freezes the Director: the event (a subagent writing `review_request`) can't
  re-invoke it, and it can't write the key. Always `run_in_background` + yield.
- **Fork drifts, fresh obeys.** A forked worker inherits the full context and
  improvises (measured: 3/4 ignored a one-line instruction, ~100k tokens each).
  A fresh `general-purpose` worker obeyed in 1 tool call, ~1/3 the tokens.
- **Same agent across suspend→wake.** The subagent foreground-blocks in ONE turn,
  so it keeps its spec memory through the wake — that's why role-flip works. "Fresh
  each time" means per-spawn, NOT a reset mid-suspend.
- **`task_completed` exists ≠ success.** Read `status`; a red tier-1 also writes it.
- **All scripts are cwd-relative** (`./.multi-subflow`). Run every role from the
  repo root or the lock dirs won't line up.

## Troubleshooting

- **`smoke.sh` hangs > 60s**: a background sim didn't get its key — check the temp
  `workdir` printed at the top; usually a path typo to `ipc/`.
- **`await_terminal.sh` returns 42 immediately**: deadline too small; pass a larger
  `<max>` (seconds).
- **`lint.sh` flags nothing on a known-stale dir**: `LINT_THRESH` default is 30s —
  pass `LINT_THRESH=0` to flag immediately (as in tests).
