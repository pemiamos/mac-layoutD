# 任务队列 Task Queue（Codex / Antigravity 自助接力用）

> 目的：让开发更自动化。两边都不必每轮等 Claude 手喂任务——读本文件，领**自己道里**最上面未打勾的任务做。
> Claude 维护本队列与每项的「目标/文件/验收」；攒一批分支后 Claude 批量审核，不再一个一个提交、一个一个审。
> 两道按文件边界分工，正常不会改到同一文件；真出现冲突按下方「认领协议」处理。
> **已完成任务见 `.ai/QUEUE-ARCHIVE.md`**（2026-07-04 起归档，保持本文件只含活任务）。

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
8. **别提交生成产物**：`Samples/output-*`、导出的 PDF/PNG 样张等**不进仓库**（验收样张投 `~/Desktop`）。

**Claude（集成）批量做：**
1. 在主仓库里，攒几个 `feature/codex-*` / `feature/ag-*` 分支一起审，不逐个来回（共享 `.git`，无需等对方 push）。
2. 每个分支跑 `scripts/review-idml.sh`：全绿才算过；有 FAIL 把精确 repro 退回交接。
3. 过的合进 `dev` 集成分支（不直接进 main）；`.ai/HANDOFF.md` 等交接日志的合并冲突由 Claude 集中解决。
4. `dev` 攒一批后交用户在 InDesign/GUI 做**视觉验收**（无头验证不了渲染对错，这关必须人看）。
5. 验收 OK → Claude 合 `dev` → `main` 并 push；验收有问题 → 直接在 Claude 这边改。

**认领协议（避免两道撞同一文件）**：两道文件边界天然不重叠（见下方"负责文件"）。如果某任务临时需要碰对方道的文件，先在本文件该任务下加一行「⚠️ 跨道改 `<文件>`，已知会 <对方>」再动手。

---

## 待用户视觉验收（阻塞合 main）

- **InDesign 式工作区骨架（第一步）** — dev（含 `72590f8`）。
  验：① 顶部控制面板（选中帧显示 X/Y/宽/高可编辑、未选中显示文档概要）；② 底部状态栏（页码跳转、预检状态灯、缩放百分比/适合页宽）；③ 右侧「面板/检查器」单列分段切换、画布更宽；④ 整窗深色、画布台面深灰、页面纸张白；⑤ 窗口工具条精简为图标模式。
- **左侧工具栏：文本框/图像框工具 + 单键快捷键** — dev=`facadbf`（2026-07-04 用户审核提案通过后 Claude 实现）。
  验：① 选「文本框工具」在页面拖矩形 → 出现空文本框（自动选中，检查器可填字）；② 选「图像框工具」拖矩形 → 出现图像框（引用某图，检查器「更换图片」可换；无图时弹窗提示）；③ 单键快捷键（画布点一下获焦后）V/A/T/F/U/H/Z/⇧P 切工具；④ 工具栏分组顺序像 InDesign。
  App 已用新构建启动（demo.md）。验收 OK → 合 main；要调 → 反馈 Claude 迭代。
- ~~基础工具热修（GUI）~~ — 用户 2026-07-04 反馈：GUI 整体按 InDesign 布局重做（见上），热修已随批合 main(`6b12271`)。
- [x] **B1 图文绕排** — ✅ 用户 2026-07-04 视觉验收通过，已合 main(`6b12271`)。
- [x] **行内格式阶段1 InDesign 终验** — ✅ 用户 2026-07-04 确认 OK。

---

## Claude 道（灌版主线 + 高风险导出 + 集成）

> **2026-07-06 定位校准（见 DECISIONS）**：layoutD 交付「初排灌版」给 InDesign，不替代 InDesign。开发价值标准 = 文流/样式/视觉规范/CMYK 高完成度迁移进 InDesign、给人工调整省时间。可编辑性 > 逐像素冻结（InDesign 里漂移可人工调校）。脚注/傍点/表格深化 = 初排细枝末节，不再投入。
> **2026-07-07 规范包路线定案（见 DECISIONS）**：视觉规范/样张走「AI 生成规范包 JSON → layoutD 渲样张 → 人工比选 → 同一规范直通 IDML」。首测已过：`~/Desktop/layoutD-规范包测试/` 有 3 份规范包 JSON（**方案A-探索黄 已选为基准**）+ 视觉预览.html；总纲见桌面《layoutD 视觉规范与样张生成·开发计划 v1.0.pdf》。本批新任务：SPEC-PACK-1（Codex 道）→ FIXTURE-1（Claude 道）→ SAMPLE-1（AG 道，依赖前两个）。

- [x] **FRAME-CANVAS-0 抽取共享断流分组函数** — ✅ Claude。
  - 交付：新增 `Sources/LayoutDEngine/FlowFrameGrouping.swift`（`public func groupIntoFlowFrames(pages:project:) -> FlowFrameGrouping`，`FlowFrameGrouping` 含 `frameRunIndex`/`paragraphsForRun`/`groupsByPage`/`groupsByRun`，`FlowFrameGroup` 除合并 rect 外还带 `memberFrameIndices`——组内原始 frame 下标，供 FRAME-CANVAS-1 画布按组渲染用）。放在 `LayoutDEngine`（`LayoutDApp`/`LayoutDExport` 都已依赖它，天然可 import）。`IDMLExporter.swift` 的 `runIndexByParagraphId`/`FrameKey`/`FlowPageKey`/`ChainInfo`/`unionRect`/`isBodyFlowParagraph` 全部删除、改为调用共享函数（`IDMLExporter+Helpers.swift` 同步瘦身）。
  - 验收：303 测试过（+2 新单测 `FlowFrameGroupingTests`：标题/抽言打断正文流分两条 run、表格打断正文流）、review-idml.sh 14/14、golden 逐字节一致（证明抽取零行为变化）。
  - **AG 的 FRAME-CANVAS-1 前置条件已满足，可以开工**（见下方 Antigravity 道队列）。

- [x] **FIXTURE-1 标准样章 fixture** — ✅ Claude（`eeb2a7a`，合 dev `1197b03`）。
  - 交付：`Samples/fixture-standard-chapter.md`（Markdown 角色标签格式，走现有导入器）——《深海不是黑暗的尽头》标准样章，覆盖 章名/节名/文章名/开节概述/正文/抽言/图注/引文/图片占位（+参考文献）全部角色，每个至少一次。
  - 回归语料：`Tests/LayoutDImportTests/FixtureStandardChapterTests.swift`（3 测）——从 `#filePath` 推算样章路径（不硬编码绝对路径），断言每个角色→正确段落种类/命名样式、标签字面不漏进正文、front matter 不泄漏。
  - 验收全过：286 测试（+3）、`review-idml.sh` 13/13；导入→初排→PDF+IDML 全链路跑通；IDML 含全部中文命名样式（含 图注）且 Story 无标签字面泄漏。
  - 用途：SAMPLE-1 一键样张的固定输入 + 角色覆盖回归语料（SAMPLE-1 CLI 直接指向此文件即可）。
- [x] **BUG-2 文档末尾「新建页面」无反应** — ✅ **2026-07-07 用户验证通过**（`a4ea45b`），验收 SPREAD-1 时顺手发现并现场修复。根因：`insertPage()` 在 `pageNum = 当前页数+1` 处存一条空白 LayoutPlan，但引擎只在**内容溢出触发翻页**时才检查该页有没有计划——如果插入的空白页排在所有正文内容之后，永远没有内容会触发翻页翻到那么远，计划存了但没人看，页面凭空消失。`finish()` 收尾时补一次检查：正文排完后如果紧接着还有计划就继续 materialize（可级联多页），带一个防死循环的兜底。新增回归测试复现原场景。
- [x] **TYPE-1 段末孤字（单字不成行）** — ✅ Claude（`13f01a2`）。**待用户 InDesign 验收**（桌面 `orphan-spike.idml`，四段刻意错开长度的正文）。用户 B1 验收时发现 InDesign 里段落末行会甩单字（如「辨。」）。查证：THREAD-1b 后正文交 InDesign 自己折行，而 InDesign **没有**原生「避免单字尾行」开关（社区共识：不算断行错误，靠 NoBreak 字符属性变通）。实现：`chapterStoryXML` 给每段末尾两个实义字（含尾部悬挂标点）打 `NoBreak="true"`（InDesign 的 `noBreak` 字符属性，动手前对照 Adobe DOM 文档确认），放不下时整体换到末行，末行至少两字。写法对照真实属性、不改文字内容。283 测试过、review-idml.sh 12/12、确定性一致、golden 隔离刷新（段末加 NoBreak）。**待用户肉眼确认**：InDesign 里段落末行不再出现单字。

- [ ] ~~**BUG-1 跨段落脚注编号全错**~~ ⏸ **不修（用户 2026-07-06 决定）**——脚注使用频率极低，初排里属细枝末节，需要时 InDesign 补做很快；且 THREAD-1 落地后 story 结构整个会变，现在修是白修。根因存档：一框一 Story 零串接 → InDesign 原生脚注按 Story 各自从 1 编号（Markdown/DOCX 两路径均复现，非 IMP-4/SPLIT-GUI 回归）。
- [x] **THREAD-1a 串接文流 spike** — ✅ **2026-07-06 用户 InDesign 人工验证通过**。手工生成脚本 `scratchpad/gen-thread-spike.py`：一个 Story 装 32 段正文 + 3 个页大小 TextFrame 用 Previous/NextTextFrame 串接（坐标沿用 demo 版心）。用户验证三点全过：① 文字跨页连续流（**第12段被从中间拆到第1→2页、第20段拆到第2→3页、段号 1→27 连续**——独立框永远做不到跨页拆段，铁证串接成立）；② 编辑顺移丝滑自动（删/插一段后文跨页自动重排）；③ 中文/复合字体/约物/两端对齐正常，漂移可接受。
  - **验证过的结构模板（THREAD-1b 照此实现）**：① 一章正文合成一个 `<Story Self="uStoryBodyN">`，每段一个 `<ParagraphStyleRange AppliedParagraphStyle="ParagraphStyle/body">`，Content 末尾带 `\n`（最后一段不带）；② 每页一个 `<TextFrame>`，几何=引擎算好的版心框（PathGeometry 四角坐标），`ParentStory` 指向该章 Story；串接：首框 `PreviousTextFrame="n"`、末框 `NextTextFrame="n"`，中间各框 Prev/Next 互指兄弟框 `Self` id；③ designmap `StoryList` 列各章 Story，每 Spread 一页含其串接框；④ InDesign 打开自动灌流、编辑自动重排，无需额外属性。
- [x] **THREAD-1b 第一刀：正文+标题按章串接** — ✅ **2026-07-06 用户 InDesign 人工验证通过**（`1338b97`）。历经两轮修复：①段落间需要字面 `\n` 作段落标记（PSR 边界本身不够，对照 THREAD-1a spike 脚本定位）；②多栏页面下按页合并 rect 会把左右两栏错误并成一个双倍宽的框（按 `(页,栏)` 分组后修复，`idml-multicolumn-frame-grouping` 记入长期记忆）。40 段/2 栏/3 页样张验证：标题独占一行、正文分段正常、跨栏跨页顺畅衔接、字距自然。
  - 实现：`export()` 内先做一遍预扫描，把「章名标题（addSectionTitle 无 sourceParagraphId，按只增计数器认领）+ 正文流段落（`isBodyFlowParagraph` 排除 callout/table/footnote/sideNote/figure）」按 `project.sections` 索引分组；每章一个 `<Story Self="uStoryChapterN">`（内容直接取原始 `paragraph.text`+`inlineRuns`，不经 frame 拆分/归一化，天然对齐、无需二次映射脚注/行内样式偏移）；每页一个合并 `TextFrame`（几何=该章在该页所有原 frame 的并集矩形），`PreviousTextFrame`/`NextTextFrame` 首尾相连。前置页（封面/目录）与非 `.text` kind（图片/抽言/表格/脚注/旁注/运行页眉）不受影响，走原逐帧独立 Story。已验证：10 页合成长章节链完整（`uChapterTF0_0`…`uChapterTF0_9`，首尾 `n`、中间互指）；`swift test`(281 过)/`review-idml.sh`(全过)/golden 已更新(`scripts/golden-update.sh`，纯预期变化：故事数按章合并 + 早前已知的 Composer 属性移除漂移一并刷新)/两次导出逐字节确定性一致。
  - **本刀范围**：只做正文+标题同流；图片/抽言/知识卡片仍是独立定位框（锚定对象是下一刀 THREAD-1b-cut2）。
  - 文件：`Sources/LayoutDExport/IDMLExporter.swift`。
  - **下一刀（cut 2）**：图片/抽言转锚定对象，随所属段落走。
- [x] **THREAD-1b cut 2：内嵌图锚定** — ✅ **2026-07-06 用户 InDesign 人工验证通过**（`9ba5b40`）。范围最终定格：只锚定图片本身，图注保持独立定位框（细节见下）。
  - **范围（比原计划更收敛）**：只处理通过 `paragraph.anchoredAssetIds` 挂在正文宿主段落上的图片（如 Markdown `![](img.png "anchor=previous")` 内嵌图）——嵌成 IDML 锚定对象（`AnchoredObjectSetting AnchoredPosition="AnchoredAboveLine"`，锚点是文流里的 Unicode 占位符 U+FFFC），挂在宿主段落末尾随文重排。**用户验证**：编辑宿主段落文字后图片正确跟着移动，机制成立。孤立的 `.figure` 段落（独占一行的图）、抽言（callout）仍是独立定位框——**不在本刀范围**（它们没有"宿主段落"，需要不同挂载机制，留给后续按需评估）。
  - **图注（已尝试并放弃随图锚定）**：试了两版"图注跟着图片走"（先用 U+2028 强制换行、再去掉换行让锚定对象自然换行），两版都在 InDesign 里复现同一个 bug——图注那一行字符间距被异常拉伸、疑似丢字，和更早的段落标记 bug 症状一致，但排查不出根因（需要真机 InDesign 迭代，盲改风险不划算）。**已回退**：图注维持独立定位框（cut 2 之前的行为），不随图片移动——按本项目"可编辑性 > 逐像素冻结、漂移可人工微调"的既定原则，这点漂移可接受，不再追加投入。
  - 实现：`LayoutEngine.addAsset` 把调用它的段落 id 带到图片 frame 上（之前完全不追踪，供导出层反查"这张图挂在哪个段落"）；`IDMLExporter` 预扫描收集"哪个宿主段落挂了哪些图"，跳过这些图片的独立定位框输出，改为嵌进该段落在章 Story 里的 CharacterStyleRange。过程中揪出两个"帧静默消失"的 bug 并修复：①宿主段落文字为空（如 DOCX 专门用来装图的段落）被"跳过空段落"的判断误伤，图片两头都进不去；②孤立 `.figure` 段落的图片被预扫描误判成"已挂到某段"从而被跳过独立输出（其实它是自己给自己当宿主，不该被纳入锚定路径）。
  - 文件：`Sources/LayoutDExport/IDMLExporter.swift`、`Sources/LayoutDEngine/LayoutEngine.swift`。
  - 验收：281 测试过、review-idml.sh 10/10（含新增的 DOCX 内嵌图回归）、逐字节确定性一致、全包 XML well-formed、无重复独立框；InDesign 人工验证图片随宿主段落编辑正确重排。
  - **后续可选**（不阻塞，按需再评估）：扩展锚定机制到孤立 `.figure` 图/抽言（需要设计"没有宿主段落时怎么挂"）；图注随图锚定需要真机 InDesign 调试后再重试。
- [x] **THREAD-1b cut 3：收边** — ✅ Claude（`309e18e`）。GUARD-4 串接探针加进 `review-idml.sh`（60段合成章节撑出多页/栏，断言单头单尾、正反遍历都覆盖全部框、无孤儿无环；已自证：人为断链后探针 FAIL，修复后恢复 PASS）。封面/目录/表格特例复核：造了个含表格+足够正文触发真实 TOC 的样张，确认章 Story 只含预期的标题+正文段落，表格/目录仍各自走独立 Story，未被误并进文流。**THREAD-1b 三刀全部完成**：cut1（正文+标题按章串接，用户验收）、cut2（内嵌图锚定，用户验收；图注锚定放弃，见 DECISIONS）、cut3（收边，本条）。
  - 说明：`scripts/review-idml.sh` 名义上是 Codex 道文件，但 GUARD-4 是 THREAD-1b 收尾的一部分、Claude 有完整上下文，直接实现而非中途交接。
- [x] **MASTER-1 自动页码** — ✅ **2026-07-06 用户 InDesign 人工验证通过**（`9e2ccc8`）。主页面板见 A-主页带页码，正文页页码正确递增。
  - **核实结果（动手前先查了现状）**：之前的猜测"页码按静态文本逐页画"是错的——IDML 导出压根**没有页码**，只有 PDF/PNG 导出器直接用 CoreGraphics 逐页画数字（`drawPageNumber`），跟 frame/主页完全无关。IDML 里的主页此前是空的（只有一个 `<Page>` 元素，没有任何内容）。
  - **实现**：主页加一个 TextFrame，内容是 InDesign「当前页码」特殊字符——写法是 `<Content>` 里嵌一个字面的 `<?ACE 18?>` 处理指令节点（不是普通文本！），这是 Adobe 官方约定（查了一份真实的 Adobe 参考文档才拿到准确写法，没有再像锚定对象那次盲猜——`<?ACE 18?>` 本身也验证过是合法 XML，`review-idml.sh` 的 well-formed 检查过了）。正文页统一 `AppliedMaster="uMasterA"`，套上主页页码就自动出对，不用逐页画。位置沿用现有 PDF/PNG 页码的靠页面上方居中做法。
  - **范围收窄**：只挪了页码，页眉书名/章名没动（还是 LayoutEngine 逐页画的静态标题——它是 PDF/PNG/IDML 共用的一份 frame，挪走要么得复制要么把三个导出器共用的东西拆开；而且"随页显示当前章名"需要 InDesign 文本变量绑定段落样式，是明显更大的一个功能，没有在这刀里做）。版心/栏参考（原计划里的一部分）也没做——现状页面本身已经有版心/栏（BOOK 层面的实际排版），"主页版心参考线"是可视化辅助线，价值没有自动页码高，先跳过。
  - 文件：`Sources/LayoutDExport/IDMLExporter.swift`。
  - 验收：281 测试过、review-idml.sh 12/12、逐字节确定性一致、全包 XML well-formed、golden 已刷新（新增 master TextFrame+Story，改动隔离）。**InDesign 人工验证待用户**：主页面板见 A-主页带页码，正文页页码正确递增。
  - **后续可选**（不阻塞）：对开镜像页码位置（留给 SPREAD-1 一起做）；页眉显示当前章名（需要文本变量机制，工作量较大，按需评估）。
- [x] **SPREAD-1 对页合并 Spread** — ✅ **2026-07-07 用户 GUI 验证通过**（`b576554`）：Export IDML... 面板"启用对开跨页"默认已打勾。
  - **核实结果（动手前先查了现状，发现活儿比预期小很多）**：真对页 spread（左右页同 spread、书脊镜像、版心镜像）**早就做完并验收过了**——`E2-4`（Claude, 用户 2026-06 已验收 PASS）+ `E2-4p`（AG，PDF/PNG 侧并排预览）。`testFacingPagesSpreadImposition` 单测也在跑。真正的缺口只有一处：GUI 的"Export IDML..."导出面板，"对开跨页"开关**硬编码默认关闭**、跟项目自身的 `pageSetup.facingPages` 设置完全脱节——旁边的 CMYK 开关早就做了"默认跟随项目设置"，唯独这个漏了。等于说：用户在 App 里预览的明明是对开跨页书稿，导出 IDML 时如果忘了手动勾选，出来的就是非对开——这正是验收标准"与 layoutD 预览一致"没做到的地方。
  - 实现：一行修复，`WorkspaceViewController.exportIDML()` 里让 `settingsState.facingPages` 默认取 `appState.project.pageSetup.facingPages`（跟 `cmykColors` 已有的写法一致），面板里仍可手动改。CLI 的 `--idml-facing` 保持显式选项不动（脚本化场景应该显式指定，不该悄悄跟着项目状态变）。
  - 文件：`Sources/LayoutDApp/WorkspaceViewController.swift`。
  - 验收：281 测试过、review-idml.sh 12/12（对开导出机制本身未改动，`testFacingPagesSpreadImposition` 仍过）。**GUI 验收待用户**：打开一份 `pageSetup.facingPages=true` 的项目，选「Export IDML...」，确认对话框里"启用对开跨页"默认已经打勾（不用手动点）。
- [x] **PERF-1 全书规模性能基准** — ✅ Claude `e106c46`，合 dev(`23df697`, 2026-07-04)。合成 161 页书稿基准：**本机基线 ≈1179ms/次全量排版**（断言只拦 60s 性能悬崖，CI 环境差异安全）。后续 PERF-3/4 用这个数字对比。
- [x] **PERF-2 baseline 布局缓存** — ✅ Claude `e106c46`，合 dev(`23df697`, 2026-07-04)。对照版只在内容/样式真变时重排（比较时剔除 appliedLayoutPlans + qualityMetricsHistory）；纯版面方案操作/undo/redo 不再触发第二次全书排版，单次改动成本约减半。加 baselineLayoutCount 测试钩子+缓存单测。
- [x] **B1-IDML 导出侧图文绕排** — ✅ Claude（`498c9cd`）。**待用户 InDesign 验收**（桌面 `b1-idml-spike/wrap-spike.idml` + 同目录 `Links/diagram.png`：图片前后各一段够长的正文，用来看绕排效果）。
  - 实现：独立定位的图片框（孤立 `.figure` 段落、跨页大图——不含 THREAD-1b cut2 的锚定图片，那条路已经靠文流本身让位，不需要绕排）现在带 `<TextWrapPreference>`（矩形绕排 BoundingBoxTextWrap + 两侧避让 + 四边 6pt 间距）。写法对照过一份真实 Adobe 导出的 IDML 样本确认结构（这轮吸取了两次盲猜 IDML 未知元素踩坑的教训，动手前先查真实参考）。
  - 文件：`Sources/LayoutDExport/IDMLExporter.swift`。
  - 验收：282 测试过、review-idml.sh 12/12、XML well-formed、golden 无变化（样例项目唯一素材标了 unused、从未真正入版，另造了带真实占位图的样张验证）。**InDesign 人工验证待用户**：图片旁边的正文是不是主动绕开了图片的矩形范围。
- [x] **SPLIT-ENGINE LayoutEngine.swift 拆分** — ✅ Claude（`046950e`）。1971 行拆成 7 个文件（核心 327 行 + TextFlow/Assets/Geometry/Measurement/FrontMatter/LayoutPlan 六个 extension，最大 492 行）。纯搬家：`private struct LayoutContext` 改成模块内部可见（`struct`，对模块外仍不可见，`LayoutEngine` 才是唯一公开入口），其 `private` 成员相应放开，供跨文件 extension 访问。三重验证零行为变化：①排序后逐行 diff 与原文件一致（只差拆分带来的 extension 包装样板）；②283 测试过、review-idml.sh 12/12、golden-check 逐字节一致（证明导出结果像素级不变，不只是"测试还过"）；③两次导出确定性一致。
- [x] **SPLIT-EXPORT IDMLExporter.swift 拆分** — ✅ Claude（`87f2dfb`）。1563 行拆成 7 个文件（核心留入口 export() 436 行 + Links/BuildContext/Helpers/PageItems/Resources/Stories 六个 extension，最大 416 行）。照抄 SPLIT-ENGINE 配方，同样三重验证零行为变化（排序逐行频次 diff 零行丢失、283 测试过、review-idml.sh 13/13、golden 逐字节一致）。
- [x] **GOLDEN-GUARD golden 防漂移护栏** — ✅ Claude（`c311fc7`）。三道闸：①`golden-update.sh` 强制 `--reason` 并写入 `Tests/golden/GOLDEN-LOG.md` 审计留痕；②覆盖前强制打印新旧 diff（杜绝盲刷）、新旧一致拒绝空刷；③`review-idml.sh` 本地跑时自动带 golden-check（CI 跳过，字体环境差异会误报），本地探针 12→13。三条路径均已自证（无 reason 拒绝/空刷拒绝/真变化打印 diff+留痕）。review-idml.sh 属 Codex 道文件，沿 GUARD-4 先例由 Claude 直改。**各道注意：今后刷 golden 必须走 `scripts/golden-update.sh --reason "<原因>"`，禁止手工覆盖基线。**

## Codex 道队列（导入 + 探针）

> 负责文件：`Sources/LayoutDImport/*`、`scripts/review-idml.sh`。
> 斜体导出已用 `Skew="12"`、粗体用 `FauxBold="true"`（别用 `FauxItalic`/`FontStyle`，对 CJK 不可见/出粉色替代字形）。

- [x] **SPEC-PACK-1 视觉规范包 schema 补全 + 导入校验** — ✅ Codex（`a7ce358`，Claude 合 dev `70a49fd`→dev）。
  - 交付：`StyleBaselineImporter` 加规范包识别（`ImportFormat.specPack`）+ `parseSpecPack(jsonData:fontAvailability:) -> SpecPackImportResult{tokens, unsupportedFields, fontResolutions}`；支持 `meta/page/fonts/colors/roles/vertical`；毫米→point token、角色中文名→段落样式 token、字体别名走批准映射 + CoreText 校验真实已装字体、不支持字段进 `unsupportedFields` 明确上报（非静默忽略）。`docs/spec-pack-guide.md` 编写指南 + `StyleBaselineImporterSpecPackTests`（桌面方案A/B/C 三份真 JSON 全导入 + 10 个非法样例带 JSON path 报错）。
  - 验收全过：`swift test` 290、`review-idml.sh` 13/13。
  - **⚠️ 已知边界（SAMPLE-1 必读）**：`parseSpecPack` 只产出/校验 **DesignTokens**，**尚未**把字体族/点缀色/开本尺寸落地到实体 `StyleLibrary`/`PageSetup`（Codex 交接明确说明）。现有 token 应用路径 `AppState.applyImportedTokens` 也只覆盖 margins/columns/grid/fontSize/lineHeight/缩进/段距，**不含** 字体族、颜色、trim 尺寸。样张要在视觉上区分方案A/B/C，SAMPLE-1 必须自己补这一段应用（见下）。
- [x] **GUARD-1 角色标签端到端探针进 review-idml.sh** — ✅ Codex @ `feature/codex-guard-role-tags`（`bdd1ac2` test: guard role tag idml review probe）
  - 背景：角色标签结构化导入（IMP-3）是 layoutD 核心能力，但 `review-idml.sh` 的端到端探针目前只测行内粗斜体——改导入器时 CI 逮不住角色回归。
  - 目标：探针加一段角色标签 fixture（含 一级标题/开节概述/抽言/参考文献 标签 + 正文），导 IDML 解包断言：① 标签文字零漏出（Story 无「抽言」「开节概述」等标签字面）；② Styles.xml 含中文命名段落样式（章标题/概述/抽言/参考文献）；③ 对应段落 `AppliedParagraphStyle` 指向正确样式。
  - 文件：`scripts/review-idml.sh`（新增探针段，用 printf 造 Markdown fixture 即可，别提交二进制 docx）。
  - 验收：探针在当前 dev PASS；人为把导入器角色识别注释掉时探针 FAIL（自证有效，验完还原）；整脚本仍 PASS。
- [x] **SPLIT-IMPORT MarkdownBookImporter.swift 拆分** — ✅ Codex @ `feature/codex-split-import`（`4ca0db6` refactor(import): split markdown parser responsibilities），Claude 已合 dev
  - 拆为 `MarkdownParserBlocks/Inline/FrontMatter/Images.swift` 四个 extension 文件，纯搬家不改逻辑，对外 API 不变。
- [x] **E3-9 约物挤压 + 基线网格对齐** — ✅ Codex @ `feature/codex-e3-9-mojikumi-baseline`（`b4dbb3d` feat(export): bind mojikumi and baseline grid in IDML），Claude 已合 dev
  - IDML 补 `MojikumiTable` 声明 + 段落样式绑定 Mojikumi/MojikumiSet + `GridAlignment=AlignAllLinesToGrid` 基线网格绑定。⚠️ 待用户在 InDesign 里肉眼确认标点挤压与基线贴齐效果（视觉属性，探针测不出）。
- [ ] ~~**E3-8 token → CMYK 色板**~~ ⏸ **暂缓（用户 2026-06-21 决定；印前转色交 InDesign，非阻塞）**
- [x] **IMP-4 DOCX 脚注导入** — ✅ Codex @ `feature/codex-docx-import-guards`（`3f84c77` feat(import): cover DOCX footnotes and import guards），Claude 已合 dev
  - 解析 `word/footnotes.xml` + 正文 `w:footnoteReference`，映射为与 Markdown 同构的 `Paragraph(kind: .footnote(number:), styleId: "footnote")` + 正文塞 Unicode 上标 + `anchoredFootnoteIds` 打通 E3-7 原生 Footnote 导出。GUARD-3 探针断言"脚注上标不残留"，确认无双标记。⚠️ 已知小边界：正文 marker 号与脚注段落号用两套计数器，仅当某 `footnoteReference` 指向空/缺失脚注时会错位（正常 Word 稿全部非空则锁步一致，罕见畸形稿才触发）。
- [x] **IMP-2 收尾：DOCX 内嵌图片改落项目目录** — ✅ Codex @ 同分支（`3f84c77`），Claude 已合 dev
  - 内嵌图片不再写到源 `.docx` 同级 `images/`，改写系统临时目录下唯一 `layoutd-docx-assets-*/images`；`Asset.fileName` 仍保持 `images/<name>` 引用名；顺带规范化 `word/media` 相对路径（`normalizedWordEntryPath` 处理 `../`）。
- [x] **GUARD-3 DOCX 端到端探针进 review-idml.sh** — ✅ Codex @ 同分支（`3f84c77`），Claude 已合 dev
  - 探针现场用 python3 造最小 OOXML（粗斜体/内嵌图/脚注）走完整 DOCX 导入→IDML→解包，断言 FauxBold/Skew/原生 Footnote/上标不残留/图片进 Links。探针总数 8→10 全过。
- [x] **GUARD-4 串接文流探针** — ✅ Claude（`309e18e`，随 THREAD-1b cut3 一并做掉，见上，Codex 无需再领）。

## Antigravity 道队列（预览渲染 + GUI）

> 负责文件：`Sources/LayoutDEngine/LayoutEngine.swift`、`PDFExporter.swift`、`PNGExporter.swift`、`Sources/LayoutDApp/*`
> ⚠️ 教训复盘：每个新任务从**最新 dev** 起分支、真把 feat 本体迁过去（别只加 docs commit）；同步 dev 不碰 QUEUE.md（已归 Claude 独占）；**生成样张别提交进仓库**（B1 踩过，Claude 合并时剔除了 20 个 PNG/PDF）。

- [x] **FRAME-INSET-2 预览文字贴框边（追平 IDML InsetSpacing=0）** — ✅ AG（`4f4ff4b`，Claude 审核合 dev `bba4867`）。普通文字框默认内边距归零（`drawText` `applyDefaultInset` 默认改 false）；组件类（知识卡片/表格）走调用方预先按 `componentStyle.textInsetX/Y` 做过的 rect，不受影响（已核对调用点）。画布/PDF/PNG 三处一致。
- [x] **UNDERLAY-1 垫底图预览/引擎追平** — ✅ AG（`51dcfdc`，Claude 审核合 dev `bba4867`）。`LayoutEngine+Assets.swift` 里 underlay 图片路径完全跳过 cursor 推进/绕排（提前 `return`，不进 `prepareWideAssetPlacement`），`exclusionRects`/`LayoutPlan` 侧同步排除；跨页 spread 底图用 `deferredUnderlayFrames` 处理"图片排到的页面还没生成"的时序、`finish()` 补页逻辑一并接好。三渲染器按 underlay 优先画（图在下字在上）。新增 2 个针对性单测。
  - 验收：301 测试过、review-idml.sh 14/14、golden 逐字节一致。**审核时剔除**：51dcfdc 里误带进一个与功能无关的 1.8MB `layoutD-icon.png`（早前已知的待定去留文件），合并时已单独 commit(`bba4867`)移除。

- [ ] **FRAME-CANVAS-1 画布/PDF/PNG 追平 IDML 分框（连续正文合并显示）**（2026-07-08 用户验收 FRAME-SPLIT 时提出，**方案 A**，✅ 前置条件已就绪，可开工）
  - 背景：FRAME-SPLIT（已合 main）只在 **IDML 导出层**把连续正文合并成一个串接流框（用户 InDesign 验收过）；但 layoutD 引擎产帧仍是「每段落一个 PageFrame」（`LayoutEngine+TextFlow.swift` 的 `placeTextFrame`/`addText` 逐段 append），画布/PDF/PNG 直接画这些原子帧——用户在画布里看到连续正文仍是一段一个虚线框，**预览 ≠ 输出**，达不到「在 layoutD 里编辑也方便」的初衷。
  - **前置条件已完成（FRAME-CANVAS-0，Claude）**：断流分组逻辑已抽成跨模块共享函数 `groupIntoFlowFrames(pages:project:) -> FlowFrameGrouping`（`Sources/LayoutDEngine/FlowFrameGrouping.swift`），`LayoutDApp`/`LayoutDExport` 都能 import。`FlowFrameGrouping.groupsByPage[pageIndex]` 给出该页所有分组（`FlowFrameGroup.rect` = 合并 rect，`.memberFrameIndices` = 组内原始 frame 在 `pages[pageIndex].frames` 里的下标，按出现顺序）——本任务直接调用它，不用重新实现断流判定。IDML 导出器（`IDMLExporter.swift`）已改为消费同一份函数，两边行为保证一致。
  - 目标（方案 A，已用户拍板，**只做显示/交互聚合层，不改 engine 产帧/override/锁页模型**）：画布对每组连续正文（`groupIntoFlowFrames` 分组结果）画**一个合并的虚线框**（组内文字仍逐段渲染，渲染逻辑不用大改）；选中/移动时整组当一个交互单位；PDF/PNG 预览同理只改「画框」这一层。
  - 明确不做：不要把 engine 改成产出「一个多段落大 frame」（方案 B，高风险大重构，已否决）——PageFrame 仍是原子单位，只是显示层按组聚合。
  - 文件：`CanvasView+Drawing.swift`、`CanvasView+Interaction.swift`（选中/移动改按组）、`PDFExporter.swift`、`PNGExporter.swift`。
  - 验收：标准样章画布里，被标题/抽言断开的每段连续正文各显示为一个合并虚线框（不再一段一框）；点击/拖拽整组一起选中移动；单段落属性面板显示仍正确（组内取第一段或提示"多段落"，具体交互细节可自行判断但不能崩溃/误编辑）；全部测试/探针 PASS。

- [x] **SAMPLE-1 一键批量样张** — ✅ **重做版**（AG，`feature/ag-sample-1-v2` `10550c6`，Claude 审核合 dev `d85a730`）。首版打回重做（原因见下），v2 全部照做。
  - **交付**：CLI `--render-samples A.json B.json ... --chapter <fixture>`（默认 chapter=`Samples/fixture-standard-chapter.md`）→ 桌面出带方案名的样张 PDF。解析**只走** `StyleBaselineImporter.parseSpecPack`（唯一事实源，首版并行的 `SpecPack.swift` 已删）；新建**共享**应用函数 `BookProject.applySpecPack(_ result:)`（`LayoutDImport/BookProject+Tokens.swift`），`AppState.applyImportedTokens` 减 105 行改为委托它（单一应用路径）；补齐了 SPEC-PACK-1 没做的视觉三项——字体族（`fontResolutions`→复合中/西/数字字体）、角色色 + 装饰点缀色、开本 trim（`page.width/height`→`PageSetup`）；不支持字段打 stderr 告警不静默。
  - **验收全过**：`swift test` 291；`review-idml.sh` 14/14（新增 2g 掩码确定性探针）；桌面 3 份规范包一条命令出 3 份**视觉可区分** PDF（md5 各异、方案A/B/C 点缀色+字体不同）；重跑**内容确定**（见下）。
  - **打回原因（存档）**：首版（`feature/ag-sample-1` `299450b`，**未合 dev**）自建并行 `SpecPack.swift`（独立解析+`toBookProjectUpdates`），与 Codex 的 `parseSpecPack` 在同模块重复解析同 3 份 JSON。用户拍板收敛到单一解析器（见 DECISIONS 2026-07-07 12:57）→ 打回。
  - **PDF「重跑确定性」处理（用户 2026-07-07 拍板 = 方式1 内容级 + 掩码探针）**：Quartz PDFContext 给每份 PDF 盖 `/CreationDate`/`/ModDate`（秒级）+ 随机 `/ID`，字节级永不可复现（连朴素 `--export-pdf` 两次都不一致），属平台行为、非本代码问题。**不改 PDF 字节**（改字节要保等长否则毁 xref，遇压缩对象流还会静默失效——见 DECISIONS）。改为在 `review-idml.sh` 加 **2g 掩码确定性探针**：导出两次、抹掉这三处易变元数据后断言逐字节一致（已自证：未掩码≠、掩码后=），以内容级确定性验收。
  - **轻量提醒（不阻塞）**：v2 为拿 roleColors/装饰色**直接改了 `StyleBaselineImporter.swift`（+58，Codex 道文件）**——加字段、能跑、已合，但属跨道；后续该类字段扩展应回归 Codex。首版分支 `feature/ag-sample-1` 与其 worktree 停靠可清理。
- [x] **PERF-3 排版异步化 + 防抖** — ✅ AG `c99e48a`，排版及预检移出主线程，引入 150ms 防抖，支持首帧/测试环境同步回退。
  - 背景：每次改动全书重排两遍 + preflight 同步跑在界面线程（`AppState.recalculateLayout`），书稿变大会卡界面。
  - 目标：连续操作只排最后一次（防抖），layout/preflight 移出界面线程（异步化）；首帧仍同步保证打开即有版面；须防状态流里的 GUI 竞态（异步排版结果回来时用户可能已经切换了选中/页面）。
  - 文件：`AppState.swift`、可能 `CanvasView.swift`。
  - 验收：连续快速操作（如连续拖拽/连续按键）时界面不卡顿、只在停顿后触发一次真实重排；PERF-1 基准脚本仍 PASS；全部现有测试/探针 PASS。
- [ ] **PERF-4 引擎测量改造（CTTypesetter 逐行填充 + 测量缓存）** — 2026-07-05 从 Claude 道转来。风险最高，**Claude 审过 AG 提交的方案后追加了两条硬约束（见下），必须照做**。拆成 4a/4b 两棒，先做低风险的 4a，量够不够再决定动不动 4b。
  - **背景（Claude review 结论）**：`estimatedTextHeight`（LayoutEngine.swift:1121）用完整 `CTFramesetterSuggestFrameSizeWithConstraints` 测高，是 `(text, style, width, inlineRuns)` 的纯函数，缓存它安全。但 `fittingPrefix`（:544）的二分查找里，`bestCount` 会喂给下游 kinsoku/避头尾/孤寡行处理，改写断点算法有让分页悄悄错位的风险；且当前 golden 语料（PerformanceBenchmarkTests，只有正文/标题的中英混排）没覆盖首行缩进/竖排/行内粗斜体/图片环绕，"golden 过了"给不了真信心。

  ### [x] 4a｜测高缓存（已由 AG 于 feature/ag-perf4a-cache 完成）
  - 目标：给 `estimatedTextHeight` 加线程安全缓存（NSLock 保护），命中即跳过 CoreText framesetter 构建。整段能放下的段落走 `fittingPrefix` 的 early-return（:558 测一次高就返回），重排时全是缓存命中——这是 80% 收益来源。
  - **⚠️ 硬约束①（缓存钥匙必须完整，配错会静默算错分页）**：钥匙**不能**只用 `(text, fontName, fontSize, lineHeight, firstLineIndent, layoutDirection, width, inlineRuns)`。`makeAttributedString` 逐字调 `style.fontMapping(for:)`，按字符套不同字体 + `sizeMultiplier` + `baselineOffset`（复合字体）。**钥匙必须再纳入该样式整套复合字体映射的指纹**（family/fallback/每段 sizeMultiplier/baselineOffset），否则两个只有复合字体配置不同、fontName/fontSize 相同的样式会撞键，取到旧高度→分页错且无声。`InlineRun`/`InlineEmphasis` 标 `Hashable` 时要含 emphasis。
  - 文件：`Sources/LayoutDEngine/LayoutEngine.swift`（`estimatedTextHeight` + 缓存类）；如需给样式加指纹计算可加到 `Sources/LayoutDCore/`。
  - 验收：PERF-1 基准显著下降；全部现有测试/探针 PASS；**新增一个缓存正确性单测**：构造两个 fontName/fontSize 相同但复合字体映射不同的样式，断言其测高缓存不互相污染（同键必同高、异配置不撞键）。

  ### ~~4b｜`fittingPrefix` 二分改单次扫描~~ ⏸ **暂缓（用户 2026-07-05 决定：4a 已拿到 16% 提升，够用；高风险改动暂不追加，日后需要再评估）**
  - 目标：`overlaps.isEmpty` 分支里的二分查找（:562-577，每步重建 framesetter）改为 `CTTypesetterCreateWithAttributedString` + `CTTypesetterSuggestLineBreak` 单次逐行扫描取 `bestCount`。
  - **⚠️ 硬约束②（"断点 100% 一致"是待验证假设，不是承诺，先扩 golden 再动手）**：手写逐行循环要精确复现 framesetter 的四处细节，任一漏掉都会改断点：①第一行必须手工减掉 `firstLineHeadIndent`；②`CTTypesetterSuggestLineBreak` 默认算法 vs framesetter 的 `byWordWrapping` 在中英混排不保证逐字一致；③老高度是 `max(ceil(总高), lineHeight)`（有 ceil 取整 + 最小行高 + 末行 descent），不是"行数×行高"；④复合字体 sizeMultiplier 改字宽→改断点。**开工顺序强制为**：先把 golden 回归语料扩充到覆盖 {首行缩进、竖排 layoutDirection==.vertical、行内粗/斜/着重、图片环绕 overlaps 非空} 四类，跑通"改动前逐页字符区间+坐标 100% 一致"的 golden 比对基线，**再**动断点算法；改完该 golden 必须仍逐页全等。达不到 100% 全等就**不合**，退回 4a 收益即可。
  - 文件：`Sources/LayoutDEngine/LayoutEngine.swift`、`Sources/LayoutDCore/ChineseTypesetting.swift`、golden 语料测试（`Tests/`）。
  - 验收：扩充后的 golden 逐页字符区间+坐标改动前后 100% 一致；PERF-1 基准进一步下降；全部测试/探针 PASS。

- [x] **GUARD-2 断言闸字形覆盖检查（rule⑥）** — ✅ AG `b3a2e97`, 合 dev(8389c9c)
  - 背景：rule⑤ 已拦「字重不存在→Helvetica 豆腐」；还差「字体存在但缺 CJK 字形→豆腐」（脚注豆腐那类事故的自动网）。
  - 目标：`IDMLInvariants` 加 rule⑥——对每个注册字体用 CoreText 抽查文档实际用到的字符集样本（如每 Story 抽前 N 个 CJK 字符）能否出字形（`CTFontGetGlyphsForCharacters`），缺字形即 FAIL 并报出字体名+字符。
  - 文件：`Sources/LayoutDExport/IDMLInvariants.swift`、`Tests/LayoutDExportTests/IDMLInvariantsTests.swift`（⚠️ 跨道改导出文件——沿用 rule⑤ 先例，已知会 Claude）。
  - 验收：单测含正反例（CJK 字体过、纯拉丁字体配中文 FAIL）；全套测试 + `review-idml.sh` PASS。
- [x] **E2-4p 补完：对开左右页并排预览 + 版心镜像** — ✅ AG `77c595c`, 合 dev(8389c9c)。⚠️ 属渲染代码，PDF/PNG 对开左右页并排（文件名 page-NNN-MMM）已落地、单测过；待用户对开稿 PNG 肉眼确认并排定位（非阻塞）。
  - 目标：`facingPages` 开启时 Canvas/PDF/PNG 左右页并排、版心镜像（订口内侧）；关闭时与现状一致。
  - 文件：`LayoutEngine.swift`、`CanvasView.swift`、`PDFExporter.swift`、`PNGExporter.swift`。
  - 验收：对开稿导 PNG 左右页镜像正确；非对开零回归；单测断言镜像边距；`review-idml.sh` PASS。
- [x] **SPLIT-GUI 巨型 GUI 文件拆分**（由 AG 于 feature/ag-split-gui 分三棒完成）— ✅ 用户 2026-07-06 GUI 截图抽查通过，已随批合 main(`0bbda6c`)。
  - 目标：`main.swift`(1500 行，拆出 AppDelegate/菜单/WorkspaceViewController/CLI 各自文件)、`InspectorView.swift`(1600 行，按面板 section 拆)、`CanvasView.swift`(1400 行，拆出工具交互/绘制)。
  - 文件：`Sources/LayoutDApp/*`。
  - 验收：全部测试零修改通过；`review-idml.sh` PASS；GUI 行为无变化（拆完 Claude 出包给用户抽查）。
- [x] **FIX-CANVAS-1 画布图片标题前泄漏资产 id**（小修） — ✅ commit 0b3fb67
  - 文件：`Sources/LayoutDApp/CanvasView+Drawing.swift`（或相关渲染函数所在文件）。
  - 验收：画布显示「细胞结构示意」无 id 前缀；PDF/PNG 导出同步检查无此问题；全部测试/探针 PASS。

## Backlog（按车道路由）

- [x] **B1 图文绕排预览** — ✅ AG `099f38b`，Claude 审核合 dev（`09b8cc4`，2026-07-04）。详见归档；导出侧配对任务 = Claude 道 B1-IDML。
- ⏹ ~~B2 长表格分页~~ / ~~B3 索引~~ / ~~B4 引文样式~~ — 用户 2026-06-23 决定不做。

## 基础设施待办（Claude/用户）

- [x] **真正 CI** — ✅ `.github/workflows/ci.yml`（2026-06-23 起 push/PR 自动跑 review-idml.sh，macOS runner）。
- [ ] IDML 官方 RNG schema 校验（vendor `app.generateIDMLSchema()` 的 RNG 做名/枚举 lint）。golden 本地回归已并入 `review-idml.sh`（GOLDEN-GUARD，2026-07-07）；golden 进 CI 仍卡字体环境差异，见 ci.yml 注释。
- [x] relay `run_checks("test")` 末行误显「0 tests」 — ✅ Claude 2026-07-07 直接修了 `~/tools/relay-mcp/server.py`（正则捞出「Executed N tests」汇总行置顶显示；**重启 relay 后生效**）。
