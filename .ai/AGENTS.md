# 三个 AI 的分工与铁律 AGENTS

> 每个 AI 开工前 `get_agents_guide()` 读这份。这是规矩，不是建议。

## 🚧 工作副本隔离（2026-06-21 起，最重要，先读）

三个 AI 现在**各有一个物理隔离的工作副本（git worktree）**，不再挤在同一个文件夹里。
进来第一件事：确认你的 shell 在**自己的副本目录**里，不是别人的。

| 你是谁 | 你的工作副本（`cd` 到这里干活） | 停靠分支 |
|---|---|---|
| **Claude** | `/Users/amos/Documents/GitHub/mac-layoutD`（主仓库 = 集成区） | `dev` / `main` |
| **Codex** | `/Users/amos/Documents/GitHub/mac-layoutD-codex` | `codex-lane` |
| **Antigravity** | `/Users/amos/Documents/GitHub/mac-layoutD-ag` | `ag-lane` |

- 三个副本**共享同一个 `.git`**（不是各 clone 一份）：谁提交了什么，别人本地都能直接看到，**无需互相 push**。
- 每个副本各占一个分支，谁在自己副本里 `checkout` 都**不会**影响别人——这就是隔离的目的，别再担心"HEAD 被切走"。
- **铁律：只在自己的副本目录里跑 git。** 别 `cd` 到别人的副本，更别 `cd` 到主仓库去 commit。relay 的 `RELAY_PROJECT_ROOT` 已分别锁到各自副本，`run_checks()` / `git_status()` 都在你自己的副本上跑。
- **开工先同步**：在自己的停靠分支上 `git fetch && git merge origin/dev`（或 rebase）拿到最新的 dev（含最新交接日志与代码），再 `git checkout -b feature/<你>-<任务>` 开新分支干活。

### ⚠️ 并发盲区：隔离是「按 AI」，不是「按对话」（2026-06-21 补，吃过亏）

worktree 隔离只防住**三个不同 AI** 互撞，**没防**「同一个 AI 同时开两个对话、都在同一个工作副本里干活」。
典型事故：两个 Claude 对话同时用主仓库 `mac-layoutD`，一个在合 E3-4 到 dev、另一个在做审核 → 同副本同分支、HEAD 被对方切走、`git add -A` 误吞对方未提交改动、`worktree add` 失败后命令误落主仓库。补两条铁律堵死：

- **N1｜同一仓库不开两个同 AI 对话。** 若必须并发（如一个对话集成、另一个审查），**第二个对话必须带自己独立的 worktree**，不许两个对话共用同一个工作副本 checkout。
- **N2｜集成/审核/试合一律在「专用临时 worktree」里做，绝不在共享主仓库 checkout 上直接动手。** 配方：
  ```bash
  git worktree add --detach /tmp/<任务>-wt dev   # 从 dev 起一份独立副本
  test -d /tmp/<任务>-wt || exit 1               # 必校验创建成功，失败别让命令落回主仓库
  cd /tmp/<任务>-wt && ...试合/build/导图...
  git worktree remove --force /tmp/<任务>-wt      # 收尾删除
  ```
  这一条同时根除「两对话撞车」与「命令误落主仓库」两类事故。
- **N3｜动手集成前先探并发。** `get_current_status()` + `git_status()` 看一眼：dev 上若有别人未提交改动或 HEAD 不在预期处，停手问清楚。开始长集成前在 relay 里 `record_decision()` 占位（"我正在集成 dev，勿动"）当软锁。

## 铁律（违反即视为出错）

1. **干活只在自己的副本里。** 见上方「工作副本隔离」。Codex 在 `…-codex`、Antigravity 在 `…-ag`、Claude 在主仓库。
2. **git 自己走，但只提交到自己的 feature 分支，不合 dev/main。** 每个 AI 用自己的 shell 完成
   建分支 / `add` / `commit`（在 `run_checks` 通过后自动提交，不必停下等确认）。
   **`dev` 和 `main` 的合并由 Claude 统一做**（审核 → 合 dev → 用户视觉验收 → 合 main）。
   Codex/Antigravity **不再 `merge` 到 dev/main，也不必 push**（共享 `.git`，Claude 本地就能看到你的分支）。
   **唯一例外**：改写远端历史或难撤回的操作（`push --force`、删远端分支、对已推送内容 `rebase`/`reset --hard`）先说明再做。
   注意：relay MCP 本身仍是 git 只读（`git_status` / `git_diff_summary` 只读），提交用各客户端自己的终端做，不经过 relay。
3. **连续作业，不停下问确认。** 用户已预先授权整条 `.ai/QUEUE.md`。被唤起后连做本道「本批连续序列」里的多个任务、连续约 1 小时，做完一个自审（`scripts/review-idml.sh` PASS）就直接接下一个，**不要每做完一个就停下等用户点 Proceed / 回话**。Antigravity 的 IDE 若弹"计划审批"，本队列即审批，直接开干。一轮收尾写**一条**汇总 handoff。
4. **开工先读，收工必写。** 进来第一件事 `read_latest_handoff()`；
   离开前最后一件事 `write_handoff()`，并在 summary/checks 里写明已提交的 commit。
   不写交接 = 没干完。
5. **分支隔离。** 在自己按约定新建的 feature 分支上工作，不在别人的分支上乱提交。
   命名约定：`feature/codex-*`（Codex）/ `feature/ag-*`（Antigravity）。停靠分支 `codex-lane`/`ag-lane` 是各自副本的"家"，每个新任务从最新 dev 起新分支。
6. **不碰禁改文件。** 见 PROJECT_CONTEXT.md 的"绝对不要碰"清单。
   要动架构级的东西，先 `record_decision()` 说明理由。
7. **检查走白名单。** 用 `run_checks()`，不要自己拼 shell 命令跑测试。

## 分工

### Claude（架构 / 分析 / 审查 / 集成）——工作副本：主仓库 `mac-layoutD`
- 需求拆解、架构判断、复杂 bug 定位、代码审查
- 把大任务拆成给 Codex/Antigravity 的明确指令，维护 `.ai/QUEUE.md`
- **唯一的集成者**：审核两道的 feature 分支 → 合进 `dev` → 交用户视觉验收 → 合 `main` 并 push
- 集中处理 `.ai/HANDOFF.md` 等交接日志的合并冲突（两道不再碰这种冲突）
- 收尾时做总结和下一步规划

### Codex（落地 / 改码 / 测试）——道一：IDML 导出管线 + 内容模型 · 工作副本：`mac-layoutD-codex`
- 负责文件：`Sources/LayoutDImport/*`、`Sources/LayoutDCore/BookProject.swift`（模型新增字段）、
  `Sources/LayoutDExport/IDMLExporter.swift`、`ZIPArchiveWriter.swift`
- 任务来源：`.ai/QUEUE.md` 的「Codex 道队列」，自助领取，按序做
- 实际写代码、重构、修 lint/type error；端到端验收（不能只靠单测）
- 跑 `run_checks()` + `scripts/review-idml.sh`，结果写进 handoff 的 checks 字段
- 改完用 `git_diff_summary()` 自查改动范围
- **提交到自己的 `feature/codex-*` 分支即可，不合 dev、不必 push**；交给 Claude 集成

### Antigravity（落地 / 改码）——道二：预览渲染 + GUI · 工作副本：`mac-layoutD-ag`
- 负责文件：`Sources/LayoutDEngine/LayoutEngine.swift`、`Sources/LayoutDExport/PDFExporter.swift`、
  `PNGExporter.swift`、`Sources/LayoutDApp/*`（CanvasView/AppState/ToolbarView 等）
- 任务来源：`.ai/QUEUE.md` 的「Antigravity 道队列」，自助领取，按序做
- 实际写代码：预览渲染按模型字段（如 `inlineRuns`）切样式、GUI 交互、批注层等
- 与 Gemini/Google 生态相关的任务
- 同样跑 `run_checks()`，结果写进 handoff
- **提交到自己的 `feature/ag-*` 分支即可，不合 dev、不必 push**；交给 Claude 集成
- **InDesign 视觉终验现由用户做**（人工打开导出的 IDML/PDF 看效果）；Antigravity 不再是"被动验收者"，
  而是和 Codex 对等的编码道——两道按文件边界分工，互不踩同一文件，可以并行开工。

## 一轮标准流程（Codex / Antigravity）
```
# 0. 确认在自己的副本目录（Codex=…-codex / AG=…-ag），不是主仓库
read_latest_handoff()              # 我接的是什么
get_current_status()               # 我自己副本现在什么状态
git fetch && git merge origin/dev  # 在停靠分支上同步最新 dev（拿到最新交接+代码）
git checkout -b feature/<我>-<任务> # 为本任务起新分支
... 干活（只在自己副本里）...
run_checks() + scripts/review-idml.sh   # 自查（pass 才提交）
git_diff_summary()                 # 确认改动范围
git add / commit                   # 自己的 shell；提交到自己的 feature 分支，不合 dev、不必 push
write_handoff(...)                 # 注明 commit，交给 Claude 集成
```

## 集成流程（仅 Claude）
```
# 在主仓库 mac-layoutD
git log feature/codex-xxx          # 共享 .git，直接看得到两道的分支与提交
scripts/review-idml.sh             # 逐分支跑探针，全绿才合
git merge feature/codex-xxx        # 合进 dev（HANDOFF.md 等冲突在此集中解决）
... 攒一批 → 交用户 InDesign 视觉验收 ...
git checkout main && git merge dev && git push   # 验收 OK 才合 main
```
