---
name: add-role
description: Scaffold a new multi-subflow agent role that plugs into the fork / file-lock patterns — either a fork-child (inherits a code-reader mother's context) or a fresh parallel worker. Generates a contract under .claude/agents/ with the topology + the file-lock suspend/wake/completion handshake baked in. Use when asked to add a teammate / worker / specialized subagent for a multi-layer or parallel run.
---

按需生成一个**多层或并行的 multi-subflow 角色**契约。它自带拓扑声明 + 文件锁握手(挂起→唤醒→带状态完工),你只填「职责」。

Driver:`.claude/skills/multi-subflow/add-role/add-role.sh`。

## 工作流（agent path）

1. **从需求拍两个参数**:
   - `<role-name>`:小写 kebab-case。
   - **拓扑** = 这个角色怎么来的:
     - `fork-child` —— 由 `code-reader` 母体 fork、**继承读码上下文**(复用同一代码范围的多层线)。
     - `parallel` —— orchestrator 直接 spawn 的 **fresh worker**(N 个互不依赖的活并行)。
2. **跑 driver:**
   ```bash
   bash .claude/skills/multi-subflow/add-role/add-role.sh <role-name> <fork-child|parallel> <target-repo-dir>
   ```
   尾行:`GATE: PASS scaffolded agents/<role>.md (kind=<...>)`。
3. **填空**:frontmatter `description`(含用户会键入的动词)+ `## 职责` 节。文件锁契约已生成,不用手写。

## 怎么选拓扑
| 你要的 | 选 | 为什么 |
|---|---|---|
| 多个工作线复用**同一片已读代码** | `fork-child` | 母体读一次,子代继承、零重读(缓存命中) |
| N 个**互不依赖**的活同时跑、各自不需要别人的上下文 | `parallel` | fresh subagent 更省更听话(不漂移) |

## Gotchas
- **名必须 kebab-case**、**拓扑必须 `fork-child|parallel`**——否则 `GATE: FAIL`。
- **不覆盖既有角色**(同名 → `GATE: FAIL ... refusing to overwrite`)。
- `fork-child` 的实际继承要靠母体 `code-reader` 用 `Agent(subagent_type="fork")` 派生;`parallel` 别用 fork(继承全上下文会漂移 + 贵)。
