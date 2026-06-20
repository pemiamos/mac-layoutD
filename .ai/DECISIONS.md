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

