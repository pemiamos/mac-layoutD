# 任务队列 Task Queue（Codex / Antigravity 自助接力用）

> 目的：让开发更自动化。两边都不必每轮等 Claude 手喂任务——读本文件，领**自己道里**最上面未打勾的任务做。
> Claude 维护本队列与每项的「目标/文件/验收」；攒一批分支后 Claude 批量审核，不再一个一个提交、一个一个审。
> 两道按文件边界分工，正常不会改到同一文件；真出现冲突按下方「认领协议」处理。

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

**Claude（集成）批量做：**
1. 在主仓库里，攒几个 `feature/codex-*` / `feature/ag-*` 分支一起审，不逐个来回（共享 `.git`，无需等对方 push）。
2. 每个分支跑 `scripts/review-idml.sh`：全绿才算过；有 FAIL 把精确 repro 退回交接。
3. 过的合进 `dev` 集成分支（不直接进 main）；`.ai/HANDOFF.md` 等交接日志的合并冲突由 Claude 集中解决。
4. `dev` 攒一批后交用户在 InDesign/GUI 做**视觉验收**（无头验证不了渲染对错，这关必须人看）。
5. 验收 OK → Claude 合 `dev` → `main` 并 push；验收有问题 → 直接在 Claude 这边改。

**认领协议（避免两道撞同一文件）**：两道文件边界天然不重叠（见下方"负责文件"）。如果某任务臨时需要碰对方道的文件，先在本文件该任务下加一行「⚠️ 跨道改 `<文件>`，已知会 <对方>」再动手。

---

## 进行中 / 待集成

- [x] **行内格式 阶段1**（粗体/斜体 → IDML CharacterStyleRange，含 CJK 单分隔符）
  — commit `b26e1ca`→`9e4f269`(CJK 修复)，已合并 `dev`（`b4adf8d`）。
  结构层 `scripts/review-idml.sh` 全绿（mimetype/XML/FontStyle 断言全过）；
  **等用户在桌面打开导出样例做最终 InDesign 视觉确认**（非阻塞，可继续后续任务）。

---

## Codex 道队列（IDML 导出管线 + 内容模型）

> 负责文件：`Sources/LayoutDImport/*`、`Sources/LayoutDCore/BookProject.swift`、
> `Sources/LayoutDExport/IDMLExporter.swift`、`ZIPArchiveWriter.swift`
>
> **🔁 本批连续序列（按顺序连做，做完一个自审 PASS 就接下一个，不停下问）：E3-3 → E3-7 → E3-4 → E3-6**。
> 约 1 小时或做到这批做完/撞阻塞为止，收尾写一条汇总 handoff。注意斜体导出已用 `Skew="12"`、
> 粗体用 `FauxBold="true"`（别用 `FauxItalic` 或 `FontStyle` 字符串，已验证那两个对 CJK 不可见/出粉色替代字形）。

- [x] **E3-1 行内格式补全到所有 block** — Codex @ `feature/codex-inline-blocks`, commit `8201059`
  - 目标：当前只普通正文段落持久化 inlineRuns；扩到标题/列表/引用/callout。先抽一个统一的 `Paragraph` 构造 helper，再让所有 Markdown block 分支走它。
  - 文件：`Sources/LayoutDImport/MarkdownBookImporter.swift`、`Sources/LayoutDCore/BookProject.swift`(如需)。
  - 验收：`printf '## **粗**标题\n\n- 列表*斜*项\n> 引用**强调**\n'` 导出 IDML 后，标题/列表/引用里的强调都出对应 FontStyle；`scripts/review-idml.sh` PASS。

- [~] **E3-3 傍点（Kenten 着重号）** — 认领: Codex @ `feature/codex-e3-3-kenten`
  - 目标：`InlineEmphasis.kenten`（已改名，原 typo `kentem` 已修）落地——定一种 Markdown 语法（如 `==着重==` 或约定）→ 解析成 kenten run → IDML 用 `KentenKind`/着重号属性输出。
  - 文件：`MarkdownBookImporter.swift`（语法解析）、`IDMLExporter.swift`（IDML 属性输出）。
  - 验收：着重段导出 IDML，解包后对应 CharacterStyleRange 含着重号属性；端到端探针断言 + 用户在 InDesign 人工确认显示傍点。

- [ ] **E3-7 脚注 → IDML**
  - 目标：`anchoredFootnoteIds` 映射到 IDML 脚注（Footnote 元素），而非当前的纯文字处理。
  - 文件：`IDMLExporter.swift`。
  - 验收：含脚注的段落导出后，InDesign 识别为脚注（自动编号/页脚排版），不是裸文字。

- [ ] **E3-4 原生表格 Table**
  - 目标：table 组件从「当文字导」升级为 IDML 原生 `<Table>/<Cell>`（行列/边框/底色），可在 InDesign 调列宽。
  - 文件：`IDMLExporter.swift`。
  - 验收：demo 里表格导出后在 InDesign 是真表格、可选列。

- [ ] **E3-6 目录（TOC）动态化**
  - 目标：当前目录是死文字；改为 InDesign 动态 TOC（或至少正确的 TOC 段落样式 + PageReference）。
  - 文件：`MarkdownBookImporter.swift`（标题锚点）、`IDMLExporter.swift`（TOC/PageReference）。
  - 验收：改动正文后目录页码在 InDesign 里能"更新目录"刷新，不是手敲数字。

- [ ] **E3-8 token → CMYK 色板**
  - 目标：颜色当前导 RGB swatch；增可选项由 token 算 CMYK 值发 `Space="CMYK"` 色板，减少 InDesign 人工转色（不自建色彩管线，只发数值）。
  - 文件：`IDMLExporter.swift`。
  - 验收：导出后色板面板里对应色为 CMYK 模式，数值合理（非简单 RGB→CMYK 近似导致明显偏色）。

- [ ] **E3-9 约物挤压 + 基线网格对齐**
  - 目标：Mojikumi 标点间距集 + 段落「对齐基线网格」映射进 IDML，使 InDesign 排版与 layoutD 预览一致。
  - 文件：`IDMLExporter.swift`。
  - 验收：含中文标点的段落导出后，InDesign 里标点挤压效果与 layoutD 预览基本一致；启用基线网格对齐的段落确实贴线。

- [ ] **E2-4 对开跨页（facing spread）**
  - 目标：按 `pageSetup.facingPages` 生成 2 页 spread + 起始页码 Section。
  - 文件：`IDMLExporter.swift`。
  - ⚠️ 风险高（可能打破当前"单页 spread 干净分页"），单独一棒、改完先确认非对开模式没有回归，再重点交用户 InDesign 验收对开效果。

- [ ] **E2-5 固定美术页 → MasterSpread / 非矩形蒙版**
  - 目标：满版图/扉页固定页映射成 MasterSpread；扇面/八角图框用 PathGeometry 蒙版。
  - 文件：`IDMLExporter.swift`。
  - 验收：固定页导出后版心位置/满版图正确；非矩形蒙版图框在 InDesign 里裁切正确。

- [ ] **D-2 DOCX 导入**（阶段 D 遗留）
  - 目标：新增 `DOCXBookImporter.swift`，解析 DOCX → `BookProject` 模型（复用 Markdown 导入已有的段落/样式映射思路）。
  - 文件：新文件 `Sources/LayoutDImport/DOCXBookImporter.swift`（不碰 `MarkdownBookImporter.swift`，避免和上面几项排队冲突）。
  - 验收：一份结构良好的 DOCX 能导入并正确分段、保留基本粗斜体。

---

## Antigravity 道队列（预览渲染 + GUI）

> 负责文件：`Sources/LayoutDEngine/LayoutEngine.swift`、`Sources/LayoutDExport/PDFExporter.swift`、
> `PNGExporter.swift`、`Sources/LayoutDApp/*`
>
> **🔁 本批连续序列（按顺序连做，做完一个自审 PASS 就接下一个，不停下问）：E3-2 → 校对批注层**。
> 约 1 小时或做到这批做完/撞阻塞为止，收尾写一条汇总 handoff。
> ⚠️ **从最新 dev 起新分支 `feature/ag-e3-2`**，**别再用旧分支 `feature/ag-inline-preview`**——
> 它上面那条 `e05a66d`（FauxItalic）已被 dev 的 `Skew` 修复取代，叠在旧分支上会把斜体修复冲掉。

- [ ] **E3-2 行内格式预览渲染**
  - 目标：PDF/PNG/Canvas 三处预览按 `inlineRuns` 切粗/斜（当前预览整段同字重，仅 IDML 已保真）。`LayoutEngine.swift` 的 `addText` 若需精确测量，把 run 透传进 measurement（已按字符类切复合字体，扩成叠加 emphasis）。
  - 文件：`LayoutEngine.swift`、`PDFExporter.swift`、`PNGExporter.swift`、`CanvasView.swift`。
  - 验收：含粗/斜的页 PNG/Canvas 里目标词字重不同（用户视觉验）；单测断言渲染层确实收到 run 并分段绘制。

- [ ] **校对批注层**（阶段 D 遗留，不参与重排的 overlay）
  - 目标：新增批注/校对标记层，叠加在 Canvas 上但不影响实际排版（类似 PDF 注释，不是 frame）。
  - 文件：`AppState.swift`（新状态）、`CanvasView.swift`（叠加渲染）、可能新文件 `AnnotationLayer.swift`。
  - 验收：能在画布上加批注标记、保存随项目持久化、不参与自动重排/不被导出带进 IDML 正文。

- [ ] **导出选项面板跟进**（待 Codex 的 E2-4 / E3-8 任一项落地后联动，非阻塞可先设计）
  - 目标：「导出 IDML…」面板加开关：对开跨页模式、CMYK 色板模式。
  - 文件：`ToolbarView.swift` 或导出选项相关 View。
  - 验收：开关能正确传参到 `IDMLExporter`，关闭时行为与当前一致（向后兼容）。

---

## 基础设施待办（Claude/用户）

- [ ] 真正 CI（GitHub Actions 跑 `scripts/review-idml.sh`），把审核从「人工记得跑」变成 push 即跑。
- [ ] IDML 官方 RNG schema 校验 + golden-file 回归基线，补强 `review-idml.sh`。
- [ ] relay `run_checks("test")` 末行误显「0 tests」，改回显 XCTest 汇总行。
