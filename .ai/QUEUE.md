# 任务队列 Task Queue（Codex / Antigravity 自助接力用）

> 目的：让开发更自动化。两边都不必每轮等 Claude 手喂任务——读本文件，领**自己道里**最上面未打勾的任务做。
> Claude 维护本队列与每项的「目标/文件/验收」；攒一批分支后 Claude 批量审核，不再一个一个提交、一个一个审。
> 两道按文件边界分工，正常不会改到同一文件；真出现冲突按下方「认领协议」处理。

## 工作副本隔离（2026-06-21 起）

三个 AI 各有物理隔离的工作副本（git worktree，共享同一个 `.git`）：
**Codex → `/Users/amos/Documents/GitHub/mac-layoutD-codex`（停靠 `codex-lane`）**；
**Antigravity → `/Users/amos/Documents/GitHub/mac-layoutD-ag`（停靠 `ag-lane`）**；
**Claude → 主仓库 `mac-layoutD`（集成区，`dev`/`main`）**。
开工先确认 shell 在自己的副本里。详见 `.ai/AGENTS.md` 顶部「工作副本隔离」。

## 🔁 连续作业模式（用户 2026-06-21 明确要求，最高优先）

**用户已预先授权整条队列，连续干，不要停下来问确认。**
- 一次被唤起后，**连做多个任务、连续作业约 1 小时**，做完一个**自己审核**（`scripts/review-idml.sh` PASS）就**直接接下一个**，不要每做完一个就停下等用户点"Proceed"/回话确认。
- **Antigravity 注意**：你的 IDE 若弹"计划审批/Proceed"，**本队列就是审批**——视同已批准，直接开干，别等用户点。不要写一份 plan 然后停下问，要边做边交付。
- 自审标准：每个任务 `run_checks()` + `scripts/review-idml.sh` 必须 PASS 才提交；FAIL 就**自己修**，修不动再在 handoff 里记下精确 repro 并跳到下一个能做的任务，**不要因此整体停摆**。
- 一轮结束（约 1 小时 / 做完本批序列 / 撞到真阻塞）时，写**一条汇总 handoff**列出这轮所有 commit，不必每个任务一条。
- **绝不碰 dev/main**：你们只在自己的 feature 分支提交，合 dev/main 是 Claude 的事。也**不要声称自己合并了 main**（之前出现过误报）。

## 流程铁律（每一棒都照做）

**Codex / Antigravity（执行）每领一个任务：**
1. 确认在**自己的副本目录**里（Codex=`…-codex` / AG=`…-ag`）。`read_latest_handoff()` + 读本文件，领**自己道**里最上面未打勾任务。
2. 把该行 `- [ ]` 改成 `- [~] 认领: <你的名字> @ <分支名>`（挂牌，避免撞车），随手改一起带上。
3. 在停靠分支上 `git fetch && git merge origin/dev` 同步最新 dev，再起 `feature/codex-<task>` 或 `feature/ag-<task>` 分支。
   **每个新任务都从最新 dev 起新分支**，别在旧分支上叠（旧分支可能含已被取代的提交）。
4. 实现 + 写**端到端验收**（不能只靠单测——本项目踩过「单测全绿但功能坏」的坑）。
5. **必须** `bash scripts/review-idml.sh` 本地 PASS 后才提交（这就是 Claude 审核要跑的同一套）。
6. commit（feat/fix 规范）到**自己的 feature 分支**+ 把该行改成 `- [x]`（注明 commit hash）。
   **不合 dev、不必 push**——共享 `.git`，Claude 本地直接看得到你的分支。
7. **直接接下一个任务**（见「连续作业模式」），不要停下问确认；一轮收尾写一条汇总 `write_handoff`。

**Claude（集成）批量做：**
1. 在主仓库里，攒几个 `feature/codex-*` / `feature/ag-*` 分支一起审，不逐个来回（共享 `.git`，无需等对方 push）。
2. 每个分支跑 `scripts/review-idml.sh`：全绿才算过；有 FAIL 把精确 repro 退回交接。
3. 过的合进 `dev` 集成分支（不直接进 main）；`.ai/HANDOFF.md` 等交接日志的合并冲突由 Claude 集中解决。
4. `dev` 攒一批后交用户在 InDesign/GUI 做**视觉验收**（无头验证不了渲染对错，这关必须人看）。
5. 验收 OK → Claude 合 `dev` → `main` 并 push；验收有问题 → 直接在 Claude 这边改。

**认领协议（避免两道撞同一文件）**：两道文件边界天然不重叠（见下方"负责文件"）。如果某任务臨时需要碰对方道的文件，先在本文件该任务下加一行「⚠️ 跨道改 `<文件>`，已知会 <对方>」再动手。

---

## 进行中 / 待集成

- [x] **行内格式 阶段1**（粗体/斜体 → IDML CharacterStyleRange，含 CJK 单分隔符）
  — commit `b26e1ca`→`9e4f269`(CJK 修复)，已合并 `dev`（`b4adf8d`）。
  结构层 `scripts/review-idml.sh` 全绿（mimetype/XML/FontStyle 断言全过）；
  **等用户在桌面打开导出样例做最终 InDesign 视觉确认**（非阻塞，可继续后续任务）。

---

## Codex 道队列（IDML 导出管线 + 内容模型）

> 负责文件：`Sources/LayoutDImport/*`、`Sources/LayoutDCore/BookProject.swift`、
> `Sources/LayoutDExport/IDMLExporter.swift`、`ZIPArchiveWriter.swift`
>
> **🔁 本批连续序列（2026-06-21 用户排期，按顺序连做，做完一个自审 PASS 就接下一个，不停下问）：**
> **E3-4b 表格内行内格式 → E3-6 目录动态化 → D-2 DOCX 导入 → E2-5 美术页/蒙版**。
> ⚠️ **E2-4 对开跨页改由 Claude 做**（用户 2026-06-21 决定），不在 Codex 序列里——但它和上面几项同改 `IDMLExporter.swift`，Claude 会等本批这几项先合进 dev 再起手，避免同文件并行冲突。
> ⏸ **E3-8 CMYK 暂缓**（用户决定先不做）；E3-9 约物挤压维持原排期，不在本批。
> 约 1 小时或做到这批做完/撞阻塞为止，收尾写一条汇总 handoff。注意斜体导出已用 `Skew="12"`、
> 粗体用 `FauxBold="true"`（别用 `FauxItalic` 或 `FontStyle` 字符串，已验证那两个对 CJK 不可见/出粉色替代字形）。

- [x] **E3-1 行内格式补全到所有 block** — Codex @ `feature/codex-inline-blocks`, commit `8201059`
  - 目标：当前只普通正文段落持久化 inlineRuns；扩到标题/列表/引用/callout。先抽一个统一的 `Paragraph` 构造 helper，再让所有 Markdown block 分支走它。
  - 文件：`Sources/LayoutDImport/MarkdownBookImporter.swift`、`Sources/LayoutDCore/BookProject.swift`(如需)。
  - 验收：`printf '## **粗**标题\n\n- 列表*斜*项\n> 引用**强调**\n'` 导出 IDML 后，标题/列表/引用里的强调都出对应 FontStyle；`scripts/review-idml.sh` PASS。

- [x] **E3-3 傍点（Kenten 着重号）** — Codex @ `feature/codex-e3-3-kenten`, 修复 commit `dfd6ac8`
  - 目标：`InlineEmphasis.kenten` 落地——`==着重==` → kenten run → IDML `KentenKind` 属性。
  - 文件：`MarkdownBookImporter.swift`（语法解析）、`IDMLExporter.swift`（IDML 属性输出）。
  - ✅ **已对的部分**：纯 `==着重==`（不嵌套）在标题/列表/引用/callout/正文里都正确出 `KentenKind="KentenSesameDot"`；ASCII `a==b` 不误判；`scripts/review-idml.sh` PASS（183 测试）。
  - ❌ **退回原因（Claude 复审实测，commit `27b5578`）**：傍点与 `*`/`**` **嵌套**时解析器状态错乱。repro：
    `printf '一 ==**A**== 二 **==B==** 三 ==*C*== 四 *==D==* 五。\n' | 导出 IDML`，解包查 Story：
    - `==**A**==`（傍点套粗）：❌ 漏出字面 `*`，A 变成 `Skew`(斜体) 不是 `FauxBold`，且**斜体污染到后面的"二""三"**（plain 文字被加了 Skew）。
    - `**==B==**`（粗套傍点）：⚠️ B 多带了不该有的 `Skew`。
    - `==*C*==`（傍点套斜）：❌ 导出成 `C*`，字面星号粘在内容里。
    - `*==D==*`（斜套傍点）：✅ 正确（`Skew`+`Kenten`）。
    根因方向：`isValidInlineDelimiter` 的 CJK flanking 判定在 `==` 被消费后，对紧跟的 `**`/`*` 开/闭判定失误，导致 `**` 降级成单 `*` 斜体、配对错位、状态泄漏到段落后续。
  - **修复验收**：上面 4 种嵌套写法导出后，A=粗+傍点、B=粗+傍点、C=斜+傍点、D=斜+傍点，**均无字面 `*` 残留、无 emphasis 渗染到相邻 plain 文字**；补这 4 个端到端断言；`scripts/review-idml.sh` 仍 PASS。修好后用户再在 InDesign 肉眼确认傍点显示。
  - ✅ 嵌套解析 bug 已修（`dfd6ac8`），但见下方 **E3-3v**：傍点视觉首次人工验收**没出点**。

- [~] **E3-3v 傍点在 InDesign 实际渲染（视觉退回）** — Claude 直接改 @ dev commit `8ce89a8`（代码已落，待用户视觉复验）
  - ❌ **退回原因（2026-06-21 用户 InDesign 首次肉眼验收 `~/Desktop/layoutD傍点嵌套验收-0621.idml`）**：粗体/斜体都正常（C/D、内质网、高尔基体可见倾斜），但**着重号（傍点/芝麻点）整页一个都没画出来**——含纯傍点对照「重点内容」也无点。即 `KentenKind="KentenSesameDot"` 属性写进了 Story XML（解包可见），InDesign 却完全不渲染。这是「属性在、视觉无」的同类坑（参考当年 FontStyle→FauxBold）。
  - **根因方向（Claude 已勘，强线索待 Codex 验证）**：导出的 `<ParagraphStyleRange>` **从不写 `AppliedComposer`**（`IDMLExporter.swift:675` 只有 `AppliedParagraphStyle`）。**Kenten/着重号是 CJK 排版特性，InDesign 仅在段落使用 World-Ready / 日文段落排版器时才绘制**；默认拉丁 composer 下 `KentenKind` 被静默忽略 → 中英文都不出点，与现象吻合。
  - 文件：`IDMLExporter.swift`（段落/样式输出）、可能 `Styles.xml` 段落样式定义。
  - **修复方向**：给正文段落（至少含 kenten run 的段落，建议全体 CJK 段落）设 World-Ready 段落排版器。IDML 中即 `AppliedComposer`，候选值需 Codex 对照真·InDesign 存盘的 IDML 确认确切字符串（如 `$ID/Adobe Japanese Paragraph Composer` 或 `HL Composer J` 一类；别凭记忆硬写，写错 InDesign 会回退默认 composer 等于没改）。如仅 composer 仍不出点，再排查是否缺 `KentenFontSize`/`KentenCharacterSet` 等次要属性。
  - **验收**：① 重新导出本验收样例，**用户在 InDesign 肉眼确认 A/B/C/D 与「重点内容」逐字带着重点、普通字无点**（这关必须人看，无头测不出渲染对错）；② `scripts/review-idml.sh` 仍 PASS；③ 补端到端断言：Story 段落带正确的 `AppliedComposer`。⚠️ composer 改了别破坏已验收的横排断行/避头尾。
  - 备注：E3-3 的解析 commit `dfd6ac8` 不回滚（嵌套已对、属性无害）；本项只补 composer 让属性真正生效。
  - ✅ **2026-06-21 Claude 已实现（dev `8ce89a8`）**：给每个 `<ParagraphStyleRange>` 写 `AppliedComposer="$ID/HL Composer Optyca"`（World-Ready 段落排版器），补端到端断言（每段都带该 composer）；187 测试 + review-idml.sh PASS。⚠️ composer 确切字符串取自 IDML 公开资料、**非真·InDesign 存盘比对**，已导两个变体给用户对比验收：`~/Desktop/傍点验收A-WorldReady排版器.idml`(`$ID/HL Composer Optyca`) 与 `~/Desktop/傍点验收B-日文排版器.idml`(`$ID/HL Composer J`)。待用户回报哪个出点：A 出点→保持；B 出点→把常量 `appliedComposer` 改成 `$ID/HL Composer J` 同步断言；都不出→另查 KentenFontSize 等。
  - ⚠️ **与 E3-7 冲突预警**：本项已改 `IDMLExporter.swift`（dev `8ce89a8`），Codex 正在同文件做 E3-7——Codex 提交前务必 `git merge origin/dev` 同步本 commit，解决段落输出处的冲突。

- [x] **E3-7 脚注 → IDML** — 原生 Footnote 机制（codex `8be4467`）+ E3-7v 豆腐修复（claude `d449077`）已合 dev（merge `3934160`）。用户 InDesign 视觉验收 PASS（脚注中文正常、自动编号）。
  - 目标：`anchoredFootnoteIds` 映射到 IDML 脚注（Footnote 元素），而非当前的纯文字处理。
  - 文件：`IDMLExporter.swift`（仅导出侧；导入侧已就绪，别动）。
  - 起手提示（Claude 已勘）：**导入侧已经做好了**——`MarkdownBookImporter` 解析 `[^id]` 标记、收集定义、`postProcessFootnotesAndSideNotes()` 分配编号、把锚段的 `anchoredFootnoteIds`(`BookProject.swift:293`) 填好，并把脚注内容作为 `kind: .footnote(number:)` 段落（`styleId:"footnote"`）追加到 story 末尾。目前 IDMLExporter 把这些当普通段落画成裸文字。本项要做的是：在导出锚段时，对其每个 `anchoredFootnoteIds`，在对应锚点位置写出 InDesign `<Footnote>` 元素（内含 `<ParagraphStyleRange>/<CharacterStyleRange>/<Content>` 的脚注正文），并**不再**把那条 `.footnote(number:)` 段落作为正文裸段输出（避免脚注内容在正文里重复出现一次）。InDesign IDML 脚注的 XML 形态可对照官方 IDML 规范的 `Footnote` 元素（自动编号靠文档级 `<FootnoteOption>`，单个脚注不用自己写号）。
  - 验收：`printf '正文一句话[^a]。\n\n[^a]: 这是脚注内容。\n'` 导出后，①InDesign 打开识别为真脚注（正文出上标编号、页脚出脚注正文、自动编号），不是裸文字；②正文里**不**再出现重复的脚注正文裸段；③`scripts/review-idml.sh` 仍 PASS，并补一条端到端断言（story XML 里出现 `<Footnote` 元素、且脚注正文不再作为独立正文段重复）。
  - ⚠️ 端到端验收必须解包 IDML grep `<Footnote`，别只靠单测——本项目踩过「单测绿但功能坏」的坑。

- [x] **E3-7v 脚注正文在 InDesign 渲染（视觉退回）** — Claude `d449077`，已合 dev（merge `3934160`）。**用户 0621 InDesign 视觉复验 PASS：脚注中文正常显示、无豆腐**。根因+修复见下（留档）
  - **现象**（用户 0621 InDesign 肉眼验收 `~/Desktop/layoutD脚注验收-0621.idml`）：原生脚注机制成立——正文锚点自动编号 1/2、页底有分隔线+脚注区、无重复。**但脚注正文里的中文全是缺字方框（豆腐 ☒☒☒），只有 `ATP` 等拉丁字符正常**。
  - **repro**：`printf '细胞是生命的基本单位[^a]。\n\n[^a]: 细胞由细胞膜、细胞质和细胞核构成。\n'` → 导出 → 解包 → 脚注区中文不显示。
  - **根因（两段断链，Claude 已勘）**：
    1. 脚注段没有专属段落样式：`StyleID` 枚举只有 `body/heading1/heading2/caption/callout`，**无 `footnote`**；导入器却把脚注段建成 `styleId:"footnote"`（`MarkdownBookImporter.swift:411`）。导出器仅遍历 `project.styles.paragraphStyles` 生成样式 → Styles.xml 里**没有 `ParagraphStyle/footnote`**，也就没有 `CF_footnote` 复合字体。
    2. `footnoteXML`（`IDMLExporter.swift:789`）把脚注的 `AppliedParagraphStyle` 硬编码成 `ParagraphStyle/$ID/[No paragraph style]`（无 AppliedFont）。正文段引用的是带 `CF_body` 复合字体的 `ParagraphStyle/body`，所以正文中文正常、脚注中文退回拉丁默认字体变豆腐。
  - **修复方向**（仅导出侧）：让脚注的 `<ParagraphStyleRange>` 引用一个带中文复合字体（`CF_*`）的段落样式。最稳：引用已存在的 `ParagraphStyle/body`；更规范：注册一个脚注专属小字号段落样式（可基于 caption）并引用之。务必确认被引用的样式真的在 Styles.xml 里生成（带 `CF_` AppliedFont），别再指向 `[No paragraph style]`。
  - **✅ 已修（Claude，commit `d449077`）**：footnoteXML 改为按 caption→body→空样式 的优先级引用带 `CF_` 复合字体的样式（caption 8.5pt/无首行缩进，最像脚注），footnoteStyleRef 一路 thread 进 storyXML→characterStyleRanges→footnoteXML。解包验证脚注现挂 `ParagraphStyle/caption`（带 `CF_caption`）。补了端到端断言（脚注样式不得 `[No paragraph style]`、须带 `CF_`）。swift test 188/0、review-idml.sh 6/0 PASS。**待用户 InDesign 肉眼确认脚注中文无豆腐**。
  - **验收**：①补端到端断言——解包后脚注 `<Footnote>` 内的 `<ParagraphStyleRange AppliedParagraphStyle=...>` 必须指向带 `CF_` 字体的样式、**不得**是 `$ID/[No paragraph style]`；②`scripts/review-idml.sh` 仍 PASS；③Claude 复审后重导样例投桌面，用户在 InDesign 肉眼确认脚注中文正常显示（无豆腐）。
  - ⚠️ 与 dev 的 E3-3v(composer 改 `storyXML` ParagraphStyleRange 行) 同文件，**合 dev 前** `git merge origin/dev` 同步并 reconcile（E3-7v 改了 storyXML 签名+正文调用处，E3-3v 改了同函数的 ParagraphStyleRange 行，会冲突需人工合）。

- [x] **E3-4 原生表格 Table** — Claude 实现，已合 dev（merge `ae82104`）。**用户 InDesign 视觉验收 PASS**（真表格、可选格、左对齐、底色贴合、无溢流）。链路：Paragraph.tableCells 结构化行列 → 导入保留 → LayoutEngine 网格估高 → 导出原生 `<Table>/<Column>/<Row>/<Cell>`（首行表头、列宽均分、0.5pt 边框、单元格左对齐去缩进、底色挂单元格）。迭代踩坑留档：①首版框按拍平文本测高→整表溢流，改 estimatedTableHeight 网格估高修复；②单元格继承正文 FirstLineIndent=21 显得右对齐，改 FirstLineIndent=0+LeftJustified；③整框填色露底部色块，改挂单元格 FillColor。
  - 目标：table 从「拍平成纯文字导」升级为 IDML 原生 `<Table>/<Row>/<Column>/<Cell>`（行列/边框/底色），InDesign 里是真表格、可调列宽。
  - **起手提示（Claude 已勘，先 `git merge origin/dev` 拿 E3-7 合并后的 IDMLExporter，已变）**：
    - ⚠️ **当前是有损的**：`MarkdownBookImporter.flushTableBuffer()`（`MarkdownBookImporter.swift:252`）其实**已经算出了结构化 `rows: [[String]]`**，却又用 `rows.map{ $0.joined(separator:"    ") }.joined(separator:"\n")` **拍平成一个纯文本字符串**塞进 `Paragraph(kind: .table, text:…)`。模型里**没有行列维度**——导出侧拿不到结构，只能当文字画。
    - 因此本项是**贯穿 模型→导入→布局→导出 的链路改造**（都在 Codex 道：BookProject.swift / MarkdownBookImporter.swift / IDMLExporter.swift）：
      1. **模型**：给表格加结构化承载。建议在 `Paragraph` 上加可选 `tableCells: [[String]]?`（Codable，旧文件 decode 为 nil 不破坏），`kind: .table` 时填充；`text` 可保留作降级/预览用。
      2. **导入**：`flushTableBuffer` 不再拍平，把 `rows` 原样存进 `tableCells`（注意每格仍走 `normalizeInlineMarkdown` 以便日后行内格式；表头行可记一个 `headerRows=1`）。
      3. **布局**：`LayoutEngine` 目前把 `.table` 段当文字测高；先保证不崩（可继续用 text 占位测高），IDML 路径用结构出真表格。真·网格预览是 AG 道 E3-4p，别在本项碰渲染层。
      4. **导出**：`IDMLExporter` 对 `.table` 段输出 InDesign `<Table ColumnCount=… RowCount=… HeaderRowCount=…>`，逐格 `<Cell Name="i:j" …><Content>…</Content></Cell>`；列宽先均分（页宽/列数），边框/底色给个朴素默认（可后续迭代）。Cell 内文字复用既有 `characterStyleRanges`，并和正文一样带 `AppliedComposer`。
    - IDML Table 的 XML 形态对照官方 IDML 规范的 `Table`/`Cell` 元素；Table 嵌在某个 Story 的 `<ParagraphStyleRange><CharacterStyleRange>` 里通过 `<Table>` 子元素承载，单元格 `Name` 为 `"行:列"`。
  - 文件：`Sources/LayoutDCore/BookProject.swift`、`Sources/LayoutDImport/MarkdownBookImporter.swift`、`Sources/LayoutDExport/IDMLExporter.swift`。
  - 验收：①`printf '| 名称 | 功能 |\n| --- | --- |\n| 线粒体 | 产能 |\n| 核糖体 | 合成蛋白质 |\n'` 导出后**解包 grep `<Table` / `<Cell`** 确认是原生表格（不是一段裸文字），列数=2、行数=3（含表头）；②补端到端断言（Table/Cell 元素数、单元格文本归位、无「4 空格拼接」残留）；③`scripts/review-idml.sh` 仍 PASS；④用户在 InDesign 打开确认是可选列、可调宽的真表格。
  - ⚠️ 端到端验收必须解包 IDML grep `<Table`/`<Cell`，别只靠单测——本项目踩过「单测绿但功能坏」的坑。

- [ ] **E3-4b 表格单元格内行内格式**（E3-4 遗留缺口，优先级中高）
  - 背景：E3-4 原生表格已落地，但 `IDMLExporter.tableStoryXML` 逐格调 `styledCharacterRanges(for: content, globalStart: 0, inlineRuns: [])` —— **inlineRuns 写死成空**，即表格单元格里的粗体/斜体/傍点（`**`/`*`/`==`）目前全部丢失，只出纯文字。
  - 目标：表格单元格继承行内格式。需链路：① 模型 `Paragraph.tableCells` 从 `[[String]]` 升级为可携带 per-cell inlineRuns（如 `[[TableCell]]`，TableCell={text, inlineRuns?}），旧文件 decode 兼容；② 导入 `flushTableBuffer` 每格解析 `inlineRuns`（复用 `normalizeInlineMarkdown` 的 run 提取）；③ 导出 `tableStoryXML` 把该格 inlineRuns 传进 `styledCharacterRanges`。
  - 文件：`BookProject.swift`、`MarkdownBookImporter.swift`、`IDMLExporter.swift`。
  - 验收：`printf '| 名称 | 说明 |\n| --- | --- |\n| 线粒体 | **产能**中心 |\n| 核糖体 | 合成*蛋白质* |\n'` 导出解包，单元格内 `**产能**`→FauxBold、`*蛋白质*`→Skew，无残留 `*`；补端到端断言；`scripts/review-idml.sh` PASS；用户 InDesign 肉眼确认表格内粗斜体可见。

- [x] **E3-6 目录（TOC）动态化** — Codex @ `feature/codex-e3-6-toc`，commit `748c60c`
  - **现状（Claude 已勘）**：`LayoutEngine` 排版时已收集带**真实页码**的目录条目（`tableOfContents: [TableOfContentsEntry(level,title,pageNumber)]`，`LayoutEngine.swift:131/138`），但在 `LayoutEngine.swift:1141` 被拼成纯文本行（`"标题  3"`）放进 `.tableOfContents` 页 → 导出到 IDML 就是**死文字**，正文页码一变目录不会跟。导出侧 TOC story 现在 `AppliedTOCStyle="n"`（`IDMLExporter.swift:891` 一带）。
  - **目标**：让目录在 InDesign 里能用「Layout → 更新目录」重新生成/刷新页码，而非手敲数字；且排版专业（点导引线 + 页码右对齐）。
  - **做法（两层，至少做到第 1 层即算过；第 2 层加分）**：
    1. **结构化目录段落**：目录每条作为独立 `<ParagraphStyleRange>` 段落，标题与页码间用**右对齐 tab + 点导引线（dot leader）**，而非空格拼接；目录条目段落引用专属 TOC 段落样式（可基于现有 `heading2`/`caption` 派生 `tocLevel1`/`tocLevel2`，须真在 Styles.xml 生成）。正文标题已用命名样式 `heading1`/`heading2`（TOCStyle 要靠它们定位）。
    2. **真·动态 TOCStyle**：在 IDML `Resources` 里输出 `<TOCStyle Self="..." Name="目录">`，含 `<TOCStyleEntry>` 把 `ParagraphStyle/heading1`→tocLevel1、`heading2`→tocLevel2 映射（设置页码位置=条目后、含 tab 导引、是否带超链接）；目录 story/frame 的 `AppliedTOCStyle` 指向它。这样用户在 InDesign「更新目录」即按标题样式重建。
  - 文件：`Sources/LayoutDExport/IDMLExporter.swift`（TOCStyle 资源 + 目录 story 输出 + TOC 段落样式）；如需 `LayoutEngine.swift` 暴露结构化条目（level/title/page）给导出侧而非只给拼好的文本，可加只读访问，但**别动**现有预览拼字逻辑（AG 预览仍用它）。
  - **验收**：① 解包导出的 IDML，grep 到 `<TOCStyle` 且其 `<TOCStyleEntry>` 引用了 `heading1`/`heading2`；目录条目是结构化段落（带 tab/点导引），**无「标题+空格+数字」裸拼**；② 在 **InDesign 中文版** 打开 → Layout → 更新目录，目录按当前正文标题与页码重建（用户肉眼验收，这关人看）；③ 补端到端断言（TOCStyle 元素存在 + 条目段落样式正确 + 页码非硬编码空格拼接）；④ `scripts/review-idml.sh` 仍 PASS。
  - ⚠️ 端到端必须解包 IDML 验证 `<TOCStyle`/段落结构，别只靠单测——本项目踩过「单测绿但功能坏」的坑。

- [ ] **E3-8 token → CMYK 色板** ⏸ **暂缓（用户 2026-06-21 决定先不做；印前转色交 InDesign，非阻塞）**
  - 目标：颜色当前导 RGB swatch；增可选项由 token 算 CMYK 值发 `Space="CMYK"` 色板，减少 InDesign 人工转色（不自建色彩管线，只发数值）。
  - 文件：`IDMLExporter.swift`。
  - 验收：导出后色板面板里对应色为 CMYK 模式，数值合理（非简单 RGB→CMYK 近似导致明显偏色）。

- [ ] **E3-9 约物挤压 + 基线网格对齐**
  - 目标：Mojikumi 标点间距集 + 段落「对齐基线网格」映射进 IDML，使 InDesign 排版与 layoutD 预览一致。
  - 文件：`IDMLExporter.swift`。
  - 验收：含中文标点的段落导出后，InDesign 里标点挤压效果与 layoutD 预览基本一致；启用基线网格对齐的段落确实贴线。

- [ ] **E2-4 对开跨页（facing spread）** — 👤 **认领固定：Claude**（用户 2026-06-21 指定，不由 Codex 做）
  - ⏳ **时序前提**：本批 Codex 的 IDMLExporter 改动（E3-4b/E3-6/E2-5）先合进 dev，Claude 再起手——同文件并行会撞（守 N2：专用 worktree + feature 分支）。
  - 目标：按 `pageSetup.facingPages` 生成 2 页 spread + 起始页码 Section。
  - 文件：`IDMLExporter.swift`（⚠️ Codex 负责文件，本项跨道由 Claude 直接做，故须等 Codex 本批先落 dev）。
  - ⚠️ 风险高（可能打破当前"单页 spread 干净分页"），单独一棒、改完先确认非对开模式没有回归，再重点交用户 InDesign 验收对开效果。

- [ ] **E2-5 固定美术页 → MasterSpread / 非矩形蒙版**
  - 目标：满版图/扉页固定页映射成 MasterSpread；扇面/八角图框用 PathGeometry 蒙版。
  - 文件：`IDMLExporter.swift`。
  - 验收：固定页导出后版心位置/满版图正确；非矩形蒙版图框在 InDesign 里裁切正确。

- [ ] **D-2 DOCX 导入**（阶段 D 遗留）
  - 目标：新增 `DOCXBookImporter.swift`，解析 DOCX → `BookProject` 模型（复用 Markdown 导入已有的段落/样式映射思路）。
  - 文件：新文件 `Sources/LayoutDImport/DOCXBookImporter.swift`（不碰 `MarkdownBookImporter.swift`，避免和上面几项排队冲突）。
  - 验收：一份结构良好的 DOCX 能导入并正确分段、保留基本粗斜体。

---

## Antigravity 道队列（预览渲染 + GUI）

> 负责文件：`Sources/LayoutDEngine/LayoutEngine.swift`、`Sources/LayoutDExport/PDFExporter.swift`、
> `PNGExporter.swift`、`Sources/LayoutDApp/*`
>
> **🔁 本批连续序列（按顺序连做，做完一个自审 PASS 就接下一个，不停下问）：E3-2b 竖排行内 → E3-4p 表格预览 →（待 Codex E3-3 合 dev 后）E3-3p 傍点预览**。
> 约 1 小时或做到这批做完/撞阻塞为止，收尾写一条汇总 handoff。
> 主题：**让预览（Canvas/PDF/PNG）追平 IDML 输出**——本阶段 AG 的核心价值是「InDesign 打开后版面与 layoutD 预览一致」。
> ⚠️ **每项都从最新 dev 起新分支 `feature/ag-<task>`**，别叠旧分支。斜体已在 dev 用 12° `Skew` 矩阵渲染（与 IDML `Skew="12"` 同算法），别改回 FauxItalic。

- [ ] **E3-2b 竖排（直排）下行内格式预览验收 + 修正**
  - 背景：E3-2 已把 `inlineRuns` 透传进 `addFlowingVerticalText`，但**斜体用的是横排 12° 水平切变矩阵**，竖排里直接照搬很可能方向错（竖排字应沿竖向基线倾斜，不是横向歪）。粗体在竖排是否真加重也需肉眼确认。
  - 目标：竖排模式下 `makeAttributedString` 的粗体/斜体在 Canvas/PDF/PNG 渲染正确——粗体明显加重、斜体沿竖排方向合理倾斜，且**不破坏竖排行序/分行/禁则**。
  - 文件：`ChineseTypesetting.swift`（竖排分支的 trait/skew 矩阵）、`LayoutEngine.swift`、三处渲染器。
  - 验收：竖排测试稿（含粗/斜词的引文）导 PNG，目标词字重/倾斜正确、竖排列序不乱；补端到端断言（竖排 + run 分段）；`scripts/review-idml.sh` PASS。修好后 Claude 出 PNG 交用户肉眼验。

- [ ] **E3-4p 原生表格预览渲染**（配对 Codex E3-4 IDML 原生表格）
  - 背景：表格组件当前在预览里基本当文字画；Codex 那边要升级成 IDML 原生 `<Table>`。预览侧也要画成真表格才能「预览=输出」。
  - 目标：table 组件在 Canvas/PDF/PNG 渲染为真实网格——行列线、单元格底色、内边距、按列宽分配，文字落在单元格内。
  - 文件：`CanvasView.swift`、`PDFExporter.swift`、`PNGExporter.swift`、`LayoutEngine.swift`（如需表格测量/分页）。
  - 验收：demo 里的表格导 PNG 是带边框的真网格（非裸文字流），列对齐、底色正确；单测断言表格 frame 产出行列结构；`scripts/review-idml.sh` PASS。

- [ ] **E3-3p 傍点（Kenten 着重号）预览渲染**　⚠️ **依赖：待 Codex E3-3 合进 dev 后再做**（当前 E3-3 退回修复中）
  - 背景：Codex E3-3 让 `==着重==` 落地为 `InlineEmphasis.kenten` → IDML `KentenKind`。预览侧需在着重字**旁/上画着重点（芝麻点）**，否则预览看不出傍点。
  - 目标：Canvas/PDF/PNG 对 `.kenten` run 的每个字符绘制着重号（横排在字下/字右、竖排在字右侧，对标 InDesign 默认 KentenSesameDot 位置）。
  - 文件：`ChineseTypesetting.swift` 或三处渲染器的字形装饰逻辑。
  - 验收：`==着重==` 导 PNG，着重字逐字带着重点、普通字没有；横排/竖排位置合理；`scripts/review-idml.sh` PASS。**起手前先确认 `InlineEmphasis.kenten` 已在 dev**（`git merge origin/dev` 后 grep 得到），没有就跳过这项、先做别的或写 handoff 说明卡点。

- [x] **E3-2 行内格式预览渲染** — Antigravity @ `feature/ag-e3-2`, commit `44e2873`
  - 目标：PDF/PNG/Canvas 三处预览按 `inlineRuns` 切粗/斜（当前预览整段同字重，仅 IDML 已保真）。`LayoutEngine.swift` 的 `addText` 若需精确测量，把 run 透传进 measurement（已按字符类切复合字体，扩成叠加 emphasis）。
  - 文件：`LayoutEngine.swift`、`PDFExporter.swift`、`PNGExporter.swift`、`CanvasView.swift`。
  - 验收：含粗/斜的页 PNG/Canvas 里目标词字重不同（用户视觉验）；单测断言渲染层确实收到 run 并分段绘制。

- [x] **校对批注层** — Antigravity @ `feature/ag-e3-2`, commit `374c28e`
  - 目标：新增批注/校对标记层，叠加在 Canvas 上但不影响实际排版（类似 PDF 注释，不是 frame）。
  - 文件：`AppState.swift`（新状态）、`CanvasView.swift`（叠加渲染）、可能新文件 `AnnotationLayer.swift`。
  - 验收：能在画布上加批注标记、保存随项目持久化、不参与自动重排/不被导出带进 IDML 正文。

- [ ] **E3-10p 预览验收 harness（让 PNG 能呈现行内特性，优先级高——当前挡住傍点/竖排斜体验收）**
  - 背景：`--export-png` 走的是固定 demo/brochure 模板，**每页只落一个正文段且会丢弃带强调（粗/斜/傍点）的正文段**——导致傍点（E3-3p）与竖排斜体（E3-2b）的预览渲染**无法出图给用户视觉验收**（2026-06-21 实测：表格能出、这两个出不来）。这不是渲染功能坏，是导图路径喂不进内容。
  - 目标：提供一条「忠实正文流」的预览导出——把任意 Markdown 稿件的正文段（含 inlineRuns 的粗/斜/傍点、竖排）真正落版到 PNG/PDF，而非套固定模板丢段。可以是新 CLI 开关（如 `--export-png-flow`）或修 demo 模板的正文 frame 让其连续承载全部正文段。
  - 文件：`Sources/LayoutDApp/main.swift`（CLI/导出路径）、`PNGExporter.swift`/`PDFExporter.swift`、`LayoutEngine.swift`（如需正文连续成帧）。
  - 验收：含 `==着重==`、`**粗**`、`*斜*`、竖排段的测试稿导 PNG，**逐项都能在图里肉眼看到**（傍点出点、粗体加重、斜体倾斜、竖排倾斜方向正确）；`scripts/review-idml.sh` PASS。这条做完，E3-3p / E3-2b 才能真正走完视觉验收。

- [ ] **导出选项面板跟进**（待 Codex 的 E2-4 / E3-8 任一项落地后联动，非阻塞可先设计）
  - 目标：「导出 IDML…」面板加开关：对开跨页模式、CMYK 色板模式。
  - 文件：`ToolbarView.swift` 或导出选项相关 View。
  - 验收：开关能正确传参到 `IDMLExporter`，关闭时行为与当前一致（向后兼容）。

---

## 待评估 Backlog（需用户拍板是否进路线图，先不排期）

> 这些是图书排版常见但 layoutD 尚未列入需求的功能。是否做、何时做由用户决定；
> 列在此避免遗忘。每项落到正式队列前由 Claude 补「目标/文件/验收」。

- [ ] **索引（Index）**：术语→页码索引页生成（InDesign 有原生 Index 机制，可对标）。
- [ ] **参考文献 / 引文样式**：文末参考文献列表 + 文中引用标记的样式化。
- [ ] **长表格分页 + 表头跨页重复**：超过一页的表格自动续页、每页重复表头（依赖 E3-4 表格基础）。
- [ ] **图表跨页 / 图文绕排进阶**：满版图跨对开、图片文字绕排（当前为矩形成帧）。

## 基础设施待办（Claude/用户）

- [ ] 真正 CI（GitHub Actions 跑 `scripts/review-idml.sh`），把审核从「人工记得跑」变成 push 即跑。
- [ ] IDML 官方 RNG schema 校验 + golden-file 回归基线，补强 `review-idml.sh`。
- [ ] relay `run_checks("test")` 末行误显「0 tests」，改回显 XCTest 汇总行。
- [ ] **文档同步**：`docs/development-plan.md` 的 E0 spike 仍标 `[ ]`，实际已被 E1 取代吸收——回填标注（E1 已在 InDesign 人工终验通过）。
