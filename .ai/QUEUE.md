# 任务队列 Task Queue（Codex / Antigravity 自助接力用）

> 目的：让开发更自动化。两边都不必每轮等 Claude 手喂任务——读本文件，领**自己道里**最上面未打勾的任务做。
> Claude 维护本队列与每项的「目标/文件/验收」；攒一批分支后 Claude 批量审核，不再一个一个提交、一个一个审。
> 两道按文件边界分工，正常不会改到同一文件；真出现冲突按下方「认领协议」处理。
> **已完成任务见 `.ai/QUEUE-ARCHIVE.md`**（2026-07-04 起归档，保持本文件只含活任务）。

## 工作副本隔离（2026-06-21 起）

三个 AI 各有物理隔离的工作副本（git worktree，共享同一个 `.git`）：
**Codex → `/Users/amos/Documents/GitHub/mac-layoutD-codex`（停靠 `codex-lane`）**；
**Antigravity → `/Users/amos/Documents/GitHub/mac-layoutD-ag`（停靠 `ag-lane`）**；
**Claude → 主仓库 `mac-layoutD`（集成区，`dev`/`main`）**。
开工先确认 shell 在自己的副本里。详见 `.ai/AGENTS.md` 顶部「工作副本隔离」。

## 🔁 连续作业模式（用户 2026-06-21 明确要求，最高优先）

**用户已预先授权整条队列，连续干，不要停下来问确认。**
- 一次被唤起后，**连做多个任务、连续作业约 1 小时**，做完一个**自己审核**（`scripts/review-idml.sh` PASS）就**直接接下一个**，不要每做完一个就停下等用户点"Proceed"/回话确认。
- **Antigravity 注意**：你的 IDE 若弹"计划审批/Proceed"，**本队列就是审批**——视同已批准，直接开干，别等用户点。不要写一份 plan 然后停下问，要边做边交付。
- 自审标准：每个任务 `run_checks()` + `scripts/review-idml.sh` 必须 PASS 才提交；FAIL 就**自己修**，修不动再在 handoff 里记下精确 repro 并跳到下一个能做的任务，**不要因此整体停摆**。
- 一轮结束（约 1 小时 / 做完本批序列 / 撞到真阻塞）时，写**一条汇总 handoff**列出这轮所有 commit，不必每个任务一条。
- **绝不碰 dev/main**：你们只在自己的 feature 分支提交，合 dev/main 是 Claude 的事。也**不要声称自己合并了 main**（之前出现过误报）。

## 流程铁律（每一棒都照做）

**Codex / Antigravity（执行）每领一个任务：**
1. 确认在**自己的副本目录**里（Codex=`…-codex` / AG=`…-ag`）。`read_latest_handoff()` + 读本文件，领**自己道**里最上面未打勾任务。
2. 把该行 `- [ ]` 改成 `- [~] 认领: <你的名字> @ <分支名>`（挂牌，避免撞车），随手改一起带上。
3. 在停靠分支上 `git fetch && git merge origin/dev` 同步最新 dev，再起 `feature/codex-<task>` 或 `feature/ag-<task>` 分支。
   **每个新任务都从最新 dev 起新分支**，别在旧分支上叠（旧分支可能含已被取代的提交）。
4. 实现 + 写**端到端验收**（不能只靠单测——本项目踩过「单测全绿但功能坏」的坑）。
5. **必须** `bash scripts/review-idml.sh` 本地 PASS 后才提交（这就是 Claude 审核要跑的同一套）。
6. commit（feat/fix 规范）到**自己的 feature 分支**+ 把该行改成 `- [x]`（注明 commit hash）。
   **不合 dev、不必 push**——共享 `.git`，Claude 本地直接看得到你的分支。
7. **直接接下一个任务**（见「连续作业模式」），不要停下问确认；一轮收尾写一条汇总 `write_handoff`。
8. **别提交生成产物**：`Samples/output-*`、导出的 PDF/PNG 样张等**不进仓库**（验收样张投 `~/Desktop`）。

**Claude（集成）批量做：**
1. 在主仓库里，攒几个 `feature/codex-*` / `feature/ag-*` 分支一起审，不逐个来回（共享 `.git`，无需等对方 push）。
2. 每个分支跑 `scripts/review-idml.sh`：全绿才算过；有 FAIL 把精确 repro 退回交接。
3. 过的合进 `dev` 集成分支（不直接进 main）；`.ai/HANDOFF.md` 等交接日志的合并冲突由 Claude 集中解决。
4. `dev` 攒一批后交用户在 InDesign/GUI 做**视觉验收**（无头验证不了渲染对错，这关必须人看）。
5. 验收 OK → Claude 合 `dev` → `main` 并 push；验收有问题 → 直接在 Claude 这边改。

**认领协议（避免两道撞同一文件）**：两道文件边界天然不重叠（见下方"负责文件"）。如果某任务临时需要碰对方道的文件，先在本文件该任务下加一行「⚠️ 跨道改 `<文件>`，已知会 <对方>」再动手。

---

## 待用户视觉验收（阻塞合 main）

- **InDesign 式工作区骨架（第一步）** — dev（含 `72590f8`）。
  验：① 顶部控制面板（选中帧显示 X/Y/宽/高可编辑、未选中显示文档概要）；② 底部状态栏（页码跳转、预检状态灯、缩放百分比/适合页宽）；③ 右侧「面板/检查器」单列分段切换、画布更宽；④ 整窗深色、画布台面深灰、页面纸张白；⑤ 窗口工具条精简为图标模式。
- **左侧工具栏：文本框/图像框工具 + 单键快捷键** — dev=`facadbf`（2026-07-04 用户审核提案通过后 Claude 实现）。
  验：① 选「文本框工具」在页面拖矩形 → 出现空文本框（自动选中，检查器可填字）；② 选「图像框工具」拖矩形 → 出现图像框（引用某图，检查器「更换图片」可换；无图时弹窗提示）；③ 单键快捷键（画布点一下获焦后）V/A/T/F/U/H/Z/⇧P 切工具；④ 工具栏分组顺序像 InDesign。
  App 已用新构建启动（demo.md）。验收 OK → 合 main；要调 → 反馈 Claude 迭代。
- ~~基础工具热修（GUI）~~ — 用户 2026-07-04 反馈：GUI 整体按 InDesign 布局重做（见上），热修已随批合 main(`6b12271`)。
- [x] **B1 图文绕排** — ✅ 用户 2026-07-04 视觉验收通过，已合 main(`6b12271`)。
- [x] **行内格式阶段1 InDesign 终验** — ✅ 用户 2026-07-04 确认 OK。

---

## Claude 道（性能批 + 高风险导出 + 集成）

> 2026-07-04 全项目 review 立项「性能批」：根因是每次改动全书重排两遍+preflight 同步跑在界面线程（AppState.recalculateLayout），书稿变大会卡。顺序做、每步靠 PERF-1 的基准数字验证。

- [x] **PERF-1 全书规模性能基准** — ✅ Claude `e106c46`，合 dev(`23df697`, 2026-07-04)。合成 161 页书稿基准：**本机基线 ≈1179ms/次全量排版**（断言只拦 60s 性能悬崖，CI 环境差异安全）。后续 PERF-3/4 用这个数字对比。
- [x] **PERF-2 baseline 布局缓存** — ✅ Claude `e106c46`，合 dev(`23df697`, 2026-07-04)。对照版只在内容/样式真变时重排（比较时剔除 appliedLayoutPlans + qualityMetricsHistory）；纯版面方案操作/undo/redo 不再触发第二次全书排版，单次改动成本约减半。加 baselineLayoutCount 测试钩子+缓存单测。
- [ ] **PERF-3 排版异步化 + 防抖** — 等 PERF-1/2 落地后单独一棒（动状态流，须防 GUI 竞态）。
  - 目标：连续操作只排最后一次，layout/preflight 移出界面线程；首帧仍同步保证打开即有版面。
  - 文件：`AppState.swift`、可能 `CanvasView.swift`。
- [ ] **PERF-4 引擎测量改造（CTTypesetter 逐行填充 + 测量缓存）** — 风险最高放最后，靠 PERF-1 验证无回归。
  - 目标：`fittingPrefix` 二分试排（每次重建 framesetter）改为 CTTypesetter 一次性逐行填充取断点；测高结果按 (text,style,width) 缓存。
  - 文件：`Sources/LayoutDEngine/LayoutEngine.swift`、`Sources/LayoutDCore/ChineseTypesetting.swift`。
  - 验收：PERF-1 基准显著下降且全部现有测试/探针 PASS；分页/避头尾/孤寡行为零变化（golden 对比）。
- [ ] **B1-IDML 导出侧图文绕排**（配对 B1）：图片框输出 `TextWrapPreference` 让 InDesign 也绕排。文件：`IDMLExporter.swift`。验收：解包含 TextWrapPreference、InDesign 打开绕排生效（用户肉眼）；`review-idml.sh` PASS。
- [ ] **SPLIT-ENGINE LayoutEngine.swift 拆分**（1600+ 行，纯搬家不改逻辑；放性能批之后避免叠加冲突）。

## Codex 道队列（导入 + 探针）

> 负责文件：`Sources/LayoutDImport/*`、`scripts/review-idml.sh`。
> 斜体导出已用 `Skew="12"`、粗体用 `FauxBold="true"`（别用 `FauxItalic`/`FontStyle`，对 CJK 不可见/出粉色替代字形）。

- [x] **GUARD-1 角色标签端到端探针进 review-idml.sh** — ✅ Codex @ `feature/codex-guard-role-tags`（`bdd1ac2` test: guard role tag idml review probe）
  - 背景：角色标签结构化导入（IMP-3）是 layoutD 核心能力，但 `review-idml.sh` 的端到端探针目前只测行内粗斜体——改导入器时 CI 逮不住角色回归。
  - 目标：探针加一段角色标签 fixture（含 一级标题/开节概述/抽言/参考文献 标签 + 正文），导 IDML 解包断言：① 标签文字零漏出（Story 无「抽言」「开节概述」等标签字面）；② Styles.xml 含中文命名段落样式（章标题/概述/抽言/参考文献）；③ 对应段落 `AppliedParagraphStyle` 指向正确样式。
  - 文件：`scripts/review-idml.sh`（新增探针段，用 printf 造 Markdown fixture 即可，别提交二进制 docx）。
  - 验收：探针在当前 dev PASS；人为把导入器角色识别注释掉时探针 FAIL（自证有效，验完还原）；整脚本仍 PASS。
- [ ] **SPLIT-IMPORT MarkdownBookImporter.swift 拆分**（1500+ 行 → 按职责分文件：行内解析 / 块解析 / frontmatter / 脚注后处理，纯搬家不改逻辑）
  - 文件：`Sources/LayoutDImport/`（新增拆分文件）。
  - 验收：全部测试零修改通过；`review-idml.sh` PASS；无任何行为变化。
- [ ] **E3-9 约物挤压 + 基线网格对齐**
  - 目标：Mojikumi 标点间距集 + 段落「对齐基线网格」映射进 IDML，使 InDesign 排版与 layoutD 预览一致。
  - 文件：`IDMLExporter.swift`（⚠️ 跨道，起手前先在本行挂牌知会 Claude）。
  - 验收：含中文标点的段落导出后，InDesign 里标点挤压效果与 layoutD 预览基本一致；启用基线网格对齐的段落确实贴线。
- [ ] ~~**E3-8 token → CMYK 色板**~~ ⏸ **暂缓（用户 2026-06-21 决定；印前转色交 InDesign，非阻塞）**

## Antigravity 道队列（预览渲染 + GUI）

> 负责文件：`Sources/LayoutDEngine/LayoutEngine.swift`、`PDFExporter.swift`、`PNGExporter.swift`、`Sources/LayoutDApp/*`
> ⚠️ 教训复盘：每个新任务从**最新 dev** 起分支、真把 feat 本体迁过去（别只加 docs commit）；同步 dev 不碰 QUEUE.md（已归 Claude 独占）；**生成样张别提交进仓库**（B1 踩过，Claude 合并时剔除了 20 个 PNG/PDF）。

- [x] **GUARD-2 断言闸字形覆盖检查（rule⑥）** — ✅ AG `b3a2e97`, 合 dev(待)
  - 背景：rule⑤ 已拦「字重不存在→Helvetica 豆腐」；还差「字体存在但缺 CJK 字形→豆腐」（脚注豆腐那类事故的自动网）。
  - 目标：`IDMLInvariants` 加 rule⑥——对每个注册字体用 CoreText 抽查文档实际用到的字符集样本（如每 Story 抽前 N 个 CJK 字符）能否出字形（`CTFontGetGlyphsForCharacters`），缺字形即 FAIL 并报出字体名+字符。
  - 文件：`Sources/LayoutDExport/IDMLInvariants.swift`、`Tests/LayoutDExportTests/IDMLInvariantsTests.swift`（⚠️ 跨道改导出文件——沿用 rule⑤ 先例，已知会 Claude）。
  - 验收：单测含正反例（CJK 字体过、纯拉丁字体配中文 FAIL）；全套测试 + `review-idml.sh` PASS。
- [x] **E2-4p 补完：对开左右页并排预览 + 版心镜像** — ✅ AG `77c595c`, 合 dev(待)
  - 目标：`facingPages` 开启时 Canvas/PDF/PNG 左右页并排、版心镜像（订口内侧）；关闭时与现状一致。
  - 文件：`LayoutEngine.swift`、`CanvasView.swift`、`PDFExporter.swift`、`PNGExporter.swift`。
  - 验收：对开稿导 PNG 左右页镜像正确；非对开零回归；单测断言镜像边距；`review-idml.sh` PASS。
- [ ] **SPLIT-GUI 巨型 GUI 文件拆分**（纯搬家不改逻辑，分三小棒各自成 commit）
  - 目标：`main.swift`(1500 行，拆出 AppDelegate/菜单/WorkspaceViewController/CLI 各自文件)、`InspectorView.swift`(1600 行，按面板 section 拆)、`CanvasView.swift`(1400 行，拆出工具交互/绘制)。
  - 文件：`Sources/LayoutDApp/*`。
  - 验收：全部测试零修改通过；`review-idml.sh` PASS；GUI 行为无变化（拆完 Claude 出包给用户抽查）。

## Backlog（按车道路由）

- [x] **B1 图文绕排预览** — ✅ AG `099f38b`，Claude 审核合 dev（`09b8cc4`，2026-07-04）。详见归档；导出侧配对任务 = Claude 道 B1-IDML。
- ⏹ ~~B2 长表格分页~~ / ~~B3 索引~~ / ~~B4 引文样式~~ — 用户 2026-06-23 决定不做。

## 基础设施待办（Claude/用户）

- [x] **真正 CI** — ✅ `.github/workflows/ci.yml`（2026-06-23 起 push/PR 自动跑 review-idml.sh，macOS runner）。
- [ ] IDML 官方 RNG schema 校验 + golden-file 回归基线，补强 `review-idml.sh`（golden 需先解决 CI 字体环境差异，见 ci.yml 注释）。
- [ ] relay `run_checks("test")` 末行误显「0 tests」，改回显 XCTest 汇总行（改 relay-mcp，仓库在 `~/tools/relay-mcp`）。
