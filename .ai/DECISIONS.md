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

## 2026-06-21 11:26 | claude
- **决策**：E2-4 对开跨页改由 Claude 直接做（用户 2026-06-21 指定，不再由 Codex 做）。因 E2-4 改 IDMLExporter.swift（Codex 负责文件），跨道协议：Claude 须等 Codex 本批 IDMLExporter 改动（E3-4b/E3-6/E2-5）先合进 dev 再起手，在专用 worktree+feature 分支上做（守 N2），避免同文件两道并行冲突。E3-6 已展开为两层验收：1) 结构化目录段落（tab+点导引线，专属 TOC 段落样式）；2) 输出 <TOCStyle> 资源映射 heading1/heading2 让 InDesign「更新目录」可重建。
- **理由**：用户判断 Codex 在高风险任务上不靠谱，对开跨页风险最高（可能打破当前干净分页），交 Claude 直接做更稳。代价是 Claude 要碰 Codex 负责文件 IDMLExporter，故用「等本批先合 dev + 专用 worktree」的时序隔离规避冲突——E2-4 本就排最后，时序天然吻合。

## 2026-06-21 11:40 | claude
- **决策**：分工再平衡（2026-06-21 用户决定，因 Codex 多次提交不靠谱需反复回修）：① Codex 砍到最少、只留隔离低风险任务——当前仅 D-2 DOCX 导入（全新独立文件，不碰现有导出）；② 原 Codex 的高风险 IDMLExporter 导出任务 E3-4b/E3-6/E2-5 全部改判 Claude 直接做（连同已改判的 E2-4），Claude 串行、各自专用 worktree，顺序 E3-4b→E3-6→E2-5→E2-4；③ AG 升为主力，预览+GUI 全线连续作业，本批序列 E3-10p→E3-6p 目录预览→E2-5p 蒙版预览→E2-4p 对开预览→导出选项面板（②③④为配对 Claude 导出侧的预览追平任务）。
- **理由**：Codex 代码质量不稳定、回修成本高，故收缩其职责到 blast radius 最小的隔离任务（新文件 DOCX 导入，botch 也不伤现有导出、易回修）；高风险导出收进可靠的 Claude 手里且串行避免同文件冲突；AG 质量可靠且预览/GUI 是其专长，升主力承接最多任务，配对预览让「预览=输出」持续推进。文件边界：Claude=IDMLExporter 导出侧、Codex=新 DOCX 导入文件、AG=LayoutEngine/渲染器/GUI，三方仍不重叠。

## 2026-06-21 15:43 | claude
- **决策**：根治文档冲突卡死：① .ai/HANDOFF.md 与 .ai/DECISIONS.md 在 .gitattributes 设 merge=union（append-only 日志两边自动保留、永不冲突）；② .ai/QUEUE.md 归 Claude 独占维护，Codex/Antigravity 不再编辑它（不勾 [x]、不挂 [~]），进度只写进 write_handoff，由 Claude 据交接更新队列；③ 各道同步 dev 仍跑 git merge origin/dev，不碰 QUEUE.md 即干净；万一仍冲突，git checkout --theirs .ai/QUEUE.md 取 dev 权威版后继续，别硬解。已写入 .ai/AGENTS.md 铁律 8。
- **理由**：2026-06-21 AG 开工 git merge origin/dev 时在 QUEUE.md/HANDOFF.md 撞冲突、自行解冲突卡死（界面停在 Working）。根因：Claude 在 dev 频繁改 QUEUE.md 排任务，各道也改 QUEUE.md 勾完成 → 每次同步必冲突，而 lane AI 不擅长解冲突。union 解决 append-only 日志；QUEUE 由单一所有者（Claude）维护消除冲突源。

## 2026-06-21 | codex | D-2 DOCX 导入采用内置最小 OOXML ZIP 读取器
- **决策**：`.docx` 读取在 `DOCXBookImporter.swift` 内实现最小 ZIP central-directory reader；支持 stored 与 deflate entry，并用 macOS `Compression` 解压。首版只读取 `word/document.xml`、`word/styles.xml`、`word/numbering.xml`，不调用外部 `unzip`。
- **理由**：当前 Swift Foundation 环境没有 `Archive` API；引入第三方 ZIP 包或外部进程会扩大依赖面。最小读取器可离线、可测试，且足以完成 D-2 的正文/样式/列表/表格映射。Zip64、加密、图片 media 与其它 OOXML 部件首版明确降级或报错。
## 2026-06-21 17:28 | claude
- **决策**：不再追求着重号(傍点/Kenten)在 InDesign 的渲染——用户图书项目一般不用着重号,需要时在 InDesign 手动加。E3-3v(傍点 InDesign 渲染)就此停止投入(KentenKind 属性仍写进 IDML 保留作者意图、layoutD 预览仍画点,但不再为"InDesign 端是否出点"花精力);表格内傍点同理。表格内粗体也不死磕(一键手动)。确立通用原则:是否为某保真坑较真,看 (该特性在真实图书里的使用频率) ×(在 InDesign 手动改的成本会不会随书规模放大)——常用且改起来不 scale 的才在 layoutD 导出端弄对;罕用或一键可改的留给 InDesign 最后顺手做(InDesign 本就是最终真理源)。
- **理由**：2026-06-21 用户明确:图书项目一般不用着重号。layoutD 定位是灌版引擎、InDesign 是最终精调真理源,故不值得为罕用特性的 InDesign 端渲染死磕(那是反复踩的"属性在视觉无"高发坑,投入大回报小)。把有限精力放在常用且手动改不 scale 的特性上(竖排/复合字体/脚注/表格结构/动态目录等已做)。

## 2026-06-23 13:48 | claude
- **决策**：不外化 ExtendScript/UXP API 到项目;主交付仍为 IDML→InDesign。改为三层保真策略,从①入手:①灌版打包前加"不变量断言闸"(把已知跨属性渲染搭档规则锁成硬检查+CoreText 字体/字形覆盖检查,不依赖 InDesign);②InDesign 往返 golden-file diff 真值机(唯一能发现新"属性在渲染死"搭档规则的办法,每功能开一次 InDesign);③可选:vendor IDML RelaxNG(app.generateIDMLSchema)做 Swift 名/枚举 lint+收编 ~40-50 个 $ID/ 暗号。明确不做:不外化 ExtendScript/UXP API(描述的是内存脚本 DOM,非我们 emit 的 IDML 磁盘格式);不把交付改成 .jsx 脚本(XL 重构,丢掉已验收+可移植+可无头测试的 IDML 路线)。
- **理由**：10-agent 工作流(6 查证+1 架构+3 对抗验证,全部 claimHolds=true)逐行核对仓库实证:已翻车的三 bug(着重号 8ce89a8/脚注 d449077/粗斜体 b567808)名字全合规范,病根是 InDesign 渲染偷偷要求的"搭档属性"缺失(着重号需 World-Ready 排版器;脚注需复合字体样式;CJK 粗斜体需 FauxBold/Skew)。任何规范(API/IDML schema)都只逐属性校验、不编码跨属性渲染前置条件 → 外化规范只消除 ~10-20% 痛(拼写/枚举/类型),对真正反复翻车的"属性在渲染死"~0% 帮助。且 ExtendScript/UXP 描述的是内存 DOM,对不上我们 emit 的 IDML 磁盘格式;要给 IDML emit 配机读规范应 vendor IDML RNG 而非 API types。

## 2026-06-23 14:12 | claude
- **决策**：B 工程健壮性完成合 main(e4a16bd)：Fonts.xml 导出确定性修复 + GitHub Actions CI(macOS,review-idml.sh) + golden-file 本地回归 + 测试硬编码路径修复(CI 首跑照出)。同时启动 Backlog 并按车道路由：B1 图文绕排/B2 长表格分页 → AG(LayoutEngine+渲染器侧)；B3 索引/B4 参考文献 → Claude/Codex(导入+IDML导出侧,非 AG 文件)。AG 现役 B1 图文绕排预览(横排矩形绕排,CoreText 非矩形 path framesetting,不碰 IDMLExporter)。
- **理由**：Backlog 四项按文件边界分流避免跨道：图文绕排/长表格分页核心在 LayoutEngine+渲染器(AG 地盘)，索引/参考文献核心在导入+IDMLExporter(Claude/Codex 文件,派 AG 会违反隔离)。图文绕排选作 AG 现役因其科普书价值最高且可用 CoreText 非矩形 path 优雅实现(渲染器已用 framesetter)。导出侧 TextWrapPreference 拆成配对 Claude 任务,保持单文件单道。

