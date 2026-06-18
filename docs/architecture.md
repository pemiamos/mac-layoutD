# layoutD 软件架构

状态：Draft  
日期：2026-06-15（2026-06-18 修订）

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
  PDF export boundary; renders LaidOutDocument into PDF output
```

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

### LaidOutDocument

排版引擎的输出结果，包含页面、页面框架和检查问题。UI 和 PDF 导出都依赖它。

`PageFrame.kind` 携带语义角色（正文、图片、图注、呼应框、表格、脚注、旁注、页眉）。页眉使用独立的 `runningHeader` 类型，使“冻结当前页为模板”等工具可以按语义识别并排除页眉，而不再依赖其像素坐标。

## 实现状态概览

端到端闭环已经打通：Markdown / 章节包导入 → 素材扫描 → 确定性分页 → 画布预览 → `.layoutd` 保存 → PDF / PNG / 预检 JSON 导出，App 与 CLI 共用同一排版与预检管线。能力按模块归类如下（详细命令见 `README.md`，逐条功能与测试以代码和 `swift test` 为准，本文不再罗列流水账）：

- **导入**：front matter 元数据与页面设置；ATX/Setext 标题、正文、引用、知识卡片、表格、有序/无序列表、行内/引用式图片；图片元数据与 `manifest.csv`；章节包目录与多文件章节流；行内 Markdown 标记清理（保留术语/公式字面量）。
- **排版**：封面/目录/正文分页与目录页码重排；双栏中文版面；hero/comparison/wide 整版图与栏位阻隔；超长文本跨栏拆分；标题 keep-with-next；中西文混排补白；图注自动编号；脚注与旁注；页眉与页码。
- **AI / 模板**：规则型 `LayoutPlan` 候选 + 可插拔 `LayoutPlanProvider`（provider→规则回退）；页面级与章节级版式模板；项目内命名模板的保存、retarget、导入/导出。
- **预检**：元数据/结构/引用/素材/分页/版面/排印/目录多类问题；frame 级定位与 `suggestedFix`；保守自动修复（`autoFixKind`）；`exportReady` 与按 PRD 成功指标对齐的 `qualityMetrics`（页数、AI 计划采纳页数、自动初排页数、低 DPI / 缺图注命中、版面问题数）。
- **导出**：审校 PDF（页码范围、裁切线、校对网格）、页面 PNG（范围与倍率）、结构化 `.layoutd`、预检 JSON；CLI `--validate` 作为质量门，`--apply-preflight-fixes` 可在导出前应用保守修复。

## 当前验证状态

完整 Xcode 工具链下 `swift build` 与 `swift test` 均通过（当前测试套件含 124 个测试函数；以本机 `swift test` 实测为准，不在文档中固定数字以免漂移）。覆盖范围包括导入、分页、中文禁则与混排、AI provider 回退、各级版式模板、模板库导入导出、预检分类与自动修复、PDF/PNG/项目导出、CLI 质量门，以及版式计划校验回退。

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

1. **AI 改动的可见性与可逆性（最高优先级）**：让用户清楚知道某页相对自动排版被 AI/模板改了什么（diff），支持撤销，以及锁定已确认页面避免后续重排破坏。这是 PRD 第 8.3/6.5 节的核心体验，目前仅有“冻结当前页为模板”的雏形。
2. 加入更完整的中文排版规则：标点压缩和跨页图文关系。
3. 支持更丰富的导入格式：DOCX 和章节包内更多资源类型。
4. 增加更完整的导出预检：更多可选修复策略和问题批处理工作流；把 `qualityMetrics` 接入可视化与历史追踪。
5. 增加可编辑版式模板：更多模板参数和模板库 UI 管理。
