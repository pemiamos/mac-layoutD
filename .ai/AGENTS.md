# 三个 AI 的分工与铁律 AGENTS

> 每个 AI 开工前 `get_agents_guide()` 读这份。这是规矩，不是建议。

## 铁律（违反即视为出错）

1. **git 自己走，自动不打断。** 每个 AI 用自己的 shell 完成 git 全套
   （建分支 / `add` / `commit` / `push` / `merge`），在 `run_checks` 通过后自动提交，
   不必停下来等人确认。**唯一例外**：改写远端历史或难撤回的操作
   （`push --force`、删远端分支、对已推送内容 `rebase` / `reset --hard`）先说明再做。
   注意：relay MCP 本身仍是 git 只读（`git_status` / `git_diff_summary` 只读），
   提交是用各客户端自己的终端做的，不经过 relay。
2. **开工先读，收工必写。** 进来第一件事 `read_latest_handoff()`；
   离开前最后一件事 `write_handoff()`，并在 summary/checks 里写明已提交的 commit。
   不写交接 = 没干完。
3. **分支隔离。** 在人指定的分支、或自己按约定新建的分支上工作，不在别人的分支上乱提交。
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
... 干活（在指定/自建的 feature 分支上）...
run_checks()                   # 自查（pass 才提交）
git_diff_summary()             # 确认改动范围
git add / commit (/ push)      # 自己的 shell，检查通过后自动提交
write_handoff(...)             # 交给下一棒，注明 commit
```
