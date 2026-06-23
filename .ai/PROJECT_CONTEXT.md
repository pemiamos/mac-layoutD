# 项目总说明 PROJECT_CONTEXT

> 每个 AI 开工前先 `get_project_brief()` 读这份。保持精简，只放"不变的事实"。
> 易变的进度放 HANDOFF.md，不要写在这里。

## 项目目标
layoutD —— 一套 macOS 优先的、AI 辅助的中文科普图书排版系统。核心理念：以"结构化书籍工程"
而非"页面文档"为单位；确定性排版引擎负责文本/图片/图注/科普组件的成帧；AI 只产出经过校验的
结构化 `LayoutPlan` 候选（受控变体），不直接产出最终成品。

**主交付路线（2026-06-19 决策，见 DECISIONS.md）**：layoutD 定位收敛为"灌版引擎"——
把"Figma 视觉规范 + 内容"自动灌成高质量初排，**导出 IDML 交 InDesign 做人工精调 + 印前
输出**（单向流，交棒后 InDesign 为真理源）。layoutD 保留基本结构化编辑工具，但不扩建重型
自有编辑器；CMYK/PDF/X 不自建，交 InDesign（强化"印前路线 A"）。

## 技术栈
- 语言：Swift（swift-tools-version 5.9）
- 形态：Swift Package（可执行 `layoutD` + 多个库 target）
- 平台：macOS 14+（AppKit 桌面壳）
- 包管理：SwiftPM（无 npm/node）

## 目录结构（核心模块）
```
Package.swift            包定义
Sources/
  LayoutDCore/          文档模型、排版、资源、页面几何、LayoutPlan 类型
  LayoutDEngine/        确定性分页与成帧
  LayoutDDesignAI/      规则 + provider 的 AI 顾问边界，产出结构化 LayoutPlan 候选
  LayoutDImport/        Markdown 稿件导入与图片资源扫描
  LayoutDCheck/         工程与资源问题检查
  LayoutDExport/        导出边界：IDML（主交付）+ PDF / PNG / 预检 JSON
  LayoutDApp/           macOS AppKit 桌面壳（画布/侧栏/检查器/导出）
Tests/                  各模块单元测试
Samples/                示例稿件与资源
docs/                   设计与路线图文档
.ai/                    本协作工作台（见 AGENTS.md）
```

## 检查命令（走 run_checks 白名单）
- `build` → `swift build`
- `test`  → `swift test`

## 绝对不要碰的文件
- `Package.swift` 的 target/product 结构（动架构先 record_decision）
- `.build/`、`.manual-build/`（构建产物，不手改）
- 已校对的 `Samples/` 基准资源（改动需先 record_decision）

## 已知约束 / 当前痛点
- AI 输出必须是受控变体（结构化 LayoutPlan + override），不做自由绘制工具
- 编辑走 LayoutPlan/override 的两层模型；复合字体 + 竖排已实现
- 排版质量指标 / 历史追踪 / 全出血固定页导出 已落地
- **主交付改为导出 IDML 交 InDesign 精调 + 印前**：`--export-idml` 全量映射已落地并经
  用户 InDesign 中文版视觉验收（竖排/复合字体/避头尾/图链/表格/脚注/动态目录/蒙版/对开
  全部通过）；曾担心的 CJK 保真度风险已用「不变量断言闸 + InDesign 往返 oracle」化解
  （见 `docs/idml-oracle/FINDINGS.md`）。剩余可选：IDML-RNG lint、约物挤压/基线网格
