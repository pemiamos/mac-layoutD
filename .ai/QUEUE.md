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

## Claude 道（灌版主线 + 高风险导出 + 集成）

> **2026-07-06 定位校准（见 DECISIONS）**：layoutD 交付「初排灌版」给 InDesign，不替代 InDesign。开发价值标准 = 文流/样式/视觉规范/CMYK 高完成度迁移进 InDesign、给人工调整省时间。可编辑性 > 逐像素冻结（InDesign 里漂移可人工调校）。脚注/傍点/表格深化 = 初排细枝末节，不再投入。

- [ ] ~~**BUG-1 跨段落脚注编号全错**~~ ⏸ **不修（用户 2026-07-06 决定）**——脚注使用频率极低，初排里属细枝末节，需要时 InDesign 补做很快；且 THREAD-1 落地后 story 结构整个会变，现在修是白修。根因存档：一框一 Story 零串接 → InDesign 原生脚注按 Story 各自从 1 编号（Markdown/DOCX 两路径均复现，非 IMP-4/SPLIT-GUI 回归）。
- [ ] **THREAD-1a 串接文流 spike（先探路，一小棒）** — 2026-07-06 立项，**灌版定位下的最高优先级**。
  - 背景：现状"一段一 Story、一框一 Story、零串接"（`NextTextFrame`/`PreviousTextFrame` 恒 `"n"`），demo 4 页即 21 story/21 框，300 页书≈1500 个。更根本的是交付物不是「可编辑的文流」——编辑在 InDesign 里插一句话，后文不会自动流动，灌版价值大打折扣。
  - 目标：手工/脚本造一份最小 threaded 样张（一章正文 3-5 页：一个 Story + 每页一个 TextFrame 用 Previous/NextTextFrame 串接，框坐标仍用引擎算好的值），InDesign 打开人工验证三件事：① 文流可编辑（中间插一段字，后文自动流过页界）；② 打开时版面漂移程度可接受（漂移允许存在，人工调校是预期内工作）；③ 样式/复合字体/约物/基线在串接结构下依旧生效。
  - 验收：spike 样张 InDesign 人工验证通过 → 写清结构模板（Story 粒度=章；章名/概述随文流入 Story；抽言/图/图注仍独立框）→ 立 THREAD-1b。不通过 → 记录失败细节，评估旁路（仅同页正文合并 story 等轻量减对象方案）。
- [ ] **THREAD-1b 串接文流全量实现**（THREAD-1a 通过后）：IDMLExporter 正文改按章出 Story、逐页框 Previous/NextTextFrame 串接；LayoutEngine 提供每页正文框的串接分组信息。验收：全书导出 story 数按章计不按段计；`review-idml.sh` 加 GUARD-4 探针（串接链完整、无孤儿框）；InDesign 人工验证灌版可编辑。
- [ ] **MASTER-1 主页交付**（THREAD-1 之后，同文件避免冲突）：版心/栏参考、自动页码（CurrentPageNumber 变量）、页眉书名/章名放 A-主页，正文页应用主页——编辑改页码位置只动主页一处。现状疑似页码按静态文本逐页画，动手前先核实。文件：`IDMLExporter.swift`。验收：InDesign 里主页面板见 A-主页带自动页码，正文页页码随主页变。
- [ ] **SPREAD-1 对页合并 Spread**（THREAD-1 之后）：per-page Spread 改真对页 spread（左右页同 spread、版心镜像），配合 MASTER-1。验收：InDesign 页面面板呈对页排列，与 layoutD 预览一致。
- [x] **PERF-1 全书规模性能基准** — ✅ Claude `e106c46`，合 dev(`23df697`, 2026-07-04)。合成 161 页书稿基准：**本机基线 ≈1179ms/次全量排版**（断言只拦 60s 性能悬崖，CI 环境差异安全）。后续 PERF-3/4 用这个数字对比。
- [x] **PERF-2 baseline 布局缓存** — ✅ Claude `e106c46`，合 dev(`23df697`, 2026-07-04)。对照版只在内容/样式真变时重排（比较时剔除 appliedLayoutPlans + qualityMetricsHistory）；纯版面方案操作/undo/redo 不再触发第二次全书排版，单次改动成本约减半。加 baselineLayoutCount 测试钩子+缓存单测。
- [ ] **B1-IDML 导出侧图文绕排**（次优先，THREAD-1 批之后顺带做——绕排影响文流走向，属灌版相关但可后补）：图片框输出 `TextWrapPreference` 让 InDesign 也绕排。文件：`IDMLExporter.swift`。验收：解包含 TextWrapPreference、InDesign 打开绕排生效（用户肉眼）；`review-idml.sh` PASS。
- [ ] **SPLIT-ENGINE LayoutEngine.swift 拆分** ⏳ **挪到 THREAD-1 批全部落地之后**（THREAD-1b 要大改引擎与导出，拆分与之叠加必然冲突；纯搬家不急）。

## Codex 道队列（导入 + 探针）

> 负责文件：`Sources/LayoutDImport/*`、`scripts/review-idml.sh`。
> 斜体导出已用 `Skew="12"`、粗体用 `FauxBold="true"`（别用 `FauxItalic`/`FontStyle`，对 CJK 不可见/出粉色替代字形）。

- [x] **GUARD-1 角色标签端到端探针进 review-idml.sh** — ✅ Codex @ `feature/codex-guard-role-tags`（`bdd1ac2` test: guard role tag idml review probe）
  - 背景：角色标签结构化导入（IMP-3）是 layoutD 核心能力，但 `review-idml.sh` 的端到端探针目前只测行内粗斜体——改导入器时 CI 逮不住角色回归。
  - 目标：探针加一段角色标签 fixture（含 一级标题/开节概述/抽言/参考文献 标签 + 正文），导 IDML 解包断言：① 标签文字零漏出（Story 无「抽言」「开节概述」等标签字面）；② Styles.xml 含中文命名段落样式（章标题/概述/抽言/参考文献）；③ 对应段落 `AppliedParagraphStyle` 指向正确样式。
  - 文件：`scripts/review-idml.sh`（新增探针段，用 printf 造 Markdown fixture 即可，别提交二进制 docx）。
  - 验收：探针在当前 dev PASS；人为把导入器角色识别注释掉时探针 FAIL（自证有效，验完还原）；整脚本仍 PASS。
- [x] **SPLIT-IMPORT MarkdownBookImporter.swift 拆分** — ✅ Codex @ `feature/codex-split-import`（`4ca0db6` refactor(import): split markdown parser responsibilities），Claude 已合 dev
  - 拆为 `MarkdownParserBlocks/Inline/FrontMatter/Images.swift` 四个 extension 文件，纯搬家不改逻辑，对外 API 不变。
- [x] **E3-9 约物挤压 + 基线网格对齐** — ✅ Codex @ `feature/codex-e3-9-mojikumi-baseline`（`b4dbb3d` feat(export): bind mojikumi and baseline grid in IDML），Claude 已合 dev
  - IDML 补 `MojikumiTable` 声明 + 段落样式绑定 Mojikumi/MojikumiSet + `GridAlignment=AlignAllLinesToGrid` 基线网格绑定。⚠️ 待用户在 InDesign 里肉眼确认标点挤压与基线贴齐效果（视觉属性，探针测不出）。
- [ ] ~~**E3-8 token → CMYK 色板**~~ ⏸ **暂缓（用户 2026-06-21 决定；印前转色交 InDesign，非阻塞）**
- [x] **IMP-4 DOCX 脚注导入** — ✅ Codex @ `feature/codex-docx-import-guards`（`3f84c77` feat(import): cover DOCX footnotes and import guards），Claude 已合 dev
  - 解析 `word/footnotes.xml` + 正文 `w:footnoteReference`，映射为与 Markdown 同构的 `Paragraph(kind: .footnote(number:), styleId: "footnote")` + 正文塞 Unicode 上标 + `anchoredFootnoteIds` 打通 E3-7 原生 Footnote 导出。GUARD-3 探针断言"脚注上标不残留"，确认无双标记。⚠️ 已知小边界：正文 marker 号与脚注段落号用两套计数器，仅当某 `footnoteReference` 指向空/缺失脚注时会错位（正常 Word 稿全部非空则锁步一致，罕见畸形稿才触发）。
- [x] **IMP-2 收尾：DOCX 内嵌图片改落项目目录** — ✅ Codex @ 同分支（`3f84c77`），Claude 已合 dev
  - 内嵌图片不再写到源 `.docx` 同级 `images/`，改写系统临时目录下唯一 `layoutd-docx-assets-*/images`；`Asset.fileName` 仍保持 `images/<name>` 引用名；顺带规范化 `word/media` 相对路径（`normalizedWordEntryPath` 处理 `../`）。
- [x] **GUARD-3 DOCX 端到端探针进 review-idml.sh** — ✅ Codex @ 同分支（`3f84c77`），Claude 已合 dev
  - 探针现场用 python3 造最小 OOXML（粗斜体/内嵌图/脚注）走完整 DOCX 导入→IDML→解包，断言 FauxBold/Skew/原生 Footnote/上标不残留/图片进 Links。探针总数 8→10 全过。
- [ ] **GUARD-4 串接文流探针** ⏳ **等 THREAD-1b 落地后再领（现在做会断言一个还不存在的结构）**：`review-idml.sh` 断言正文框 Previous/NextTextFrame 串接链完整（可从任一链头走到链尾）、story 数按章计不按段计、无孤儿正文框。文件：`scripts/review-idml.sh`。验收：探针在 THREAD-1b 后的 dev PASS；人为断开一处串接时 FAIL（自证有效）；整脚本仍 PASS。

## Antigravity 道队列（预览渲染 + GUI）

> 负责文件：`Sources/LayoutDEngine/LayoutEngine.swift`、`PDFExporter.swift`、`PNGExporter.swift`、`Sources/LayoutDApp/*`
> ⚠️ 教训复盘：每个新任务从**最新 dev** 起分支、真把 feat 本体迁过去（别只加 docs commit）；同步 dev 不碰 QUEUE.md（已归 Claude 独占）；**生成样张别提交进仓库**（B1 踩过，Claude 合并时剔除了 20 个 PNG/PDF）。

- [x] **PERF-3 排版异步化 + 防抖** — ✅ AG `c99e48a`，排版及预检移出主线程，引入 150ms 防抖，支持首帧/测试环境同步回退。
  - 背景：每次改动全书重排两遍 + preflight 同步跑在界面线程（`AppState.recalculateLayout`），书稿变大会卡界面。
  - 目标：连续操作只排最后一次（防抖），layout/preflight 移出界面线程（异步化）；首帧仍同步保证打开即有版面；须防状态流里的 GUI 竞态（异步排版结果回来时用户可能已经切换了选中/页面）。
  - 文件：`AppState.swift`、可能 `CanvasView.swift`。
  - 验收：连续快速操作（如连续拖拽/连续按键）时界面不卡顿、只在停顿后触发一次真实重排；PERF-1 基准脚本仍 PASS；全部现有测试/探针 PASS。
- [ ] **PERF-4 引擎测量改造（CTTypesetter 逐行填充 + 测量缓存）** — 2026-07-05 从 Claude 道转来。风险最高，**Claude 审过 AG 提交的方案后追加了两条硬约束（见下），必须照做**。拆成 4a/4b 两棒，先做低风险的 4a，量够不够再决定动不动 4b。
  - **背景（Claude review 结论）**：`estimatedTextHeight`（LayoutEngine.swift:1121）用完整 `CTFramesetterSuggestFrameSizeWithConstraints` 测高，是 `(text, style, width, inlineRuns)` 的纯函数，缓存它安全。但 `fittingPrefix`（:544）的二分查找里，`bestCount` 会喂给下游 kinsoku/避头尾/孤寡行处理，改写断点算法有让分页悄悄错位的风险；且当前 golden 语料（PerformanceBenchmarkTests，只有正文/标题的中英混排）没覆盖首行缩进/竖排/行内粗斜体/图片环绕，"golden 过了"给不了真信心。

  ### [x] 4a｜测高缓存（已由 AG 于 feature/ag-perf4a-cache 完成）
  - 目标：给 `estimatedTextHeight` 加线程安全缓存（NSLock 保护），命中即跳过 CoreText framesetter 构建。整段能放下的段落走 `fittingPrefix` 的 early-return（:558 测一次高就返回），重排时全是缓存命中——这是 80% 收益来源。
  - **⚠️ 硬约束①（缓存钥匙必须完整，配错会静默算错分页）**：钥匙**不能**只用 `(text, fontName, fontSize, lineHeight, firstLineIndent, layoutDirection, width, inlineRuns)`。`makeAttributedString` 逐字调 `style.fontMapping(for:)`，按字符套不同字体 + `sizeMultiplier` + `baselineOffset`（复合字体）。**钥匙必须再纳入该样式整套复合字体映射的指纹**（family/fallback/每段 sizeMultiplier/baselineOffset），否则两个只有复合字体配置不同、fontName/fontSize 相同的样式会撞键，取到旧高度→分页错且无声。`InlineRun`/`InlineEmphasis` 标 `Hashable` 时要含 emphasis。
  - 文件：`Sources/LayoutDEngine/LayoutEngine.swift`（`estimatedTextHeight` + 缓存类）；如需给样式加指纹计算可加到 `Sources/LayoutDCore/`。
  - 验收：PERF-1 基准显著下降；全部现有测试/探针 PASS；**新增一个缓存正确性单测**：构造两个 fontName/fontSize 相同但复合字体映射不同的样式，断言其测高缓存不互相污染（同键必同高、异配置不撞键）。

  ### ~~4b｜`fittingPrefix` 二分改单次扫描~~ ⏸ **暂缓（用户 2026-07-05 决定：4a 已拿到 16% 提升，够用；高风险改动暂不追加，日后需要再评估）**
  - 目标：`overlaps.isEmpty` 分支里的二分查找（:562-577，每步重建 framesetter）改为 `CTTypesetterCreateWithAttributedString` + `CTTypesetterSuggestLineBreak` 单次逐行扫描取 `bestCount`。
  - **⚠️ 硬约束②（"断点 100% 一致"是待验证假设，不是承诺，先扩 golden 再动手）**：手写逐行循环要精确复现 framesetter 的四处细节，任一漏掉都会改断点：①第一行必须手工减掉 `firstLineHeadIndent`；②`CTTypesetterSuggestLineBreak` 默认算法 vs framesetter 的 `byWordWrapping` 在中英混排不保证逐字一致；③老高度是 `max(ceil(总高), lineHeight)`（有 ceil 取整 + 最小行高 + 末行 descent），不是"行数×行高"；④复合字体 sizeMultiplier 改字宽→改断点。**开工顺序强制为**：先把 golden 回归语料扩充到覆盖 {首行缩进、竖排 layoutDirection==.vertical、行内粗/斜/着重、图片环绕 overlaps 非空} 四类，跑通"改动前逐页字符区间+坐标 100% 一致"的 golden 比对基线，**再**动断点算法；改完该 golden 必须仍逐页全等。达不到 100% 全等就**不合**，退回 4a 收益即可。
  - 文件：`Sources/LayoutDEngine/LayoutEngine.swift`、`Sources/LayoutDCore/ChineseTypesetting.swift`、golden 语料测试（`Tests/`）。
  - 验收：扩充后的 golden 逐页字符区间+坐标改动前后 100% 一致；PERF-1 基准进一步下降；全部测试/探针 PASS。

- [x] **GUARD-2 断言闸字形覆盖检查（rule⑥）** — ✅ AG `b3a2e97`, 合 dev(8389c9c)
  - 背景：rule⑤ 已拦「字重不存在→Helvetica 豆腐」；还差「字体存在但缺 CJK 字形→豆腐」（脚注豆腐那类事故的自动网）。
  - 目标：`IDMLInvariants` 加 rule⑥——对每个注册字体用 CoreText 抽查文档实际用到的字符集样本（如每 Story 抽前 N 个 CJK 字符）能否出字形（`CTFontGetGlyphsForCharacters`），缺字形即 FAIL 并报出字体名+字符。
  - 文件：`Sources/LayoutDExport/IDMLInvariants.swift`、`Tests/LayoutDExportTests/IDMLInvariantsTests.swift`（⚠️ 跨道改导出文件——沿用 rule⑤ 先例，已知会 Claude）。
  - 验收：单测含正反例（CJK 字体过、纯拉丁字体配中文 FAIL）；全套测试 + `review-idml.sh` PASS。
- [x] **E2-4p 补完：对开左右页并排预览 + 版心镜像** — ✅ AG `77c595c`, 合 dev(8389c9c)。⚠️ 属渲染代码，PDF/PNG 对开左右页并排（文件名 page-NNN-MMM）已落地、单测过；待用户对开稿 PNG 肉眼确认并排定位（非阻塞）。
  - 目标：`facingPages` 开启时 Canvas/PDF/PNG 左右页并排、版心镜像（订口内侧）；关闭时与现状一致。
  - 文件：`LayoutEngine.swift`、`CanvasView.swift`、`PDFExporter.swift`、`PNGExporter.swift`。
  - 验收：对开稿导 PNG 左右页镜像正确；非对开零回归；单测断言镜像边距；`review-idml.sh` PASS。
- [x] **SPLIT-GUI 巨型 GUI 文件拆分**（由 AG 于 feature/ag-split-gui 分三棒完成）— ✅ 用户 2026-07-06 GUI 截图抽查通过，已随批合 main(`0bbda6c`)。
  - 目标：`main.swift`(1500 行，拆出 AppDelegate/菜单/WorkspaceViewController/CLI 各自文件)、`InspectorView.swift`(1600 行，按面板 section 拆)、`CanvasView.swift`(1400 行，拆出工具交互/绘制)。
  - 文件：`Sources/LayoutDApp/*`。
  - 验收：全部测试零修改通过；`review-idml.sh` PASS；GUI 行为无变化（拆完 Claude 出包给用户抽查）。
- [ ] **FIX-CANVAS-1 画布图片标题前泄漏资产 id**（小修）：用户 2026-07-06 GUI 抽查截图发现画布上示意图标题显示为「cell-d细胞结构示意」——"cell-d" 疑似资产 id/文件名前缀混进了标题渲染（InDesign 里打开同一文档无此前缀，仅画布预览有）。查 `CanvasView+Drawing.swift` 图片占位/标题绘制路径，只画标题本体。
  - 文件：`Sources/LayoutDApp/CanvasView+Drawing.swift`（或相关渲染函数所在文件）。
  - 验收：画布显示「细胞结构示意」无 id 前缀；PDF/PNG 导出同步检查无此问题；全部测试/探针 PASS。

## Backlog（按车道路由）

- [x] **B1 图文绕排预览** — ✅ AG `099f38b`，Claude 审核合 dev（`09b8cc4`，2026-07-04）。详见归档；导出侧配对任务 = Claude 道 B1-IDML。
- ⏹ ~~B2 长表格分页~~ / ~~B3 索引~~ / ~~B4 引文样式~~ — 用户 2026-06-23 决定不做。

## 基础设施待办（Claude/用户）

- [x] **真正 CI** — ✅ `.github/workflows/ci.yml`（2026-06-23 起 push/PR 自动跑 review-idml.sh，macOS runner）。
- [ ] IDML 官方 RNG schema 校验 + golden-file 回归基线，补强 `review-idml.sh`（golden 需先解决 CI 字体环境差异，见 ci.yml 注释）。
- [ ] relay `run_checks("test")` 末行误显「0 tests」，改回显 XCTest 汇总行（改 relay-mcp，仓库在 `~/tools/relay-mcp`）。
