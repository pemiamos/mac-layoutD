# layoutD 开发计划（执行权威）

状态：Living（本文件是执行计划的唯一权威；PRD 管需求，本文管落地）
更新：2026-07-08（补记阶段 F「初排灌版主线」；新增文末「2026-07-08 项目复盘」）

进度图例：✅ 已实现　🟡 部分　⬜ 未开始

相关文档：需求 [layoutd-prd.md](layoutd-prd.md) · 架构 [architecture.md](architecture.md) · 样式基线 [visual-paradigm-jiangnan.md](visual-paradigm-jiangnan.md) · 工具分工 [design-tool-comparison.md](design-tool-comparison.md)

## 工作流定位（一句话）

样张定样式 → 导入为结构化样式基线 → 确定性灌版 + 中文排版 → 人工微调 → 导出。layoutD 拥有"灌版 + 中文排版 + 微调 + 一致性"；封面/插图/图表/3D 立体书等成品美术由外部工具产出后作为资产置入。

## 5 支柱

| 支柱 | 内容 | 现状 |
|---|---|---|
| P1 样式基线 | 统一 token 模型 + StyleLibrary + PageSetup + 组件定义 + 模板（DTCG 风格 schema） | 🟡 |
| P2 导入 | Markdown✅ + Figma/DTCG 样式导入 + IDML 结构参照 | 🟡 |
| P3 灌版引擎 | 确定性分页✅ + 复合字体 + 竖排 + 两层模型 | 🟡 |
| P4 人工微调闭环 | 编辑→override→重排 + undo/redo + 锁页 + 工具集 + 批注层 | 🟡 雏形 |
| P5 预检与导出 | 预检✅ + qualityMetrics 可视化 + 封面固定页导出 | 🟡 |

## 关键决策（约束所有任务）

- **AI = 受控变体**：只在已批准样式框架内生成合规排布变体；合规由引擎 `planValidationFailures` 扩成的"样式合规闸门"强制拒绝越框块。
- **人工编辑走 override**：不产生自由几何，每次编辑捕获为 `LayoutPlan`/override 再确定性重排。
- **中文排版自有引擎**：复合字体/竖排/禁则约物外部工具都不提供，必须自做。
- **两层模型**：结构层引擎拥有；美术层（封面/满版/扇面/印章/底纹）作固定页/置入资产，不重排。
- **裁掉**：自由矢量绘制、图表生成/数据驱动、PDF/X、3D 立体书、封面设计内核化。

---

## 阶段 A — 地基（当前阶段）

> 目标：立起样式模型与微调承重墙；解锁后续一切。

### A1. P1 样式基线 schema
- [x] 在 `LayoutDCore` 定义统一 token 模型（`DesignTokens`：color 多模式 + scalar）+ 解析器 + DTCG 导出（`dtcgExport`）。支持**多模式**（章节主题色组：绿/蓝）。
- [x] `StyleLibrary` 加可选 `tokens` 字段 + `colorHex(_:mode:)` 解析器（优先 tokens，回退 legacy `colors`）+ `effectiveTokens`；向后兼容（旧 `.layoutd` 无 `tokens` 键解码为 nil）。
- [x] 重构消费端（颜色）：PDF/PNG/Canvas 三处渲染器经 `colorHex(_:mode:)` 解析段落色（颜色优先级：frame override > 样式色 token > 回退）。token 现已真正驱动文字颜色。
- [x] 颜色**多模式 live**：`BookProject.colorMode` + `resolvedColorHex(_:)`，渲染器据此解析；切换模式全书联动（绿/蓝主题组）。向后兼容（旧 `.layoutd` 解码 `colorMode == nil`）。
- [x] `ParagraphStyle` 字号/行距/间距改为**引用 scalar token**而非硬编码值；`StyleLibrary.paragraphStyle(id:)` 返回 token 解析后的有效样式，手动编辑会清除对应 token 绑定。
- [x] `PageSetup` 的网格/页边距/栏/基线纳入同一 schema；默认页边距、栏数、栏距、基线网格可通过 scalar token 联动，手动编辑会清除对应 token 绑定。
- [x] 形式化组件定义（知识卡片/表格/图注）为样式化模板；`StyleLibrary.componentStyles` 定义 fill/stroke/accent/text inset，Canvas/PDF/PNG 共同消费，旧项目缺字段时回退默认组件。
- [x] `.layoutd` 持久化加 schema 版本号（`BookProject.schemaVersion`，旧文件缺字段时默认当前 schema）。
- 验收：项目可序列化为 DTCG 风格 JSON ✅（`dtcgExport`）；改一个**颜色** token → 全书联动 ✅；改一个**段落 scalar** token → 字号/行距/间距联动 ✅；改一个**页面 scalar** token → 页边距/栏数/栏距/基线联动 ✅；旧 `.layoutd` 仍可打开 ✅。
- 涉及：`LayoutDCore`（StyleLibrary/BookProject）、三处渲染器。

### A2. P4 微调基石闭环（最高优先级）
- [x] 统一"编辑捕获"为 override 模型（归并现有 `freezePageToPlan` + frame override）。
- [x] undo/redo 栈（`AppState` 层，项目级快照或操作记录）。
- [x] 锁页：`lockedPages` 接入 UI；重排时尊重锁定页不被破坏。
- [x] 改动 diff：自动排版 baseline vs 当前 override 的可视化提示（PRD §8.3/6.5）。
- 验收：移动/缩放 frame→捕获 override→其余页确定性重排→撤销可回退→锁定页不受后续重排影响；能看出某页相对自动排版改了什么。
- 涉及：`LayoutDApp`（AppState/Canvas/Inspector）、`LayoutDEngine`（尊重锁定）。

---

## 阶段 B — 接口 + 护城河起步

### B1. 复合字体（合成字体）
- [x] `ParagraphStyle` 从单一 `fontName` 扩展为"命名复合字体"：按字符类（汉字/全角标点/半角标点/罗马字/数字/符号）映射 字体 + 字号% + 基线偏移（对标 InDesign 复合字体编辑器）。
- [x] 文本测量（CoreText）与 PDF/PNG/Canvas 渲染按字符类切字体；归并现有"中西文混排补白"。
- 验收：一行中英数字混排各用对应字体、对齐正确；样式切换全书生效。
- 涉及：`LayoutDCore`（ParagraphStyle）、`LayoutDEngine`、三处渲染器。

### B2. Figma/DTCG 样式导入（P2，依赖 A1）
- [x] 定义导入映射：Figma Variables/REST 或 DTCG JSON → A1 的 token/style 模型；layout grid → PageSetup。
- [x] 导入后"映射确认/补值"界面：显式处理有损项（基线网格、中文排版项）。
- [x] token 绑定率体检：导入前报告"多少是 token/命名样式 vs 写死值"。
- 验收：一个结构良好的 Figma/DTCG 样张能导成可灌版的样式基线。
- 涉及：新 `LayoutDImport` 样式导入路径、`LayoutDApp` UI。

### B3. AI 受控变体（依赖 A1 + 校验扩展）
- [x] 把 `planValidationFailures` 扩成"样式合规闸门"：拒绝引用非批准 token / 非样式库字体 / 非组件清单块的变体。
- [x] 变体生成器在合规集合内产出多排布（丰富视觉、避免页页雷同）。
- 验收：生成的变体全部合规；越框变体被拒绝并回退。
- 涉及：`LayoutDEngine`、`LayoutDDesignAI`。

---

## 阶段 C — 护城河纵深 + 美术层

### C1. 竖排（直排）
- [x] 纵向文本流、行进方向、frame 几何与分页方向；竖排禁则。
- 验收：能竖排一段引文/诗并正确分行分页。
- 涉及：`LayoutDEngine`、渲染器、`PageSetup`（排版方向）。

### C2. 两层模型（固定美术页 / 置入资产 / 非矩形蒙版）
- [x] 一等"固定页/美术页"类型：不参与重排，承载满版图、扉页、封面。
- [x] 置入装饰资产 + 非矩形图框蒙版（扇面/八边形）作图片处理选项。
- 验收：满版图整页与扇面图框能正确置入、导出，且不被重排打乱。
- 涉及：`LayoutDCore`（页/frame 模型）、`LayoutDEngine`、渲染器。

---

## 阶段 D — 收尾 / 增强

- [x] `qualityMetrics` 接入可视化与历史追踪。
- [x] 封面/满版图作固定页导出。
- [x] 校对批注层（不参与重排的 overlay）。
- [x] DOCX 导入（D-2）。 — Codex 实现 `DOCXBookImporter.swift`（`85d7a00`），已合 dev+main（merge `69ba11c`），**用户视觉验收 PASS**。

---

## 阶段 E — 主交付路线：IDML 灌版交棒（进行中）

> 决策见 `.ai/DECISIONS.md`（2026-06-19）：layoutD 收敛为「灌版引擎」，主交付改为
> 导出 IDML 交 InDesign 做人工精调 + 印前。原阶段 D 的「IDML 结构参照」「更完整印前」
> 两项被本阶段取代/吸收——印前（CMYK/PDF/X）确定交 InDesign，layoutD 不自建。

### E0. 最小验证 spike ✅ 已被 E1 取代吸收
- [x] `--idml-spike <path>` 已实现并在 **InDesign 中文版**人工验证通过（竖排/复合字体/图链/CMYK Swatch
      全 round-trip），主交付转向 E1 全量映射。spike 代码留作回归探针（`IDMLSpikeExporter.swift`）。

### E1. BookProject → IDML 全量映射（spike 通过后）
最小可用版已落地并在 InDesign 中文版**人工终验通过**（`--export-idml PATH`，`Sources/LayoutDExport/IDMLExporter.swift`）：
- [x] 页 → Spread/Page（单页 spread）；文本框 → TextFrame/Story；段落样式 → ParagraphStyle。
- [x] 颜色 token → RGB 色板；置入图 → Rectangle+Image+Link。
- [x] 复合字体 → Fonts.xml 内 CompositeFont；竖排 → Story `StoryOrientation=Vertical`。
- [x] 字体匹配：CoreText 取真实 FontType（系统 CJK 是 OpenTypeCID 非 CFF）+ PostScript 名 → InDesign 无缺失字体。
- [x] 非对开干净分页：`PagesPerDocument="1"`（恒为 1，非实际页数）+ `FacingPages="false"` + spread 纵向偏移 → 无空白页、主页单页。
- [x] 容器级自动验证（IDMLExporterTests）+ demo.md 端到端导出、全 XML well-formed、InDesign 4 页内容全正确。
已随 MVP 一并解决：字体「家族+样式名」拆分（splitFont + FontType 检测）；首页幻影（改单页非对开后自然消失）。

### E1b. CJK 保真三层策略（2026-06-23，决策见 `.ai/DECISIONS.md`、记录见 `docs/idml-oracle/FINDINGS.md`）
> 不外化 ExtendScript/UXP API（描述内存 DOM，非我们 emit 的 IDML 磁盘格式；且不编码跨属性渲染前置条件）。
- [x] **①不变量断言闸** `IDMLInvariants.swift`：打包前硬检查已知 CJK 渲染搭档规则（着重号需 World-Ready 排版器、脚注需 CJK 字体样式、CJK 粗斜走 FauxBold/Skew、AppliedFont 引用完整性），撞回归当场报错。
- [x] **②InDesign 往返 oracle**：用真·InDesign 存盘当 golden diff，抽取规范不写的真值。**首战即修真 bug**：CJK 排版器此前三处全错（属性名 `AppliedComposer`→真值 `Composer`；值 Optyca 拉丁→真值 `HL Composer J`；位置应挂段落样式+TextDefault）——这是中文断行/避头尾一直走错引擎的根因。golden 归档 `docs/idml-oracle/goldens/`。
- [ ] **③可选 IDML-RNG lint**（vendor InDesign `app.generateIDMLSchema()` 的 RNG 做名/枚举校验）+ 断言闸加 CoreText 字形覆盖检查。后续增量。

### E2. IDML 增强（接力分工，详见 `.ai/AGENTS.md`）

> 单向流，不做 IDML 回导；交棒后 InDesign 为真理源。
> **2026-06-23 用户 InDesign 验收 ✅**：E3-6 动态目录（页码右对齐+点导引线+层级缩进）、
> E2-4 对开跨页（首页单独+左右镜像+订口在内）、E2-5 非矩形蒙版——三项均人工肉眼通过。
> 验收样例（含最新 CJK 排版器修复）：`~/Desktop/验收1-动态目录-0623.idml`、`验收3-对开跨页-0623.idml`。
> 蒙版无 Markdown/CLI 路径（maskShape 仅 GUI/布局模型设），几何另有端到端单测（八角8/扇面≥16点）兜底。

> 单向流，不做 IDML 回导；交棒后 InDesign 为真理源。每项验收口径：导出 → InDesign 中文版打开正确（视觉验收由用户/Antigravity 做，Claude 无 Screen Recording 权限）。

> **E2 全部完成（2026-06-23）**：E2-1～E2-7 均已落地并合 dev/main，核心特性经用户 InDesign 视觉验收通过。

| # | 任务 | 主负责 | 状态 |
|---|---|---|---|
| E2-1 | **图片打包 + 相对重链** | Codex | ✅ 置入图复制进 `Links/`、`LinkResourceURI="file:Links/…"` 相对路径，`.idml` 可移植 |
| E2-2 | **组件背景 / 描边** | Codex | ✅ 组件底色/描边经 `componentStyle` 映射成框架填色描边 |
| E2-3 | **避头尾 → 禁则集** | Codex | ✅ 中文禁则映射 InDesign 禁则集 |
| E2-4 | **对开跨页（facing spread）** | **Claude** | ✅ 视觉验收过（首页单独+左右镜像+订口在内），`02900eb` |
| E2-5 | **固定美术页 → MasterSpread / 非矩形蒙版** | Claude | ✅ 视觉验收过（八角/扇面 PathGeometry），`404596b` |
| E2-6 | **`/usr/bin/zip` → 原生 zip 写入** | Codex | ✅ 主 IDML 路径用原生 `ZIPArchiveWriter`（mimetype store-first）|
| E2-7 | **GUI 加 IDML 导出入口** | Codex | ✅ App/CLI 导出 IDML 入口 + 导出选项面板（对开/CMYK 留位）|
| — | **审查 + 拆解指令 + 每项验收闭环** | Claude | ✅ 持续闭环 |
| — | **InDesign 打开效果 / GUI 交互视觉验证** | Antigravity / 用户 | ✅ 已替代 Claude 做视觉验收 |

> 说明：`swift test` 末尾「0 tests in 0 suites」是 **Swift Testing 运行器**（找 `@Test`）的输出，本项目全用 XCTest，实测 **172 个 XCTest 全部执行通过**（`swift test` 完整输出含 "Executed 172 tests, 0 failures"）。relay `run_checks("test")` 仅回显最后一行才造成「0 tests」错觉——**非测试发现 bug，是 run_checks 输出截取问题**，可在 relay 侧改为回显 XCTest 汇总行。

- 验收：一份真实 demo 项目导出的 IDML 在 InDesign 打开后版面与 layoutD 预览一致到「可微调」程度。

### E3. 行内 / 结构特性增强（接力分工，逐项 InDesign 视觉验收）

> 任务级拆解与验收口径见 `.ai/QUEUE.md`（Codex 道 / AG 道）。本表只记排期与状态。

| # | 任务 | 主负责 | 状态 |
|---|---|---|---|
| E3-1 | 行内粗/斜体到所有 block | Codex | ✅ 视觉验收过 |
| E3-2 | 行内格式预览渲染 + 批注层 | AG | ✅ 视觉验收过 |
| ~~E3-3 / E3-3v~~ | ~~傍点（着重号）~~ | — | ⏹ **已移出计划**（用户 2026-06-23：图书项目不用着重号，不再投入。见下方说明） |
| E3-4 | 原生表格 `<Table>` | Claude | ✅ 视觉验收过 |
| E3-7 / E3-7v | 脚注 → 原生 Footnote + 中文豆腐修复 | Codex/Claude | ✅ 视觉验收过 |
| E3-2b / ~~E3-3p~~ / E3-4p | 竖排斜体 / ~~傍点~~ / 表格网格 预览渲染 | AG | ✅ 已合 dev/main（随 e3-10p `c5fcfb7`，竖排斜体/表格网格视觉验收过；傍点部分已移出，见下） |
| E3-4b | 表格单元格内行内格式（E3-4 遗留缺口） | Codex | ⬜ 已立项 |
| E3-10p | 预览验收 harness（让 PNG 能呈现行内特性） | AG | ⬜ 已立项·高优先 |

> **傍点（着重号）已移出计划（2026-06-23，用户决定）**：图书项目不使用着重号，不再投入。
> 已合入的相关代码**保留不回滚**：① CJK 段落排版器 `Composer="HL Composer J"`（dev `e2a78be`）
> 是**通用 CJK 排版基础设施**（影响避头尾/断行等，非着重号专属），保留；② 着重号 emit 与断言闸
> rule①（dev `63a9a5c`）仅在稿件出现 `==着重==` 时触发，无害，留存即可。后续不再为着重号花精力。

#### 排期决策（2026-06-21，用户确认）

「锦上添花」批正式纳入开发计划，按以下顺序接力（均 Codex 道，风险低→高）：

| 顺序 | 任务 | 说明 |
|---|---|---|
| 1 | **E3-6 目录（TOC）动态化** | 死文字目录 → InDesign 动态 TOC / PageReference |
| 2 | **D-2 DOCX 导入** | 新增 `DOCXBookImporter.swift`，独立文件不与导出冲突，可并行 |
| 3 | **E2-5 固定美术页 → MasterSpread / 非矩形蒙版** | 满版图/扉页固定页映射、扇面/八角蒙版 |
| 4 | **E2-4 对开跨页（facing spread）** — 👤 **Claude 做** | 风险最高（可能打破当前干净分页），放最后单独一棒、做完先验非对开无回归。跨 Codex 负责文件，须等 Codex 本批 IDMLExporter 改动先合 dev |

- **E3-8 token → CMYK 色板：暂缓**（用户 2026-06-21 决定先不做；印前转色本就交 InDesign，非阻塞）。
- **E3-9 约物挤压 + 基线网格对齐**：维持原排期，未纳入本批。

---

## 阶段 F — 初排灌版主线（2026-07 定位校准后，核心已落地）

> **2026-07-06 定位校准（DECISIONS）**：layoutD 的交付物是给 InDesign 的「初排灌版」，不是替代 InDesign。
> 开发价值标准 = 文流结构/样式体系/视觉规范/色彩能否高完成度迁移进 InDesign、给人工调整省时间。
> **可编辑性 > 逐像素冻结**（InDesign 里漂移可人工调校）；脚注/傍点/表格深化 = 初排细枝末节，不再投入。
> 任务级细节见 `.ai/QUEUE.md` 与 `.ai/QUEUE-ARCHIVE.md`，此处只记里程碑。

### F1. 串接文流（THE core gap，✅ 全部 InDesign 人工验收通过）
- [x] **THREAD-1a** 串接 spike：一章一 Story + Previous/NextTextFrame 串接，跨页拆段/编辑自动重排铁证成立。
- [x] **THREAD-1b 三刀**：①正文+标题按章串接（含多栏 (页,栏) 分组修复）；②内嵌图锚定（AnchoredAboveLine 随宿主段落走；图注锚定因 InDesign 字距拉伸 bug 回退为独立框，见 DECISIONS 2026-07-06）；③收边（GUARD-4 串接探针 + 表格/目录不误并入文流）。
- [x] **段落回车根治**：段落分隔必须用 IDML `<Br/>` 元素（用户 7 种写法实机验证定案），统一修复章串接/逐帧/目录三路径。
- [x] **MASTER-1** 主页自动页码（`<?ACE 18?>` 当前页码变量，正文页统一 AppliedMaster）。
- [x] **SPREAD-1** GUI 导出面板对开开关默认跟随项目 `pageSetup.facingPages`（真对开 spread 早于 E2-4 完成）。

### F2. 一个角色一个框（FRAME-SPLIT 链路，✅ IDML 与预览一致）
- [x] **FRAME-SPLIT**：标题/概述/抽言/图注/参考文献各自独立框各套样式，只有纯正文进串接流；文流遇独立框角色即断（每段连续正文一条串接链）；废除内嵌图锚定 cut2 机制之外的锚定文字路径；新增 `Asset.wrapMode`（wrap 绕排 / underlay 垫底）。
- [x] **FRAME-CANVAS-0/1**：断流分组逻辑抽成共享函数 `groupIntoFlowFrames`（LayoutDEngine），画布/PDF/PNG 消费同一分组——连续正文显示合并虚线框、整组选中移动、属性面板多选保护（审核时顺手修复画布每帧全文档重算的性能问题）。
- [x] **FRAME-INSET-2** 预览文字贴框边（追平 IDML InsetSpacing=0）；**UNDERLAY-1** 垫底图不占版面、图下字上，三渲染器一致。
- [x] **默认排书规则批次**：左对齐/首行不缩进/段间空行、关基线网格逐行锁定、默认不生成目录。
- [x] **TYPE-1** 段末孤字（NoBreak 末两字）— 代码已合，待用户 InDesign 终验。

### F3. 视觉规范包路线（✅ 首链路跑通，见 DECISIONS 2026-07-07）
> AI 生成规范包 JSON → layoutD 校验渲染样张 → 人工比选定稿 → 同一规范直通初排与 IDML。放弃 Figma 作为主路径。
- [x] **SPEC-PACK-1**（Codex）：`StyleBaselineImporter.parseSpecPack` 唯一解析事实源（schema 校验/字体 CoreText 核验/不支持字段显式上报）+ `docs/spec-pack-guide.md`。
- [x] **FIXTURE-1**（Claude）：`Samples/fixture-standard-chapter.md` 标准样章覆盖全部角色标签 + 回归语料。
- [x] **SAMPLE-1**（AG，重做版）：CLI `--render-samples` 一键批量样张；共享应用函数 `BookProject.applySpecPack`（字体族/角色色/开本 trim 落地）；PDF 重跑确定性按内容级掩码探针验收。
- [ ] **规范包 → 正式项目应用闭环**：目前只有 CLI 样张路径；GUI「导入规范包应用到当前项目」入口未做（见文末复盘 → 后续计划）。

### F4. 工程与性能
- [x] PERF-1 基准（161 页 ≈1179ms）/ PERF-2 baseline 缓存 / PERF-3 排版异步化+防抖 / PERF-4a 测高缓存（16%）；4b 暂缓（用户 2026-07-05）。
- [x] GOLDEN-GUARD 防漂移护栏（--reason 审计 + 强制 diff + 本地 golden 探针）；GUARD-1～4 端到端探针进 `review-idml.sh`（14 项）。
- [x] SPLIT-ENGINE / SPLIT-EXPORT / SPLIT-IMPORT / SPLIT-GUI 巨型文件拆分。

---

## 2026-07-08 项目复盘（问题 / 改进 / 后续计划）

> 本节为 2026-07-08 全项目 review 的结论存档。「后续计划」为**候选提案，优先级待用户拍板**后才登记进 `.ai/QUEUE.md`。

### 现状一句话

主链路已完整且多轮 InDesign 人工验收通过：角色标签稿（Markdown/DOCX）→ 确定性引擎 → 画布/PDF/PNG 预览 → IDML（串接文流/分框/锚定图/主页页码/对开）→ InDesign 人工精调。303 单测 + 14 项端到端探针 + golden 护栏 + CI 全绿。规范包路线首链路跑通。

### 目前的问题

1. **待视觉验收积压，dev 领先 main 18 个 commit**。排队中的至少有：FRAME-CANVAS-1 合并框 GUI、TYPE-1 段末孤字（InDesign）、E3-9 约物挤压/基线贴齐（InDesign）、InDesign 式工作区骨架、左侧工具栏（见 QUEUE「待用户视觉验收」段）。积压越久，验收发现问题时越难定位是哪笔改动引入的。
2. **「预览≠输出」会反复再生**。画布/PDF/PNG 三个渲染器各自实现绘制，IDML 侧每改一个行为，就要出一个「追平」任务（FRAME-INSET-2、FRAME-CANVAS-1、UNDERLAY-1、E2-4p 全是这一类）。根因是没有共享的「绘制模型」层，三处代码天然会漂。
3. **规范包路线断在最后一公里**。规范包能出样张（CLI），但定稿后无法在 GUI 里一键应用到真实书稿项目——目前视觉三项（字体族/角色色/开本）只有 `--render-samples` 路径会走 `applySpecPack`。
4. **大文件回涨**。AppState.swift 已到 1375 行（从未拆过）；CanvasView+Drawing 1089、PDFExporter 1085、WorkspaceViewController 982——SPLIT 批次之后 GUI/导出侧又长回来了。
5. **纪律性 drift**：SAMPLE-1 v2 跨道直改了 Codex 的 StyleBaselineImporter（已合，欠回归）；QUEUE.md 曾在合并中被误删任务（已补回）；HANDOFF.md 交接条目常滞留未提交状态。
6. **已知未解 bug 存档**：锚定字符后紧跟文字在 InDesign 里字距拉伸/丢字（anchored-text stretch，未解，需真机迭代，不盲改）；图注不随图锚定（已接受为限制）。
7. **两个队列（Codex 道/AG 道）活任务已清空**，下一批任务未规划——本复盘的「后续计划」即为此准备。

### 改进意见

- **流程**：约定「dev 领先 main 超过 ~10 commit 或攒满一批功能」就集中做一次用户视觉验收+合 main，不让验收无限后置。
- **架构**（中期最有价值的一刀）：提取共享绘制模型（页面→绘制指令列表），画布/PDF/PNG 只做「指令→各自画布」的薄适配层，从根上消灭「追平」类任务。
- **纪律**：StyleBaselineImporter 后续字段扩展回归 Codex 道；交接后 HANDOFF.md 随批提交；每合一批 main 顺手回写本文件（本次已补 6-23 以来全部欠账）。

### 后续开发计划（候选，待用户拍板排期）

| 优先 | 任务 | 说明 | 建议道 |
|---|---|---|---|
| P0 | **验收批次** | 集中清掉「待视觉验收」积压 → 合 main | 用户 + Claude |
| P0 | **SPEC-APPLY-1 规范包应用闭环** | GUI「导入规范包」入口：定稿规范 JSON 一键应用到当前项目（复用 `applySpecPack`），即从「出样张」走到「用规范排真书」 | AG（GUI）+ Codex（解析字段补全） |
| P0 | **PILOT-2 真书整本试排** | 用定稿规范包 + 角色标签整本书稿（如《村落》）跑通 导入→初排→IDML→InDesign 全流程，检验整本规模下的角色覆盖/性能/InDesign 打开体验，产出问题清单 | Claude 主导 |
| P1 | **RENDER-CORE-1 共享绘制模型** | 见改进意见第 2 条；先出设计再动手，属高风险重构 | Claude 设计 + AG 实施 |
| P1 | **SPLIT-APPSTATE** | AppState.swift 1375 行拆分（照 SPLIT-ENGINE 配方，纯搬家零行为变化） | AG |
| P2 | **IDML-RNG lint**（E1b③） | vendor `app.generateIDMLSchema()` RNG 做名/枚举 lint | Codex |
| 按需 | anchored-text stretch bug | 只在真实书稿再撞上时，真机 InDesign 迭代定位，不盲改 | Claude |

---

## 维护约定

- 任务状态在本文勾选；PRD/architecture 不再重复任务级清单，只保留高层支柱并指向本文。
- 每完成一项，更新对应 ✅ 与 `architecture.md` 的"实现状态概览"。
