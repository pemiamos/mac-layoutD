# 架构决策记录 Decisions Log
> 追加式，最新在最下方。

## 2026-06-19 10:00 | human(默寺)
- **决策**：git 写操作全部走 GitHub Desktop，AI 工具一律不碰 git。
- **理由**：防止三个 AI 在分支与提交历史上互相干扰；提交动作集中由人审。
## 2026-06-19 16:20 | claude
- **决策**：推翻 2026-06-19 10:00 那条「git 全走 GitHub Desktop、AI 不碰」。现政策:三个 AI 用各自 shell 自主完成 git 全流程(branch/add/commit/push/merge),run_checks 通过后自动提交、不打断;唯一例外是改写远端历史等难撤回操作(push --force、删远端分支、对已推送内容 rebase/reset --hard)需先说明。relay 服务器本身仍保持 git 只读。
- **理由**：用户 2026-06-19 明确要求放开,以提升三方接力效率。已同步全局 ~/.claude/CLAUDE.md、~/.codex/AGENTS.md、本项目 .ai/AGENTS.md+CLAUDE.md 与 relay 模板。分支隔离与提交质量改由各 AI 按 feature/<ai>-* 约定 + 提交后写 handoff 注明 commit 来保证。

## 2026-06-19 16:20 | claude
- **决策**：印前采用「路线 A:预检 + 诚实披露」,长期把 CMYK 分色 / PDF/X 合规外包给印厂或 Acrobat/PitStop;LayoutD 自身只产出高质量 RGB/PDF + PrepressInspector 预检告警,不自建 CMYK 色彩管线。不实现路线 B(自建 ICC/分色/专色/叠印)。
- **理由**：贴合路线图「external-tool division / 出版工作流」。对「中文科普书排版工具」定位,自建 CMYK 是数月工程且易做错反坑用户,性价比不对。PDFExporter 因此只嵌诚实 OutputIntent、不写 GTS_PDFXVersion/Conformance。**若未来要做路线 B,必须先 record_decision 显式撤销本条**——防止后续 AI 看到「没有真 CMYK」就擅自去建色彩管线、撞翻路线图。

## 2026-06-19 17:42 | claude
- **决策**：layoutD 主交付路线转向「灌版引擎 → 导出 IDML → InDesign 人工精调 + 印前输出」。layoutD 定位收敛为:用结构化模型 + AI 受控变体把「Figma 视觉规范 + 内容」自动灌成一份高质量初排,导出为 IDML(InDesign 可继续编辑的结构),交给 InDesign 做人工精调与印前。四点约束:①IDML 从 roadmap 的「结构参照」升级为一等导出格式;②layoutD 仍保留基本编辑工具(LayoutPlan/override 两层模型:选择/移动/缩放框、换图、改样式、组件化、锁页),用于交棒前出好初排,但不再追求 InDesign 级编辑深度,不再扩建重型自有编辑器;③这是单向流——layoutD→IDML→InDesign,改动不回流,交棒后 InDesign 成为真理源,layoutD 退为「初稿生成器」;④印前(CMYK 分色/PDF/X 合规)继续不自建,交 InDesign,本条强化而非撤销「印前路线 A」。
- **理由**：用户实践中发现两大痛点:CMYK 印前无好方案、人工精调需要一批成熟编辑工具,而 InDesign 在这两点上都远比自建成熟。导出 IDML 同时解决两者,且与 layoutD「结构化模型」本质天然对齐(Section/页→Spread/Page、文本框→TextFrame/Story、样式→ParagraphStyle、颜色 token→Swatch、固定页→MasterSpread),既复用了确定性引擎 + AI 受控变体的核心价值,又砍掉了重型编辑器与自建色彩管线两块大工程。唯一可能让方案崩掉的是 CJK 排版保真度(竖排、复合字体、避头尾、框架网格)能否干净落进 InDesign——因此先做最小验证 spike 证伪(v1:跨页+中文段落样式文本框+竖排文本框+置入图+CMYK Swatch;v2 再压测复合字体),验证通过再动架构。若未来放弃 IDML 路线,须先 record_decision 显式撤销本条。

## 2026-06-21 02:10 | claude
- **决策**：三个 AI 改用 git worktree 物理隔离工作副本。Claude=主仓库 mac-layoutD（集成区，dev/main）；Codex=mac-layoutD-codex（停靠 codex-lane）；Antigravity=mac-layoutD-ag（停靠 ag-lane）。三副本共享同一个 .git。四处 relay 配置的 RELAY_PROJECT_ROOT 已分别改指各自副本：Codex 的 ~/.codex/config.toml；Antigravity 的 ~/.gemini/config/mcp_config.json、~/.gemini/antigravity-ide/mcp_config.json、~/.gemini/antigravity/mcp_config.json；Claude 的 .mcp.json 不变。改前都做了 .bak-worktree 备份。新分工：Codex/Antigravity 只在自己副本+自己 feature 分支提交，不合 dev/main、不必 push；dev 与 main 的合并、交接日志冲突解决统一由 Claude 做，用户视觉验收后 Claude 才合 main。
- **理由**：此前三个 AI 客户端 + 用户的 git GUI 工具都指向同一个本地工作目录，观察到一次并发 git checkout 导致 commit 误落到别的分支（cherry-pick 纠正，无数据丢失）。worktree 给每个 AI 独立的 checked-out 分支，谁切分支都不影响别人，从物理层面消除"HEAD 被切走"的风险。共享 .git 让 Claude 在主仓库本地就能看到两道分支，无需互相 push。把 dev/main 合并集中到 Claude，顺带解决了 .ai/HANDOFF.md 每次合并都冲突的老问题（两道不再触发该冲突）。relay 各指各自副本，保证 run_checks/git_status 报告的是该 AI 自己的工作树。回滚：git worktree remove + 用 .bak-worktree 还原四处配置。注意：Codex 与 Antigravity 需重启应用让新 RELAY_PROJECT_ROOT 生效。

## 2026-06-21 11:06 | claude
- **决策**：worktree 隔离是「按 AI」不是「按对话」，补三条并发铁律（N1/N2/N3，已写入 .ai/AGENTS.md 隔离章节）：N1 同一仓库不开两个同-AI 对话，必须并发则第二个对话带独立 worktree，禁止两对话共用同一 checkout；N2 集成/审核/试合一律在专用临时 worktree（git worktree add --detach /tmp/...-wt dev，且必 test -d 校验创建成功再 cd，失败别让命令落回主仓库），收尾 remove；N3 动手集成前 get_current_status()+git_status() 探并发，长集成前 record_decision() 占位当软锁。
- **理由**：2026-06-21 实测吃亏：两个 Claude 对话同时用主仓库 mac-layoutD（一个合 E3-4 到 dev、一个做审核），导致 HEAD 被对方切走、git add -A 误吞对方未提交改动、worktree add 失败后命令误落主仓库误建废弃分支。已有的「三 AI 各持 worktree」隔离防不住「同 AI 多对话并发」这个盲区。N2 的专用临时 worktree 配方能同时根除「两对话撞车」与「命令误落主仓库」两类事故——本次最后改用 detached worktree 后即再未出事。

## 2026-06-21 11:22 | claude
- **决策**：「锦上添花」批排进开发计划（2026-06-21 用户确认）：E3-6 目录动态化 → D-2 DOCX 导入 → E2-5 美术页MasterSpread/蒙版 → E2-4 对开跨页（风险最高放最后），均 Codex 道按此顺序接力。E3-8 token→CMYK 色板暂缓（先不做，印前转色交 InDesign，非阻塞）。E3-9 约物挤压维持原排期不在本批。
- **理由**：用户盘点进度后决定把锦上添花层除 CMYK 外全部纳入正式计划。排序按依赖与风险：TOC 自包含先做；DOCX 独立新文件可并行；美术页蒙版中等；对开跨页风险最高（可能打破当前干净分页）放最后单独一棒并先验非对开无回归。CMYK 暂缓因印前本就交 InDesign、非交付阻塞。

