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
- [ ] 在 `LayoutDCore` 定义统一 token 模型（color / spacing / typography），形如 DTCG（`$value`/`$type`/别名），支持**多模式**（章节主题色组：绿/蓝）。
- [ ] 重构 `StyleLibrary`：`ParagraphStyle` 等改为**引用 token**而非硬编码值。
- [ ] `PageSetup` 的网格/页边距/栏/基线纳入同一 schema。
- [ ] 形式化组件定义（知识卡片/边栏/图注）为样式化模板。
- [ ] `.layoutd` 持久化加 schema 版本号；保留旧档解码兼容。
- 验收：项目可序列化为 DTCG 风格 JSON；改一个 token → 全书联动重排；旧 `.layoutd` 仍可打开。
- 涉及：`LayoutDCore`（StyleLibrary/PageSetup/ProjectFile）。

### A2. P4 微调基石闭环（最高优先级）
- [ ] 统一"编辑捕获"为 override 模型（归并现有 `freezePageToPlan` + frame override）。
- [ ] undo/redo 栈（`AppState` 层，项目级快照或操作记录）。
- [ ] 锁页：`lockedPages` 接入 UI；重排时尊重锁定页不被破坏。
- [ ] 改动 diff：自动排版 baseline vs 当前 override 的可视化提示（PRD §8.3/6.5）。
- 验收：移动/缩放 frame→捕获 override→其余页确定性重排→撤销可回退→锁定页不受后续重排影响；能看出某页相对自动排版改了什么。
- 涉及：`LayoutDApp`（AppState/Canvas/Inspector）、`LayoutDEngine`（尊重锁定）。

---

## 阶段 B — 接口 + 护城河起步

### B1. 复合字体（合成字体）
- [ ] `ParagraphStyle` 从单一 `fontName` 扩展为"命名复合字体"：按字符类（汉字/全角标点/半角标点/罗马字/数字/符号）映射 字体 + 字号% + 基线偏移（对标 InDesign 复合字体编辑器）。
- [ ] 文本测量（CoreText）与 PDF/PNG/Canvas 渲染按字符类切字体；归并现有"中西文混排补白"。
- 验收：一行中英数字混排各用对应字体、对齐正确；样式切换全书生效。
- 涉及：`LayoutDCore`（ParagraphStyle）、`LayoutDEngine`、三处渲染器。

### B2. Figma/DTCG 样式导入（P2，依赖 A1）
- [ ] 定义导入映射：Figma Variables/REST 或 DTCG JSON → A1 的 token/style 模型；layout grid → PageSetup。
- [ ] 导入后"映射确认/补值"界面：显式处理有损项（基线网格、中文排版项）。
- [ ] token 绑定率体检：导入前报告"多少是 token/命名样式 vs 写死值"。
- 验收：一个结构良好的 Figma/DTCG 样张能导成可灌版的样式基线。
- 涉及：新 `LayoutDImport` 样式导入路径、`LayoutDApp` UI。

### B3. AI 受控变体（依赖 A1 + 校验扩展）
- [ ] 把 `planValidationFailures` 扩成"样式合规闸门"：拒绝引用非批准 token / 非样式库字体 / 非组件清单块的变体。
- [ ] 变体生成器在合规集合内产出多排布（丰富视觉、避免页页雷同）。
- 验收：生成的变体全部合规；越框变体被拒绝并回退。
- 涉及：`LayoutDEngine`、`LayoutDDesignAI`。

---

## 阶段 C — 护城河纵深 + 美术层

### C1. 竖排（直排）
- [ ] 纵向文本流、行进方向、frame 几何与分页方向；竖排禁则。
- 验收：能竖排一段引文/诗并正确分行分页。
- 涉及：`LayoutDEngine`、渲染器、`PageSetup`（排版方向）。

### C2. 两层模型（固定美术页 / 置入资产 / 非矩形蒙版）
- [ ] 一等"固定页/美术页"类型：不参与重排，承载满版图、扉页、封面。
- [ ] 置入装饰资产 + 非矩形图框蒙版（扇面/八边形）作图片处理选项。
- 验收：满版图整页与扇面图框能正确置入、导出，且不被重排打乱。
- 涉及：`LayoutDCore`（页/frame 模型）、`LayoutDEngine`、渲染器。

---

## 阶段 D — 收尾 / 增强

- [ ] `qualityMetrics` 接入可视化与历史追踪。
- [ ] 封面/满版图作固定页导出。
- [ ] IDML 结构参照（印刷/中文样式样板）。
- [ ] 校对批注层（不参与重排的 overlay）。
- [ ] DOCX 导入。
- [ ] 更完整印前（按需）。

---

## 维护约定

- 任务状态在本文勾选；PRD/architecture 不再重复任务级清单，只保留高层支柱并指向本文。
- 每完成一项，更新对应 ✅ 与 `architecture.md` 的"实现状态概览"。
