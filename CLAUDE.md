# multi-subflow — orchestrator notes (drop into your CLAUDE.md)

> 把本段并入你项目的 `CLAUDE.md`,让 orchestrator(主会话)和子代都懂这套约定。完整协议见 `/multi-subflow` skill。

## 跨 agent 通信:文件锁,不用 SendMessage
子代与 orchestrator 之间用 `.multi-subflow/` 下的锁文件通信,不走对话层(子代没有 SendMessage,且对话层耗 token)。等待方阻塞在 Bash 轮询里,**模型不生成 = 0 token**。

- **orchestrator 侧**:用 `await_events.sh` 作多路复用总机。🔴 **必须 `run_in_background: true` 启动并随即让出 turn**——前台阻塞会冻死自己(既写不了钥匙也收不到事件);watcher 捞到 `review_request` / `task_completed` / `task_failed` 即退出 → re-invoke orchestrator。
- **子代侧**:相对 orchestrator 是后台并发,`await_director_review.sh` 直接**前台**阻塞即可(只占自己的 turn)。
- **唤醒**:`approve_fork.sh` 写钥匙(`[STATUS: APPROVED]` + 指令),子代阻塞脚本 `cat` 到 stdout 即变身。无需 Hook。

## 两个角色(在 `agents/`)
- **`arc-imp`**:同一 agent 暂停等审批 → 原地切 Implementer 写码(带活上下文)。
- **`code-reader`**:母体读一次 → `fork` 子代继承上下文(零重读)→ 子代经文件锁握手干活。

## 纪律
- **完工带状态、非裸 done**:`echo '{"slug":"<slug>","status":"ok|failed","tier1_rc":N}' > .multi-subflow/task_completed_<slug>.json`;orchestrator 信 `status` 字段、不信文件存在。
- **双向失败**:子代未拿 `APPROVED` 不写码、超时/拒绝自写 `task_failed_<slug>.json`;orchestrator 侧 `await_terminal.sh <slug> <deadline>` deadline 内无终止信号 = 判子代 presumed-dead,不无限挂起。
- **窄活用 fresh subagent 不 fork**:`fork` 继承全上下文会漂移 + 贵;`fork` 只为"复用母体已读上下文"(code-reader)留。
- `.multi-subflow/` 是运行时锁目录,加进 `.gitignore`。
