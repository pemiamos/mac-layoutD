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

### LaidOutDocument

排版引擎的输出结果，包含页面、页面框架和检查问题。UI 和 PDF 导出都依赖它。

## 首版实现状态

已搭建：

- Swift Package 工程骨架。
- macOS AppKit 应用入口。
- 三栏工作区：左侧项目/页面，中央画布，右侧检查器/AI 候选。
- 左侧侧栏包含章节、页面缩略图和素材库摘要；页面缩略图来自 `LaidOutPage` frame 分布，素材项显示角色、使用状态、像素尺寸、DPI 和图注。
- 右侧检查器可编辑素材角色、图注和版权/来源信息，修改后触发重排和预检刷新。
- 右侧检查器可编辑完整图书元数据（书名、副标题、作者、出版社、ISBN、丛书、关键词），并以毫米显示和修改页边距、栏间距，可切换对页排版。
- 右侧检查器可一键应用项目级样式模板：中文科普默认、紧凑学习手册、图像强化科普。
- 右侧检查器可选择章节、章节模板和起始页，将章节模板生成的 `LayoutPlan` 写入项目。
- 右侧检查器可按 severity 和 category 组合筛选预检问题，便于在导出前优先处理阻断项或集中处理元数据、素材、版面、排印等问题域。
- 画布支持点击选择 frame；右侧检查器可对选中 frame 做坐标和尺寸微调，并可为图片 frame 更换项目素材。手动编辑会被约束在页面范围内，并保留最小 frame 尺寸。
- 点击带 frame 定位的预检问题会滚动到对应页面、高亮并选中该 frame，问题列表同时显示 frame 类型、rect 摘要和可执行修复建议。
- App 可从命令行加载 Markdown 书稿：`swift run layoutD -- Samples/demo.md`。
- App 可从命令行或打开面板加载章节包目录，自动查找根目录 Markdown 并扫描 `images/` 或 `assets/`。
- App 可无窗口导出审校 PDF：`swift run layoutD -- --export-pdf /tmp/layoutD-demo.pdf Samples/demo.md`。
- CLI PDF 导出支持页码范围、裁切线和校对网格：`--pdf-pages 1,3 --pdf-crop-marks --pdf-grid-guides`。
- App 可无窗口导出页面 PNG 预览：`swift run layoutD -- --export-png /tmp/layoutD-pages Samples/demo.md`。
- PNG 预览导出支持页码范围和输出倍率：`--png-pages 1,3 --png-scale 1.5`。
- App 可无窗口导出结构化项目：`swift run layoutD -- --export-project /tmp/layoutD-demo.layoutd Samples/demo.md`。
- App 可打开和保存 `.layoutd` 项目文件。
- App 可通过 `File -> Export PDF...` 使用保存面板导出当前项目。
- App 可通过 `File -> Export PNG Previews...` 将页面导出为 `page-001.png` 等预览文件，并可设置页码范围和输出倍率。
- App 可通过 `File -> Export Preflight Report...` 导出当前项目预检 JSON。
- App 可通过 `File -> Import Layout Templates...` / `Export Layout Templates...` 导入和导出项目内保存的版式模板库。
- App 支持画布缩放：Zoom In、Zoom Out、Actual Size、Fit Width。
- App 支持上一页/下一页导航，侧栏显示当前页。
- 结构化文档模型。
- 默认中文科普样章。
- 基于 Core Text 文本测量的分页引擎。
- 排版引擎会生成封面页、目录页、正文页，并按目录插入后的页码重排内容页。
- 排版引擎支持 `hero`、`comparison` 和 `span=wide` 触发的整版内容宽图片；跨栏图片会设置栏位阻隔线，避免后续右栏文字回到图片上方。
- 排版引擎会自动把超长正文/知识卡片跨栏拆分，避免生成超高文本框。
- 排版引擎会对标题执行 keep-with-next 规则，避免标题落在栏底而下一段正文进入下一栏。
- 排版引擎会在相邻中文汉字与 ASCII 字母/数字之间自动补空隙，满足基础中西文混排规则。
- 排版引擎会自动给未编号图片图注加 `图1`、`图2` 这样的顺序编号。
- 样式系统包含 3 套项目级模板：中文科普默认、紧凑学习手册、图像强化科普，可一次性替换全书段落样式和颜色 token。
- 规则型 LayoutPlan 候选生成器，以及可接入本地/云端模型的 `LayoutPlanProvider` 边界、语义上下文摘要和 provider fallback advisor。
- Markdown 导入器，支持 front matter 图书元数据、ATX 1-6 级标题、Setext 1/2 级标题、正文、引用、admonition 知识卡片、简单 pipe 表格、无序/有序列表、inline/reference-style 图片引用、尖括号图片路径、单引号/双引号图片元数据、`credit/source/来源/版权` 图片来源别名、`span=wide` 图片提示、`anchor=previous` 段落图片锚定、草稿分隔线/单行与多行 HTML 注释过滤和基础页面设置；导入文本会清理常见行内 Markdown 标记，包括链接、强调、加粗、行内代码和转义标记，同时保留 `snake_case`、`3 * 4` 这类普通术语和公式符号。
- 项目加载器支持章节包目录：根目录可放 `manuscript.md` / `book.md` / `chapter.md` / `content.md` / `README.md`，也可用按文件名排序的 `chapters/*.md` 多文件章节流；素材目录可用 `images/` 或 `assets/`。
- front matter 可设置 `title`、`subtitle`、`author`、`publisher`、`isbn`、`series`、`keywords`、`columns`、`page`、`page_width_mm`、`page_height_mm`、`margins`、`gutter_mm`、`baseline_grid_pt`。
- 图片素材扫描器，读取尺寸、DPI 并推断图片角色。
- 图片目录可提供 `manifest.csv` / `assets.csv` / `images.csv`，按 `file,caption,role,span,credit` 合并图注、角色、跨栏提示和版权来源；章节级子目录也可拥有自己的 manifest。
- 导入器匹配图片引用时优先使用素材库完整相对路径，并兼容章节包中 `../assets/...` / `../images/...` 形式的引用，再用文件名兜底；只把 Markdown 明确引用的图片标记为已使用，素材目录中未引用的图片保留在素材库中供预检提示，不会被排版引擎自动插入正文。
- 画布和 PDF 导出会优先渲染已扫描到 `sourcePath` 的真实图片，缺失时回退到占位框；知识卡片会以带强调边的色块导出；PDF 会输出页码。
- 项目检查器会报告缺失章节、缺失正文、缺失图书元数据、ISBN-13 校验失败、未引用素材、缺失图注、预计印刷分辨率低、重复文件名、源文件缺失、缺版权来源和缺失素材引用。
- 项目检查器会报告重复使用图片，Markdown 导入器会在同一素材被多次引用时标记 `usage = repeated`。
- 版面预检会检查页码连续性，并用 CoreText 检查文本是否真实放入 frame，报告文本溢出、frame 重叠、越界、空文本 frame 和缺失图片 frame。
- 版面预检会检查目录条目引用页是否存在，并在可见标题页码和目录页码不一致或可见标题缺少目录项时给出导出前提示。
- 版面预检会基于 CoreText 实际分行检查共享中文禁则规则，报告行首禁用标点、闭合引号/括号和行尾开括号/开引号问题。
- App 和 CLI 都可以生成结构化 JSON 预检报告：`swift run layoutD -- --preflight-report /tmp/layoutD-preflight.json Samples/demo.md`；报告包含 `exportReady`、severity/category 聚合、素材摘要、版面 frame 统计、frame 级 `issueLocations` 定位信息和常见问题的 `suggestedFix` 修复建议。
- 可自动处理的预检问题会带 `autoFixKind`，Inspector 可一键应用保守修复：补占位出版社/关键词、移除无效 ISBN、按文件名补图注、补待确认来源、清除失效 sourcePath。
- CLI 支持 `--apply-preflight-fixes`，可在导出 `.layoutd`、PDF、PNG、预检 JSON 或执行 validate 前先应用同一套保守修复。
- CLI 支持 `swift run layoutD -- --validate Samples/demo.md` 作为质量门：可导出返回 `0`，加载失败或存在 error 级预检问题返回非 0。
- 页面级版式模板已经抽象为可复用目录，覆盖正文优先、图片主导、图文均衡和知识卡片页，并由规则版 layout advisor 直接复用。
- 章节级版式模板可以生成按页码索引的 `LayoutPlan` 集合，覆盖科普章节、图像密集章节和学习手册章节，可直接写入项目的 `appliedLayoutPlans`；App Inspector 和 CLI 都可以在导出项目前应用章节模板。
- 项目数据可以保存命名版式模板，并将已保存的 `LayoutPlan` retarget 到其他页面、跨页或章节目标复用；Inspector 页面控制区可以把当前页保存为模板，也可以应用、重命名和删除已保存模板。
- App 和 CLI 都可以把项目内已保存版式模板导出为独立模板库 JSON，也可以导入模板库并合并到当前项目。
- 示例数据包含真实 PNG 图片：`Samples/images/cell-diagram.png`。
- PDF 导出边界。
- PNG 页面预览导出边界。
- 基础测试用例。

## 当前验证状态

已安装并切换到完整 Xcode 后，SwiftPM 构建链路已经恢复。当前验证结果：

```text
swift build: pass
swift test: pass, 97 tests
Markdown -> PDF export: pass
Markdown -> .layoutd -> PDF export: pass
Multi-file chapter package -> .layoutd export: pass
Multi-file chapter package validate: pass
Chapter package asset reference matching: pass
Markdown -> PNG preview export: pass
Markdown -> preflight JSON export: pass
CLI validate success/failure exits: pass
Wide image PDF page render: pass
Image manifest import: pass
Nested chapter asset manifest import: pass
Layout defect validation: pass
Text overflow validation: pass
Chinese line-break preflight: pass
Chinese/Western text spacing: pass
AI provider advisor fallback and semantic context: pass
Project-level style templates: pass
Page-level layout templates: pass
Chapter-level layout templates: pass
CLI chapter template application: pass
Saved layout template reuse: pass
Layout template library import/export: pass
Preflight auto-fix entry: pass
CLI preflight auto-fix: pass
Preflight issue categories: pass
Markdown knowledge-card import: pass
Heading keep-with-next layout: pass
Markdown draft-marker cleanup: pass
Multi-line HTML comment cleanup: pass
Multi-line HTML comment CLI export: pass
Callout PDF export: pass
Front matter margin/gutter import: pass
Page sequence preflight: pass
Table-of-contents consistency preflight: pass
Layout frame summary: pass
Book metadata import and ISBN preflight: pass
Legacy .layoutd metadata decode: pass
Markdown table import and table frame layout: pass
Repeated image reference import and preflight: pass
Chapter package loader tests: pass
Duplicate nested asset basename import: pass
Exact nested asset path matching: pass
Nested chapter package asset CLI matching: pass
Nested Markdown heading import: pass
Nested Markdown heading CLI export: pass
Ordered Markdown list import: pass
Ordered Markdown list CLI export: pass
Inline Markdown cleanup import: pass
Inline Markdown cleanup CLI export: pass
Inline Markdown literal symbol preservation: pass
Markdown anchored image import: pass
Markdown anchored image CLI export: pass
Anchored image layout placement: pass
Single-quoted Markdown image metadata: pass
Angle-bracket Markdown image path import: pass
Inline image source metadata import: pass
Credited image preflight: pass
Setext Markdown heading import: pass
Reference-style Markdown image import: pass
Shortcut reference-style Markdown image import: pass
```

曾经的阻塞是机器只使用 Command Line Tools 时，`Foundation` / `PackageDescription` 导入出现 SDK 模块冲突。解决方式是安装完整 Xcode，并执行：

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
```

## 下一步开发顺序

1. 加入更完整的中文排版规则：标点压缩和跨页图文关系。
2. 支持更丰富的导入格式：DOCX 和章节包内更多资源类型。
3. 增加更完整的导出预检：更多可选修复策略和问题批处理工作流。
4. 增加可编辑版式模板：更多模板参数和模板库 UI 管理。
