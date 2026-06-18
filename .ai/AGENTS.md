# 三个 AI 的分工与铁律 AGENTS

> 每个 AI 开工前 `get_agents_guide()` 读这份。这是规矩，不是建议。

## 铁律（违反即视为出错）

1. **git 只走 GitHub Desktop。** 任何 AI 都不得执行 git 写操作
   （commit / branch / push / merge / rebase / reset / rm）。
   本 MCP 也只提供 git 只读工具。提交、建分支、合并一律由人在 GitHub Desktop 完成。
2. **开工先读，收工必写。** 进来第一件事 `read_latest_handoff()`；
   离开前最后一件事 `write_handoff()`。不写交接 = 没干完。
3. **分支隔离靠人。** 你只在人指定给你的分支上工作，不主动切换分支。
   命名约定：`feature/claude-*` / `feature/codex-*` / `feature/ag-*`。
4. **不碰禁改文件。** 见 PROJECT_CONTEXT.md 的"绝对不要碰"清单。
   要动架构级的东西，先 `record_decision()` 说明理由。
5. **检查走白名单。** 用 `run_checks()`，不要自己拼 shell 命令跑测试。

## 分工

### Claude（架构 / 分析 / 审查）
- 需求拆解、架构判断、复杂 bug 定位、代码审查
- 把大任务拆成给 Codex 的明确指令，写进 handoff
- 收尾时做总结和下一步规划

### Codex（落地 / 改码 / 测试）
- 实际写代码、重构、修 lint/type error
- 跑 `run_checks()`，把结果写进 handoff 的 checks 字段
- 改完用 `git_diff_summary()` 自查改动范围

### Antigravity（IDE 内多文件 / 前端验证）
- IDE 内跨文件理解、前端交互/视觉验证、局部重构
- 与 Gemini/Google 生态相关的任务
- 验证前一棒的改动在 UI 上是否正常

## 一轮标准流程
```
read_latest_handoff()          # 我接的是什么
get_current_status()           # 现在仓库什么状态
... 干活（只在指定分支，不碰 git 写）...
run_checks()                   # 自查
git_diff_summary()             # 确认改动范围
write_handoff(...)             # 交给下一棒
```
