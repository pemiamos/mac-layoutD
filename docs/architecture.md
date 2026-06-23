# layoutD 软件架构

状态：Draft  
日期：2026-06-15（2026-06-23 修订）

## 架构目标

layoutD 的核心不是自由画布，而是面向中文科普图书的结构化图文排版系统。架构需要同时满足三件事：

1. 内容可结构化导入和维护。
2. 图文版面可以由 AI 生成候选，但最终必须确定性重排。
3. PDF 输出和页面预览共享同一套布局结果，避免预览和导出漂移。

## 模块划分

```text
LayoutDApp
  macOS AppKit shell, canvas, sidebar, inspector

LayoutDCore
  book project model, page setup, styles, assets, layout plans, laid-out pages

LayoutDEngine
  deterministic pagination, text/image frame placement, layout issue detection

LayoutDDesignAI
  layout-advisor/provider boundary; produces structured LayoutPlan candidates

LayoutDImport
  Markdown manuscript import and image asset scanning

LayoutDCheck
  project structure, image metadata, and asset issue inspection

LayoutDExport
  PDF / PNG / 预检 JSON 导出边界;并承载 IDML 导出（灌版 → InDesign 交棒）
```

> **主交付路线（2026-06-19 决策）**：layoutD 的核心定位收敛为「灌版引擎」——把
> 「Figma 视觉规范 + 内容」自动灌成一份高质量初排，导出 **IDML** 交给 InDesign 做
> 人工精调与印前输出。IDML 从「结构参照」升级为一等导出格式；这是 **单向流**
> （layoutD→IDML→InDesign，改动不回流，交棒后 InDesign 为真理源）。layoutD 仍保留
> 基本结构化编辑工具（见 LayoutPlan/override 两层模型），但不再扩建重型自有编辑器；
> CMYK/PDF/X 继续不自建（强化「印前路线 A」）。详见 `.ai/DECISIONS.md`。

## 数据流

```text
Markdown + image folder
  -> LayoutDImport creates BookProject
  -> BookProject
  -> LayoutAdvisor proposes LayoutPlan candidates
  -> LayoutEngine validates and produces LaidOutDocument
  -> CanvasView previews cover / contents / body pages
  -> PDFExporter writes paginated PDF
```

AI 不直接生成最终页面文件。AI 只生成 `LayoutPlan`：页面目标、策略、块类型、内容引用、相对位置和说明。`LayoutEngine` 负责把计划转换为实际页面框架，并检查是否可用。
`LayoutPlanProvider` 接收 `LayoutPlanRequest`，其中包含项目、目标页面和章节/素材语义摘要；provider 失败或返回空结果时由规则型候选回退。

## 核心模型

### BookProject

项目级对象，包含：

- `metadata`：书名、副标题、作者、出版社、ISBN、丛书、关键词、时间。
- `pageSetup`：开本、页边距、栏数、基线网格。
- `styles`：中文科普图书默认样式库。
- `sections`：章节和正文流。
- `assets`：图片素材库。

`.layoutd` 项目带 `schemaVersion`，旧文件缺字段时按当前 schema 兼容解码。`StyleLibrary` 内的 `DesignTokens` 是样式基线入口：颜色 token 支持多模式解析，段落字号、行距、缩进与段前/段后距可通过 scalar token 引用；`StyleLibrary.paragraphStyle(id:)` 返回已解析的有效样式。`PageSetup` 的页边距、栏数、栏距与基线网格也可绑定 scalar token，并通过 `BookProject.resolvedPageSetup` / `resolvedMargins` / `resolvedColumns` / `resolvedGutter` / `resolvedBaselineGrid` 进入排版和预检。知识卡片、表格、图注等组件由 `StyleLibrary.componentStyles` 定义 fill / stroke / accent / text inset，Canvas、PDF、PNG 共用同一组件样式，确保预览、导出和质量检查共享同一数值来源。

### Story / Paragraph

正文不是页面上的散落文本框，而是可流动的文本流。段落具有 `kind` 和 `styleId`，后续可以支持图片锚定、脚注、旁注和图文关联。

### Asset

图片是一等对象，包含：

- 文件名。
- 图片角色：主图、示意图、照片、图表、步骤图、对比图。
- 图注、版权、尺寸、DPI、使用状态。

### LayoutPlan

AI 和模板系统的共同输出格式。它描述“建议如何排”，不是最终页面。这样可以保留 AI 的设计能力，同时避免不可控的静态图输出。

`LayoutPlan` 是建议而非命令：在渲染前，`LayoutEngine` 会调用 `planValidationFailures(_:)` 校验每个块的归一化坐标是否越界、尺寸是否为正、内容引用（段落、素材、story 范围）是否存活、线程块 id 是否自洽。任何一项失败都会让该页计划被整体拒绝、回退到确定性排版，并在版面问题中记录一条 warning，从而落实“AI 做建议、引擎做决定”的边界。

人工微调走同一条通路：用户的手动编辑（移动/缩放框、换图、改样式、转组件、锁页）不产生游离于内容流之外的自由几何，而是被捕获为 `LayoutPlan` / frame override，再交给引擎确定性重渲染。因此 `LayoutTool` 只提供作用于结构化模型的工具（选择、直接选择、页面、间隔、文字选中、手形、缩放），不提供自由矢量绘制/自由创作（钢笔、铅笔、任意形状、渐变绘制）——这类工具已从工具栏移除。

### LaidOutDocument

排版引擎的输出结果，包含页面、页面框架和检查问题。UI 和 PDF 导出都依赖它。

`PageFrame.kind` 携带语义角色（正文、图片、图注、呼应框、表格、脚注、旁注、页眉）。页眉使用独立的 `runningHeader` 类型，使“冻结当前页为模板”等工具可以按语义识别并排除页眉，而不再依赖其像素坐标。

## 实现状态概览

端到端闭环已经打通：Markdown / 章节包导入 → 素材扫描 → 确定性分页 → 画布预览 → `.layoutd` 保存 → PDF / PNG / 预检 JSON 导出，App 与 CLI 共用同一排版与预检管线。能力按模块归类如下（详细命令见 `README.md`，逐条功能与测试以代码和 `swift test` 为准，本文不再罗列流水账）：

- **导入**：front matter 元数据与页面设置；ATX/Setext 标题、正文、引用、知识卡片、表格、有序/无序列表、行内/引用式图片；图片元数据与 `manifest.csv`；章节包目录与多文件章节流；行内 Markdown 标记清理（保留术语/公式字面量）。
- **排版**：封面/目录/正文分页与目录页码重排；双栏中文版面；hero/comparison/wide 整版图与栏位阻隔；超长文本跨栏拆分；标题 keep-with-next；中西文混排补白；图注自动编号；脚注与旁注；页眉与页码。
- **样式基线**：`DesignTokens` 支持颜色多模式、scalar token、DTCG 风格导出；默认中文科普样式的段落度量、PageSetup 度量与组件外观已可通过 token / 样式模板联动，并保持 legacy `colors` / 旧 `.layoutd` 兼容。
- **AI / 模板**：规则型 `LayoutPlan` 候选 + 可插拔 `LayoutPlanProvider`（provider→规则回退）；页面级与章节级版式模板；项目内命名模板的保存、retarget、导入/导出。
- **预检**：元数据/结构/引用/素材/分页/版面/排印/目录多类问题；frame 级定位与 `suggestedFix`；保守自动修复（`autoFixKind`）；`exportReady` 与按 PRD 成功指标对齐的 `qualityMetrics`（页数、AI 计划采纳页数、自动初排页数、低 DPI / 缺图注命中、版面问题数）。
- **导出**：审校 PDF（页码范围、裁切线、校对网格）、页面 PNG（范围与倍率）、结构化 `.layoutd`、预检 JSON；CLI `--validate` 作为质量门，`--apply-preflight-fixes` 可在导出前应用保守修复。
- **IDML 主交付（阶段 E，已落地并经 InDesign 中文版验收）**：`BookProject → IDML` 全量映射（页/文本框/段落样式/颜色 token→Swatch/置入图打包重链/复合字体/竖排/避头尾禁则/行内粗斜/脚注/原生表格/动态目录 TOCStyle/非矩形蒙版/对开跨页），原生 `ZIPArchiveWriter` 打包（mimetype store-first），App/CLI 均有导出入口与选项面板。CJK 保真走「不变量断言闸 + InDesign 往返 oracle」两层守护（见 `docs/idml-oracle/FINDINGS.md`）。CMYK/PDF/X 交 InDesign，不自建。

## 当前验证状态

完整 Xcode 工具链下 `swift build` 与 `swift test` 均通过（测试数量以本机 `swift test` 实测为准，不在文档中固定数字以免漂移）。覆盖范围包括导入、分页、中文禁则与混排、AI provider 回退、各级版式模板、模板库导入导出、预检分类与自动修复、PDF/PNG/项目导出、CLI 质量门、版式计划校验回退，以及 IDML 导出的容器级断言与不变量闸（`scripts/review-idml.sh` 解包校验 `<Table>`/`<TOCStyle>`/PathGeometry 等结构）。

历史阻塞：机器仅装 Command Line Tools 时 `Foundation` / `PackageDescription` 出现 SDK 模块冲突。解决方式是安装完整 Xcode 并执行：

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
```

## 已知限制与技术债

- **前置页数量为固定假设**：内容引擎从第 1 页开始编号，再统一加 `frontMatterPageCount`（当前为 2：封面 + 单页目录）换算为绝对页码。该常量现已单点定义（`LayoutDEngine`），但仍假设前置页数量固定。一旦出现多页目录、扉页或版权页，需要由实际组装出的前置页推导该偏移，而不能继续用常量。
- **页眉几何为约定值**：`runningHeaderTopY` / `runningHeaderHeight` 为命名常量，尚未随样式系统参数化。
- **LayoutPlan 校验为结构性检查**：`planValidationFailures(_:)` 校验坐标、尺寸、引用与线程一致性，但尚未检查块之间是否相互重叠或与栏网格对齐——这类问题目前由导出前的版面预检兜底，而非在应用计划时拒绝。

## 下一步开发顺序

计划已围绕真实出版工作流与外部设计工具分工重组为"5 支柱 + 4 阶段"。**任务级拆解与状态以 [development-plan.md](development-plan.md) 为准**（另见 [layoutd-prd.md](layoutd-prd.md) 第 11 节、[design-tool-comparison.md](design-tool-comparison.md)）。下为架构视角的阶段顺序：

**阶段 A（地基，✅ 已完成）**
1. **样式基线 schema（P1）**：把 StyleLibrary/PageSetup/组件/模板统一成一套 DTCG 风格的 token + style 模型，作为导入/灌版/微调/预检的共同承载。（已实现）
2. **人工微调基石闭环（P4，最高优先级）**：编辑 → 捕获为 `LayoutPlan`/override → 引擎确定性重排 → undo/redo + 锁页；并展示相对自动排版的改动 diff（PRD 8.3/6.5）。（已实现）

**阶段 B（接口 + 护城河起步，✅ 已完成）**
3. **复合字体（合成字体）**：`ParagraphStyle` 从单一 `fontName` 扩展为按字符类（汉字/全角标点/半角标点/罗马字/数字/符号）映射字体+字号%+基线偏移，对标 InDesign 复合字体；影响每行混排正文，价值即时。（已实现）
4. **Figma/DTCG 样式导入（P2）**：依赖 P1 schema，把外部样张抽成样式基线。（已实现）
5. **AI 受控变体**：把 `planValidationFailures` 扩成"样式合规闸门"——只接受引用已批准 token/组件/网格的变体，从而在保持全书一致的前提下丰富单页视觉。（已实现）

**阶段 C（护城河纵深 + 美术层，✅ 已完成）**
6. **竖排（直排）**：纵向文本流、分页方向与 frame 几何；最大引擎改动，放在 A/B 稳定后。（已实现）
7. **两层模型**：为"固定美术页 / 置入装饰资产 / 非矩形蒙版"建一等承载，使满版图、扉页、扇面/印章等成品美术不进重排但可置入。（已实现）

**阶段 D（收尾 / 增强，✅ 已完成）**
8. `qualityMetrics` 接入可视化与历史追踪（已实现）；封面/满版图作固定页导出（已实现）；
   校对批注层（已实现）；DOCX 导入（已实现，用户视觉验收通过）。

**阶段 E（主交付路线：IDML 灌版交棒，✅ 核心已落地并经 InDesign 验收）**
9. **IDML 导出**（从阶段 D 的「结构参照」升级为一等导出格式）。最小验证 spike
   （`--idml-spike`）已在 InDesign 中文版人工验证通过（竖排/复合字体/图链/CMYK Swatch
   全 round-trip），随后落地正式的 `BookProject → IDML` 全量映射（`--export-idml`）：
   全量样式/颜色/图片打包重链/复合字体/竖排/避头尾/行内格式/脚注/原生表格/动态目录/
   非矩形蒙版/对开跨页，均经用户 InDesign 视觉验收。曾担心的 CJK 保真度风险已用
   「不变量断言闸 + InDesign 往返 oracle」两层守护化解（首战即修正了 CJK 排版器
   `Composer` 三处错误，见 `docs/idml-oracle/FINDINGS.md`）。CMYK/PDF/X 由 InDesign
   完成（不自建）。剩余可选增量：IDML-RNG lint（E1b③）、约物挤压/基线网格（E3-9）。

> 排版与中文（复合字体/竖排/禁则约物）必须是 layoutD 自有引擎——外部设计工具均不提供（见 [design-tool-comparison.md](design-tool-comparison.md)）。
