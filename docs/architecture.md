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
  -> CanvasView previews pages
  -> PDFExporter writes PDF
```

AI 不直接生成最终页面文件。AI 只生成 `LayoutPlan`：页面目标、策略、块类型、内容引用、相对位置和说明。`LayoutEngine` 负责把计划转换为实际页面框架，并检查是否可用。

## 核心模型

### BookProject

项目级对象，包含：

- `metadata`：书名、作者、时间。
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
- 结构化文档模型。
- 默认中文科普样章。
- 基于 Core Text 文本测量的分页引擎。
- 规则型 LayoutPlan 候选生成器。
- Markdown 导入器，支持标题、正文、引用、列表和图片引用。
- 图片素材扫描器，读取尺寸、DPI 并推断图片角色。
- 画布和 PDF 导出会优先渲染已扫描到 `sourcePath` 的真实图片，缺失时回退到占位框。
- PDF 导出边界。
- 基础测试用例。

## 当前验证状态

已安装并切换到完整 Xcode 后，SwiftPM 构建链路已经恢复。当前验证结果：

```text
swift build: pass
swift test: pass, 6 tests
```

曾经的阻塞是机器只使用 Command Line Tools 时，`Foundation` / `PackageDescription` 导入出现 SDK 模块冲突。解决方式是安装完整 Xcode，并执行：

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
```

## 下一步开发顺序

1. 修通本机 Xcode/SwiftPM 构建环境。
2. 把 `LayoutDEngine` 的估算文字高度替换为 Core Text 真实测量。
3. 把 App 接入 Markdown 文件打开流程，允许用户从真实书稿创建项目。
4. 增加第一个真实样章数据集。
5. 扩展画布交互：页面选择、frame 选择、缩放、网格显示开关。
6. 把 PDF 导出接入 App 菜单。
7. 把 AI `LayoutAdvisor` 从规则实现扩展成 provider 接口。
