#!/usr/bin/env bash
# Scaffold a new multi-subflow agent role — one that plugs into the fork /
# file-lock patterns. Pick the role's place in the topology:
#   fork-child : forked off a code-reader mother, inherits its read context
#   parallel   : a fresh standalone worker, one of N run concurrently
# Both get the file-lock handshake (suspend → wake → status-carrying completion).
# Refuses to overwrite.
#
# Usage:  bash add-role.sh <role-name> <fork-child|parallel> [target-repo-dir]
set -euo pipefail
ROLE="${1:?usage: add-role.sh <role-name> <fork-child|parallel> [target-dir]}"
KIND="${2:?usage: add-role.sh <role-name> <fork-child|parallel> [target-dir]}"
TARGET="${3:-$(pwd)}"
case "$ROLE" in *[!a-z0-9-]*) echo "GATE: FAIL role name must be lowercase kebab-case: $ROLE"; exit 1;; esac
case "$KIND" in fork-child|parallel) ;; *) echo "GATE: FAIL kind must be fork-child|parallel"; exit 1;; esac
DEST="$TARGET/.claude/agents"
mkdir -p "$DEST"
F="$DEST/$ROLE.md"
[ -e "$F" ] && { echo "GATE: FAIL agents/$ROLE.md already exists (refusing to overwrite)"; exit 1; }

if [ "$KIND" = fork-child ]; then
  ORIGIN='**fork 子代**：由 `code-reader` 母体 `fork` 派生，**继承母体已读的代码上下文（零重读）**。适合"复用同一代码范围"的多层工作线。'
  SPAWN='由母体 `Agent(subagent_type="fork", …)` 派生；fork prompt 里声明"你是 $ROLE 子代 + 本线职责"。'
else
  ORIGIN='**并行 worker**：orchestrator 直接 spawn 的 **fresh subagent**（不继承上下文，更省更听话）。适合 N 个互不依赖的活同时跑。'
  SPAWN='由 orchestrator 直接 spawn（fresh，无 name），靠文件锁回报，不走 SendMessage。'
fi

cat > "$F" <<EOF
---
name: $ROLE
description: <ONE LINE — what $ROLE does + WHEN to use it; put the verbs an agent would actually type>
model: inherit
color: cyan
---

你是 **$ROLE**。<一句话定位:它在这条多层/并行流水线里补哪个缺口>

## 拓扑
- $ORIGIN
- 派生方式:$SPAWN

## 职责（🔴 FILL ME）
- **做**:<具体产物 / 它负责那一段>
- **不做**（越界即停、报 orchestrator）:<不碰什么>

## multi-subflow 契约（文件锁,完整协议见 \`/multi-subflow\` skill）
- 需审批时**前台**调 \`bash .claude/skills/multi-subflow/ipc/await_director_review.sh <slug>\` 挂起(自身阻塞轮询、0 token)。
- **安全**:Bash 结果里没收到 \`[STATUS: APPROVED]\`(拿到 \`[FAILED-NOKEY]\`/\`[REJECTED]\`/\`[BADKEY]\`,脚本已写好 \`task_failed_<slug>.json\`)→ **一行 production code 都不写**,以该结果结束。
- 完工**必抛带状态信号**(裸 done 会被 \`lint.sh\` 判违规):
  \`echo '{"slug":"<slug>","status":"ok|failed","tier1_rc":N}' > .multi-subflow/task_completed_<slug>.json\`
EOF

echo "GATE: PASS scaffolded agents/$ROLE.md (kind=$KIND)"
echo "NEXT: 填 frontmatter description + 『职责』节;orchestrator 侧用 await_events.sh(run_in_background)收它的信号。"
