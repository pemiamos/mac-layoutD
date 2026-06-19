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

