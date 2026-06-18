# AI 设计工具选型对比（面向 layoutD 的样式基线导入）

状态：调研记录
日期：2026-06-18
评估视角：**不是"哪个 AI 稿子好看",而是"哪个工具的产物能被 layoutD 抽取为结构化样式系统(Variables/Components/Text Styles/Grid),并服务于印刷书内页(185×260 跨页、多栏、中文编辑排版)"。**

## 核心判断

评价轴两条：**(a) 产物是否机器可读、可治理的结构**(不是扁平像素或一次性代码);**(b) 这套结构能否表达印刷书内页语义 + 中文编辑级排版。**

反直觉但关键的事实：**几乎所有热门 AI 设计工具(Figma First Draft/Make、Stitch、v0、Lovable、Framer、Uizard、Visily、Magic Patterns)只做 app/web UI,没有印刷书内页模型**——没跨页、没母版、没串接文本框、没 CMYK。于是问题退化为两个子问题:① 用什么 AI **填 Figma**(它是唯一原生有结构 + 抽取栈的"基底");② **印刷内页语义和中文竖排谁负责**——Figma 给不了,InDesign(IDML)才有,而**最终分页与中文排版必须是 layoutD 自有引擎**。

## 对比矩阵（适配度针对 layoutD）

| 工具 | 主攻 | 结构化可抽取性 | 到 Figma/DTCG | 印刷书/跨页 | 中文编辑排版 | 适配度 |
|---|---|---|---|---|---|---|
| **Figma 原生栈** | app/web 设计系统 | 强(一等机器可读) | 原生最佳 | 弱 | 屏幕级,无竖排 | 中-高(作基底) |
| **Claude + Figma MCP** | 写原生 Figma 结构 | 最强写入 | 最佳 | 无 | 横排勉强,竖排不可靠,有丢字 bug | 高(仅 token/UI 侧) |
| **InDesign + Firefly** | 印刷/长文编辑 | 印刷最强(段/字/对象样式、母版、IDML 可抽) | 无(IDML 原生) | 完整专业 | 业界最强(竖排/禁则/约物) | 结构参照最佳;中文 AI 自动化弱、陆区不可用 |
| Figma First Draft | app/web UI | 真组件但用 Figma 自家库 | 落地后可抽 | 无(官方点名书籍不支持) | 无竖排 | 低 |
| Figma Make | prompt→React app | 弱(copy-as-layers=静态快照) | 代码非 token | 无 | 无 | 低/有误导 |
| Claude Artifacts/Design | UI/原型/SVG | Artifacts 孤岛;Design 出专有 bundle | 非 Figma 目标 | 弱 | 无保证 | 中(token/SVG 种子) |
| Google Stitch | app/web UI | DESIGN.md(DTCG 兼容 CLI) | 仅粘贴 Figma | 无 | 中文 prompt 常失败 | 低(token 种子) |
| v0 / Lovable / Framer | web app/网站 | 高但"错的结构" | 弱/无 | 无 | 无 | 低-极低 |
| Uizard / Visily / Magic Patterns | UI 线框/原型 | 半结构 | Figma 插件,无 DTCG | 无 | 无 | 低(仅封面探索) |
| **Recraft** | 矢量/插画/品牌资产 | 像素+矢量(非样式系统) | 出 SVG/PDF/TIFF 资产 | 印刷级资产 | 文字烤进图 | 资产引擎(封面/插图/图标) |
| Canva Magic Design | 营销/短印刷品 | 封闭模板 | 无,仅 PDF/PNG | 有限,非长书内页 | 消费级 | 半-不适配 |

## 分场景推荐

- **封面/装帧美术** → **Recraft**(矢量+印刷级+API),次选 Claude Artifacts 做技术性 SVG。当成品资产用,不从中抽样式。
- **内页视觉样式系统(要被 layoutD 抽取)** → 双轨分职责：
  - **Token/结构侧**：Claude + 官方 Figma MCP 写原生 Variables/Components/Grid → REST `/variables/local` + 社区工具导 **DTCG** → layoutD 抽取。（本组唯一现实的"原生可抽取"路径）
  - **印刷语义 + 中文侧**：以 **InDesign/IDML 为结构参照**,但分页与中文排版由 **layoutD 自有引擎**实现。

## 三条红线

1. **结构化是验收红线**：样张必须真有绑定的 Variables/Components/Text Styles/Grid;数值硬编码 = 抽取退化为"图层而非样式"。导入前校验 token 绑定率,不看渲染效果。
2. **UI 工具产物 ≠ 印刷书版式**：v0/Stitch/Framer 等再干净也是屏幕 UI 结构,套到书籍内页会在分页/跨页/多栏系统性崩塌。
3. **中文不能外包**：所有工具(含 Figma、含经 MCP 的 Claude)无原生竖排/禁则/约物;Figma 经 MCP 还有 CJK 变豆腐块的已知 bug。中文排版正确性必须由 layoutD 引擎保证。

## 一句话结论

**Figma 当"可抽取 token 基底"(Claude+MCP 写 → DTCG 抽),Recraft 当封面/插图资产引擎,InDesign/IDML 当印刷内页结构参照;跨页分页 + 中文编辑级排版必须是 layoutD 自有引擎——别指望任何 AI 设计工具替你做书。**

## 关键链接

- Figma REST(Variables 抽取)：https://developers.figma.com/docs/rest-api/
- 官方 Figma MCP：https://developers.figma.com/docs/figma-mcp-server/tools-and-prompts/
- Figma→DTCG 工具：https://www.npmjs.com/package/@tfk-samf/figma-to-dtcg
- Figma Make "copy as layers" 是静态快照(官方)：https://help.figma.com/hc/en-us/articles/35060759685015-Copy-a-Figma-Make-preview-as-design-layers
- First Draft 不适合书籍(官方)：https://help.figma.com/hc/en-us/articles/23955143044247-Use-First-Draft-with-Figma-AI
- Figma 竖排 CJK 仍是未满足需求：https://forum.figma.com/suggest-a-feature-11/east-asian-vertical-text-31111
- Google Stitch DESIGN.md(W3C-DTCG 兼容)：https://github.com/google-labs-code/design.md
