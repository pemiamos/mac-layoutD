# 任务队列归档（已完成项）

> 从 `.ai/QUEUE.md` 移出的已完成任务，一行一条。**完整任务描述/验收口径/踩坑记录**见 git 历史：
> `git show c1e2b28:.ai/QUEUE.md`（归档前最后一版全文）。此文件只做速查索引。

## 导入（IMP / D）

- [x] **IMP-1 多段 frontmatter 止血** — Codex `ac903f3`，合 dev+main(c19dd05)。段边界+全 key:value 双护栏，title→标题，其余键静默忽略。
- [x] **IMP-2 DOCX 内嵌图导入** — AG `3175bae`，合 dev+main(c19dd05)。rels 映射+w:drawing 解析+EMU 转换，真书稿 3 图验证。⚠️ 遗留：图片落 docx 旁 images/ 目录，宜改临时/工程目录。
- [x] **IMP-3 角色标签结构化导入** — Claude 接手完成合 dev(4507e65)。Codex 初版 4 真 bug 全修；标签零漏出、中文命名段落样式直通 InDesign。遗留：正文/标题全局默认字体仍 Songti/PingFang（牵动分页测试，单独一步）。
- [x] **D-2 DOCX 导入** — Codex `85d7a00`。OOXML→BookProject，粗斜体/列表/表格映射。

## IDML 导出（E2 / E3）

- [x] **E3-1 行内格式补全到所有 block** — Codex `8201059`。
- [x] **E3-3 傍点解析（含嵌套修复）** — Codex `dfd6ac8`。E3-3v 渲染验收 ⏹ 不再投入（用户 0621 决定，属性保留、InDesign 出点不追）。
- [x] **E3-7 脚注 → 原生 Footnote** — Codex `8be4467` + E3-7v 豆腐修复 Claude `d449077`（footnoteXML 引用带 CF_ 复合字体样式），用户视觉验收 PASS。
- [x] **E3-4 原生表格 Table** — Claude，合 dev(ae82104)，用户视觉验收 PASS。踩坑：网格估高/FirstLineIndent=0/底色挂单元格。
- [x] **E3-4b 表格单元格内行内格式** — 合 dev(fe31069)。tableCellRuns 并行字段。
- [x] **E3-6 目录动态化** — Codex `748c60c` + Claude 制表位修复 `9568de3`，用户 0623 验收 PASS（TOCStyle+点导引线+右对齐页码）。
- [x] **E2-5 非矩形蒙版** — Claude，合 dev(404596b)，用户 0623 验收 PASS（八角 8 点/扇面弧近似 PathGeometry）。
- [x] **E2-4 对开跨页** — Claude `02900eb`，用户验收 PASS（首页单独+左右镜像+订口在内）。
- [x] E2-1 图片打包 / E2-2 背景描边 / E2-3 禁则集 / E2-6 原生 zip / E2-7 GUI 导出入口 — 均 Codex，详见 development-plan.md E2 表。

## 预览/GUI（AG 道）

- [x] **E3-2 行内格式预览渲染** — AG `44e2873`；**校对批注层** — AG `374c28e`。
- [x] **E3-2b 竖排斜体 / E3-4p 表格网格 / E3-3p 傍点 预览** — AG，随 e3-10p merge `c5fcfb7` 合入，视觉验收过。
- [x] **E3-10p 预览验收 harness（--export-png-flow/--export-pdf-flow）** — AG `c056f88`，合 dev(c5fcfb7)。
- [x] **E3-6p 目录预览** — AG `d234d22`，合 dev(dad96a5)。
- [x] **E2-5p 蒙版预览** — AG `7f486ab`，合 dev(dad96a5)。
- [x] **E2-4p 对开预览（页码定位部分）** — AG `3f7a986`，合 dev(9497663)。⚠️ 左右页并排预览/版心镜像未做。
- [x] **导出选项面板** — AG `d4c647c`，合 dev(16c12c3)。

## Backlog / 插单

- [x] **B1 图文绕排预览** — AG `099f38b`，Claude 审核剔除误提交样张后合 dev(09b8cc4, 2026-07-04)。CoreText 挖洞排版+exclusionRects+三渲染器一致。PNG 样张确认绕图行变窄/图占区无字（~/Desktop/B1绕排验收-0704）。导出侧 TextWrapPreference 配对任务在 Claude 道。
- [x] **基础工具可用性热修（GUI）** — Codex `783f96f`，合 dev(9773fe7)。拖拽本地预览/Direct Selection select-only/Inspector 文字编辑/删假渐变。**待用户 GUI 视觉复验后合 main。**
- [x] **行内格式 阶段1** — `b26e1ca`→`9e4f269`，合 dev(b4adf8d)。等用户 InDesign 最终视觉确认（非阻塞）。

## 基础设施

- [x] **真正 CI** — `.github/workflows/ci.yml`（2026-06-23）：push/PR 自动跑 review-idml.sh（macOS runner）。
- [x] **文档同步** — development-plan.md E0/D-2/E1b 回填（Claude 2026-06-23）。
