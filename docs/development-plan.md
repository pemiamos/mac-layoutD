# layoutD 开发计划（执行权威）

状态：Living（本文件是执行计划的唯一权威；PRD 管需求，本文管落地）
更新：2026-06-18

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
- [ ] 校对批注层（不参与重排的 overlay）。
- [ ] DOCX 导入。

---

## 阶段 E — 主交付路线：IDML 灌版交棒（进行中）

> 决策见 `.ai/DECISIONS.md`（2026-06-19）：layoutD 收敛为「灌版引擎」，主交付改为
> 导出 IDML 交 InDesign 做人工精调 + 印前。原阶段 D 的「IDML 结构参照」「更完整印前」
> 两项被本阶段取代/吸收——印前（CMYK/PDF/X）确定交 InDesign，layoutD 不自建。

### E0. 最小验证 spike（先行证伪，别先动架构）
- [ ] `--idml-spike <path>`：生成只含「一个跨页 + 一个中文段落样式文本框 + 一个竖排
      文本框 + 一张置入图 + 一个 CMYK Swatch」的 IDML。
- 验收：在 **InDesign 中文版** 干净打开，样式/图链/颜色/竖排都在。
- **重点压测竖排**——这是唯一可能让整条路线崩掉的地方，最先证伪。
- v1 先验证基础包有效性 + 竖排；**v2 再压测复合字体**（合成字体落 IDML 的保真）。
- 涉及：`LayoutDExport`（IDML 生成）、`LayoutDApp`（CLI 入口）。

### E1. BookProject → IDML 全量映射（spike 通过后）
最小可用版已落地并在 InDesign 中文版**人工终验通过**（`--export-idml PATH`，`Sources/LayoutDExport/IDMLExporter.swift`）：
- [x] 页 → Spread/Page（单页 spread）；文本框 → TextFrame/Story；段落样式 → ParagraphStyle。
- [x] 颜色 token → RGB 色板；置入图 → Rectangle+Image+Link。
- [x] 复合字体 → Fonts.xml 内 CompositeFont；竖排 → Story `StoryOrientation=Vertical`。
- [x] 字体匹配：CoreText 取真实 FontType（系统 CJK 是 OpenTypeCID 非 CFF）+ PostScript 名 → InDesign 无缺失字体。
- [x] 非对开干净分页：`PagesPerDocument="1"`（恒为 1，非实际页数）+ `FacingPages="false"` + spread 纵向偏移 → 无空白页、主页单页。
- [x] 容器级自动验证（IDMLExporterTests）+ demo.md 端到端导出、全 XML well-formed、InDesign 4 页内容全正确。
后续增量：
- [ ] 对开跨页（facing spread）；固定美术页 → MasterSpread；非矩形蒙版。
- [ ] 避头尾 → 禁则集；组件背景/描边（知识卡片等）；字体「家族+样式名」拆分（PingFang SC Semibold 等）。
- [ ] 图片打包（IDML + Links 文件夹）与相对路径重链。
- [ ] 首页幻影（起始页码=2 的 Section）；spike 的 /usr/bin/zip 换原生 zip 写入。
- 验收：一份真实 demo 项目导出的 IDML 在 InDesign 打开后版面与 layoutD 预览一致到「可微调」程度。
- 注意：单向流，不做 IDML 回导；交棒后 InDesign 为真理源。

---

## 维护约定

- 任务状态在本文勾选；PRD/architecture 不再重复任务级清单，只保留高层支柱并指向本文。
- 每完成一项，更新对应 ✅ 与 `architecture.md` 的"实现状态概览"。
