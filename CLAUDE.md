# layoutD — 项目规则

## relay 协作（三 AI 接力）

本项目接入了 `relay` MCP（统一工作台，git 全程只读）。每次：

- **开工先读**：先调用 `read_latest_handoff()` 和 `get_current_status()` 了解上一棒做了什么、仓库当前状态。
- **收工必写**：离开前调用 `write_handoff(...)` 交接（做了什么、改了哪些文件、检查结果、下一步）。不写交接 = 没干完。
- **检查走白名单**：用 `run_checks("build")` / `run_checks("test")`，不要自己拼 shell 跑构建。
- 详细分工与铁律见 `.ai/AGENTS.md`，可用 `get_agents_guide()` 读取。

> git 规范见全局 `~/.claude/CLAUDE.md`：AI 可自主完成 git 全套（建分支/commit/push/merge），
> 在 `run_checks` 通过后自动提交、不打断；唯一例外是改写远端历史等难撤回操作需先说明。
> 提交后在 `write_handoff` 里注明 commit。
