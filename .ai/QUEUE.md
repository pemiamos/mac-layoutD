# 任务队列 Task Queue（Codex 自助接力用）

> 目的：让开发更自动化。Codex 不必每轮等 Claude 手喂任务——读本文件，领最上面**未打勾**的任务做。
> Claude 维护本队列与每项的「目标/文件/验收」；做完后 Claude 批量审核。
> 队列顺序 = 优先级；越靠上越先做。

## 流程铁律（每一棒都照做）

**Codex（执行）每领一个任务：**
1. `read_latest_handoff()` + 读本文件，领最上面未打勾任务。
2. 起 `feature/codex-<task>` 分支。
3. 实现 + 写**端到端验收**（不能只靠单测——本项目踩过「单测全绿但功能坏」的坑）。
4. **必须** `bash scripts/review-idml.sh` 本地 PASS 后才提交（这就是 Claude 审核要跑的同一套）。
5. commit（feat/fix 规范）+ `write_handoff` 注明 commit hash。
6. 能连续跑就接着领下一个；不能就停，等下次被唤起。

**Claude（审核）批量做：**
1. 攒几个 `feature/codex-*` 分支一起审。
2. 每个分支跑 `scripts/review-idml.sh`：全绿才算过；有 FAIL 把精确 repro 退回交接。
3. 过的合进 `dev` 集成分支（不直接进 main）。
4. `dev` 攒一批后交你/Antigravity 在 InDesign 做**视觉验收**（无头验证不了渲染对错，这关必须人看）。
5. InDesign OK → Claude 合 `dev` → `main` 并 push。

**分工边界**：Codex 写代码；Claude 审核 + 合并 + 维护队列；你/Antigravity 做 InDesign 视觉验收。

---

## 进行中 / 待集成

- [x] **行内格式 阶段1**（粗体/斜体 → IDML CharacterStyleRange，含 CJK 单分隔符）— commit `9e4f269`，已审核 PASS，在 `dev` 集成分支**等 InDesign 视觉验收**。

## 队列（按优先级）

- [ ] **E3-1 行内格式补全到所有 block**
  - 目标：当前只普通正文段落持久化 inlineRuns；扩到标题/列表/引用/callout。先抽一个统一的 `Paragraph` 构造 helper，再让所有 Markdown block 分支走它。
  - 文件：`Sources/LayoutDImport/MarkdownBookImporter.swift`、`Sources/LayoutDCore/BookProject.swift`(如需)。
  - 验收：`printf '## **粗**标题\n\n- 列表*斜*项\n> 引用**强调**\n'` 导出 IDML 后，标题/列表/引用里的强调都出对应 FontStyle；`scripts/review-idml.sh` PASS。

- [ ] **E3-2 行内格式预览渲染**
  - 目标：PDF/PNG/Canvas 三处预览按 `inlineRuns` 切粗/斜（当前预览整段同字重，仅 IDML 已保真）。引擎 `addText`(LayoutEngine.swift) 若需精确测量，把 run 透传进 measurement（已按字符类切复合字体，扩成叠加 emphasis）。
  - 验收：含粗/斜的页 PNG 里目标词字重不同（你/Antigravity 视觉验）；单测断言渲染层收到 run。

- [ ] **E3-3 傍点（Kenten 着重号）**
  - 目标：`InlineEmphasis.kenten` 落地——定一种 Markdown 语法（如 `==着重==` 或约定）→ 解析成 kenten run → IDML 用 `KentenKind`/着重号属性输出 + 预览画点。
  - 验收：着重段导出 IDML 在 InDesign 显示傍点（人工验）。

- [ ] **E3-4 原生表格 Table**
  - 目标：table 组件从「当文字导」升级为 IDML 原生 `<Table>/<Cell>`（行列/边框/底色），可在 InDesign 调列宽。
  - 验收：demo 里表格导出后在 InDesign 是真表格、可选列。

- [ ] **E3-5 页眉/页脚/自动页码**
  - 目标：running header/footer + 页码（folio）映射到 MasterSpread 的页码文本变量，跨页自动。
  - 验收：多页书导出后 InDesign 主页有自动页码 + 章节页眉。

- [ ] **E3-6 目录（TOC）**：当前目录是死文字；改为 InDesign 动态 TOC（或至少正确的 TOC 段落样式 + PageReference）。
- [ ] **E3-7 脚注**：`anchoredFootnoteIds` → IDML 脚注。
- [ ] **E3-8 token → CMYK 色板**：颜色当前导 RGB swatch；增可选项由 token 算 CMYK 值发 `Space="CMYK"` 色板，减少 InDesign 人工转色（不自建色彩管线，只发数值）。
- [ ] **E3-9 约物挤压 + 基线网格对齐**：Mojikumi 标点间距集 + 段落「对齐基线网格」映射进 IDML，使 InDesign 排版与 layoutD 预览一致。
- [ ] **E2-4 对开跨页（facing spread）**：按 `pageSetup.facingPages` 生成 2 页 spread + 起始页码 Section。风险高（可能回退干净分页），单独一棒、重点 InDesign 验收。
- [ ] **E2-5 固定美术页 → MasterSpread / 非矩形蒙版**：满版图/扉页固定页映射；扇面/八角图框 PathGeometry 蒙版。

---

## 基础设施待办（Claude/用户）

- [ ] 真正 CI（GitHub Actions 跑 `scripts/review-idml.sh`），把审核从「人工记得跑」变成 push 即跑。
- [ ] IDML 官方 RNG schema 校验 + golden-file 回归基线，补强 `review-idml.sh`。
- [ ] relay `run_checks("test")` 末行误显「0 tests」，改回显 XCTest 汇总行。
