# layoutD 软件架构

状态：Draft  
日期：2026-06-15

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
  layout-advisor boundary; produces structured LayoutPlan candidates

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

### LaidOutDocument

排版引擎的输出结果，包含页面、页面框架和检查问题。UI 和 PDF 导出都依赖它。

## 首版实现状态

已搭建：

- Swift Package 工程骨架。
- macOS AppKit 应用入口。
- 三栏工作区：左侧项目/页面，中央画布，右侧检查器/AI 候选。
- App 可从命令行加载 Markdown 书稿：`swift run layoutD -- Samples/demo.md`。
- App 可无窗口导出审校 PDF：`swift run layoutD -- --export-pdf /tmp/layoutD-demo.pdf Samples/demo.md`。
- App 可无窗口导出结构化项目：`swift run layoutD -- --export-project /tmp/layoutD-demo.layoutd Samples/demo.md`。
- App 可打开和保存 `.layoutd` 项目文件。
- App 可通过 `File -> Export PDF...` 使用保存面板导出当前项目。
- App 可通过 `File -> Export Preflight Report...` 导出当前项目预检 JSON。
- App 支持画布缩放：Zoom In、Zoom Out、Actual Size、Fit Width。
- App 支持上一页/下一页导航，侧栏显示当前页。
- 结构化文档模型。
- 默认中文科普样章。
- 基于 Core Text 文本测量的分页引擎。
- 排版引擎会生成封面页、目录页、正文页，并按目录插入后的页码重排内容页。
- 排版引擎支持 `hero`、`comparison` 和 `span=wide` 触发的整版内容宽图片；跨栏图片会设置栏位阻隔线，避免后续右栏文字回到图片上方。
- 排版引擎会自动把超长正文/知识卡片跨栏拆分，避免生成超高文本框。
- 排版引擎会对标题执行 keep-with-next 规则，避免标题落在栏底而下一段正文进入下一栏。
- 排版引擎会自动给未编号图片图注加 `图1`、`图2` 这样的顺序编号。
- 规则型 LayoutPlan 候选生成器。
- Markdown 导入器，支持 front matter 图书元数据、标题、正文、引用、admonition 知识卡片、简单 pipe 表格、列表、图片引用、`span=wide` 图片提示、草稿分隔线/注释过滤和基础页面设置。
- front matter 可设置 `title`、`subtitle`、`author`、`publisher`、`isbn`、`series`、`keywords`、`columns`、`page`、`page_width_mm`、`page_height_mm`、`margins`、`gutter_mm`、`baseline_grid_pt`。
- 图片素材扫描器，读取尺寸、DPI 并推断图片角色。
- 图片目录可提供 `manifest.csv` / `assets.csv` / `images.csv`，按 `file,caption,role,span,credit` 合并图注、角色、跨栏提示和版权来源。
- 导入器只把 Markdown 明确引用的图片标记为已使用；素材目录中未引用的图片保留在素材库中供预检提示，不会被排版引擎自动插入正文。
- 画布和 PDF 导出会优先渲染已扫描到 `sourcePath` 的真实图片，缺失时回退到占位框；知识卡片会以带强调边的色块导出；PDF 会输出页码。
- 项目检查器会报告缺失章节、缺失正文、缺失图书元数据、ISBN-13 校验失败、未引用素材、缺失图注、预计印刷分辨率低、重复文件名、源文件缺失、缺版权来源和缺失素材引用。
- 版面预检会检查页码连续性，并用 CoreText 检查文本是否真实放入 frame，报告文本溢出、frame 重叠、越界、空文本 frame 和缺失图片 frame。
- 版面预检会基于 CoreText 实际分行检查第一层中文禁则，报告行首禁用标点和行尾开括号类标点。
- App 和 CLI 都可以生成结构化 JSON 预检报告：`swift run layoutD -- --preflight-report /tmp/layoutD-preflight.json Samples/demo.md`；报告包含 `exportReady`、素材摘要和版面 frame 统计。
- CLI 支持 `swift run layoutD -- --validate Samples/demo.md` 作为质量门：可导出返回 `0`，加载失败或存在 error 级预检问题返回非 0。
- 示例数据包含真实 PNG 图片：`Samples/images/cell-diagram.png`。
- PDF 导出边界。
- 基础测试用例。

## 当前验证状态

已安装并切换到完整 Xcode 后，SwiftPM 构建链路已经恢复。当前验证结果：

```text
swift build: pass
swift test: pass, 38 tests
Markdown -> PDF export: pass
Markdown -> .layoutd -> PDF export: pass
Markdown -> preflight JSON export: pass
CLI validate success/failure exits: pass
Wide image PDF page render: pass
Image manifest import: pass
Layout defect validation: pass
Text overflow validation: pass
Chinese line-break preflight: pass
Markdown knowledge-card import: pass
Heading keep-with-next layout: pass
Markdown draft-marker cleanup: pass
Callout PDF export: pass
Front matter margin/gutter import: pass
Page sequence preflight: pass
Layout frame summary: pass
Book metadata import and ISBN preflight: pass
Legacy .layoutd metadata decode: pass
Markdown table import and table frame layout: pass
```

曾经的阻塞是机器只使用 Command Line Tools 时，`Foundation` / `PackageDescription` 导入出现 SDK 模块冲突。解决方式是安装完整 Xcode，并执行：

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
```

## 下一步开发顺序

1. 增加 frame 选择、对象属性面板和手动换图能力。
2. 加入更完整的中文排版规则：避头尾、标点压缩、孤行/寡行控制。
3. 引入 AI provider 接口，让 `LayoutAdvisor` 可以基于章节语义生成多套版式候选。
4. 支持更丰富的导入格式：DOCX、章节级素材包。
5. 增加更完整的导出预检：目录一致性、页码一致性、文本溢出可视定位。
6. 增加可编辑版式模板和项目级样式配置。
