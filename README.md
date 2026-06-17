# multi-subflow

Two primitives for orchestrating **Claude Code subagents** — built so that waiting costs **0 tokens** and needs **no hooks**:

1. **Fork agents that inherit context.** A "mother" agent reads a code range **once**; forked children inherit its read context, so no child re-reads what's already been read (cache-hit + zero re-read).
2. **File-lock IPC.** The orchestrator and subagents coordinate through lock files under `.multi-subflow/` instead of the conversation layer. The waiting side blocks in a `bash` poll → the model doesn't generate → **0 tokens while suspended**.

> Subagents have no `SendMessage`, and the conversation layer costs tokens on every hop. The file lock sidesteps both — and works **across agent levels** (it's just the shared filesystem, independent of the spawn tree).

---

## Why

Native subagent coordination has two gaps this fixes:

- **A subagent can't message the orchestrator back cheaply** — `SendMessage` isn't available to plain subagents, and routing through the model burns tokens per hop. → The file lock lets any agent report/await with **0 tokens** while blocked.
- **A fresh subagent re-reads the code** another agent already read. → The mother-fork lets children **inherit** that read context.

It buys **control + token-free coordination**, not raw speed (see *Caveats*).

## Install

**Marketplace**
```
/plugin marketplace add Robinfxa/multi-subflow
/plugin install multi-subflow@multi-subflow
```

**Manual** — copy `agents/` and `skills/` into your project's `.claude/`, and merge this repo's `CLAUDE.md` into your project's `CLAUDE.md` so the orchestrator knows the protocol. Add `.multi-subflow/` to `.gitignore`.

## What's inside

| Path | What |
|---|---|
| `skills/multi-subflow/SKILL.md` | The file-lock IPC usage guide (`/multi-subflow`) |
| `skills/multi-subflow/ipc/*.sh` | The 6 handshake scripts (suspend / approve / multiplex / terminal-guard) |
| `skills/multi-subflow/smoke.sh` | One-command end-to-end self-test of the whole protocol |
| `skills/multi-subflow/lint.sh` | Bidirectional compliance checker (catches either side breaking protocol) |
| `skills/multi-subflow/add-role/` | Scaffold a new role — `fork-child` (inherits mother context) or `parallel` worker (`/add-role`) |
| `agents/code-reader.md` | The **mother-fork** agent: read once → fork context-inheriting children |
| `agents/arc-imp.md` | The **suspend-then-switch** agent: design → pause for approval → implement in place |
| `CLAUDE.md` | Orchestrator notes to merge into your project's `CLAUDE.md` |

## How the file-lock handshake works

```
orchestrator                          subagent
     │  spawn subagent ───────────────▶ works…
     │  arm await_events.sh                │  writes review_request_<slug>.json
     │   (run_in_background) + yield turn  │  blocks in await_director_review.sh  ← 0 token
     │ ◀── watcher exits on the event ─────┘
     │  review on disk → approve_fork.sh <slug>  (writes the key)
     │                                     ┌─ poll sees the key on stdout
     │ ◀── task_completed_<slug>.json ─────┤  becomes implementer, writes code
                                           └─ emits {status, tier1_rc}
```

| Script | Side | Role |
|---|---|---|
| `await_director_review.sh <slug>` | subagent | write request, **foreground**-block for the key (0 token); self-writes `task_failed` on timeout/reject |
| `approve_fork.sh <slug> [instr]` | orchestrator | write the `[STATUS: APPROVED]` key |
| `await_events.sh` | orchestrator | 🔴 **run in background + yield the turn**; multiplexer that wakes on any `review_request` / `task_completed` / `task_failed` |
| `await_terminal.sh <slug> <max>` | orchestrator | wait for one slug's terminal signal with a deadline → `exit 42` = worker presumed dead |
| `await_director_commands.sh` / `command_code_reader.sh` | mother / orchestrator | mother waits for FORK / SYNC / EXIT commands |

**Two rules that make it reliable:**
- 🔴 **The orchestrator never foreground-blocks** — it arms `await_events.sh` via `run_in_background` and yields the turn; the watcher's exit re-invokes it. (Foreground-blocking freezes it: it can neither write the key nor receive events.)
- **Completion carries status, never a bare `done`** — `{"status":"ok|failed","tier1_rc":N}`. The orchestrator trusts the `status` field, not the file's existence. `lint.sh` flags a bare `done`.

## Self-test & compliance

```bash
bash skills/multi-subflow/smoke.sh                 # → "9 passed / GATE: PASS"
bash skills/multi-subflow/lint.sh director|subagent  # catch the other side breaking protocol
```

## Adapt to your project

The agents and the protocol are **domain-free**. To wire it in, merge this repo's `CLAUDE.md` into your project's `CLAUDE.md`, then use `/add-role` for project-specific workers. `arc-imp` says "write a spec / run your tests" generically — your `CLAUDE.md` supplies the project specifics.

## Caveats (honest)

- **`fork` / role-switch use Claude Code's agent-teams features.** The file-lock handshake itself is plain Bash + stdout (no hooks), but in-place role-switch and context-inheriting forks rely on those.
- **Long subagent foreground blocks are unverified at scale.** A subagent blocking in `await_director_review.sh` is proven for tens of seconds; multi-minute blocks haven't been stress-tested — keep long full-suite runs on the orchestrator.
- **This is governance, not a speedup.** It enforces "no approval → no code", surfaces every failure, and coordinates token-free; it does *not* make the work finish faster. Reach for it when you want control over an autonomous run.
- **Internal docs are currently in Chinese** (the agent contracts and SKILL files). PRs to localize welcome.

## License

MIT © Robinfxa
