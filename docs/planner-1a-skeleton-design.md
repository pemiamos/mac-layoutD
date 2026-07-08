# PLANNER-1a-DESIGN · 对开骨架词表设计文档

> 状态：设计（先设计后动手，形态参考 RENDER-CORE-1）。作者 Claude @ `feature/claude-planner-1a-design`，2026-07-09。
> 关键路径：`SPEC-PACK-2 → **PLANNER-1a** → PLANNER-1b → REROLL-1 → PILOT-3`。
> 本文档定义**约 7 个对开骨架 + 灰盒线框图渲染方案 + GUI 圈选交互**，并倒推 `layoutGrammar` 对 SPEC-PACK-2 的 schema 需求。
> 消费方：PLANNER-1a-IMPL（AG，落地骨架 + 线框图 + 圈选界面）、PLANNER-1b-DESIGN（Claude，受控变体规划器）。

---

## 0. 为什么以「对开」为单位

现状 `PageLayoutTemplate`（`textLedPage/imageLedPage/balancedImageText/knowledgeCardPage`）是**单页**模板，每个出 `variation 0/1` 两版（镜像）。真书翻阅时读者一次看到的是**一对页（spread）**——左右页的图文配比、大图气口、书脊镜像、章节开篇的非对称留白，都是**对开级**的决策。单页模板永远算不出「左页正文 + 右页大图跨到书脊」这种关系。

因此规划的原子单位从**页**升级为**对开**（见 [[layoutd-positioning-initial-pour]]、queue 批次 P 铁律「以对开为单位规划，非单页」）。一个**对开骨架（SpreadArchetype）**描述：
- 左页、右页各自的**槽位（slot）布局**；
- 跨页关系（书脊镜像轴、图片是否跨书脊出血、页眉/页码在对开上的镜像）；
- 允许的**参数变体**（镜像 / 图片档位 / 抽言位）——这三个参数正是 queue 点名的变体维度。

对开骨架 **不产出最终 `LayoutPlan`**；它产出的是**受约束的候选空间**，PLANNER-1b 的受控抽签在这个空间里按内容指纹选一版。这样 1a 负责「有哪些合法骨架」，1b 负责「这一对开该用哪个」。

---

## 1. 坐标与几何约定

沿用现有 `Rect(x,y,width,height)`（`Sources/LayoutDCore/PageSetup.swift`），**归一化到单页 0…1**，与 `PageLayoutTemplate.makePlan` 现有词汇完全一致（正文常用 `x≈0.08…0.10`、`width≈0.80`）。对开在此之上加一层：

- **页位 `pageSlot`**：`.left` / `.right`。一个对开骨架 = 有序二元组 `(leftPage, rightPage)`，每页是一组归一化 block。
- **书脊侧**：左页的 `inner` 边是 `x=1.0` 侧，右页的 `inner` 边是 `x=0.0` 侧。镜像与跨书脊出血都相对书脊定义。
- **跨书脊出血 block**：`bleedAcrossSpine=true` 的图片 block，左右页各留一半，渲染/导出时按对开 spread 拼合（真 spread 已由 `E2-4`/`SPREAD-1` 支持，见 queue）。1a 只需在骨架上标记，几何交给 1a-IMPL 按 `pageSetup.facingPages` 落地。

> 落地时 `LayoutTarget` 用现有 `.spread(Int)`（`LayoutPlan.swift:98`）承载对开；每页 block 仍写进各自页的 `LayoutPlan`。1a-IMPL 复用 `PageLayoutTemplate.makePlan` 的 block 生成词汇，只是把「单页 + variation」升级为「对开 + 参数」。

---

## 2. 槽位词表（Slot Vocabulary）

骨架由**槽位**拼成。槽位是「角色 + 归一化框 + 允许的内容类型」，映射到现有 `LayoutPlanBlock.kind/role`：

| 槽位 slot | kind | role | 说明 | 对应 motif（SPEC-PACK-2） |
|---|---|---|---|---|
| `body` | `.text` | `body` | 串接正文流（**永远一条河**，见 §6 铁律） | — |
| `heroImage` | `.image` | `hero` | 主图，可跨书脊出血 | — |
| `supportImage` | `.image` | `supporting` | 配图（图集/均衡用） | — |
| `caption` | `.caption` | `caption` | 图注 | `captionTick`（顶部短横） |
| `pullQuote` | `.text` | `pullQuote` | 抽言 | `pullQuoteRule`（左侧竖线） |
| `heading` | `.text` | `heading{1,2,3}` | 章名/节名/文章名 | `headingRule`（标题下划线） |
| `intro` | `.text` | `introduction` | 开节概述 | — |
| `knowledgeCard` | `.component` | `knowledgeCard` | 知识卡片/边栏 | — |
| `ghostNumber` | `.text` | `chapterNumber` | 超大 ghost 章节号（压底层） | `chapterNumber` |
| `sectionNumber` | `.text` | `sectionNumber` | 节序号「01 /」 | `sectionNumber` |
| `header` | `.component` | `header` | 页眉 chrome（章名·刊名·细线） | `header` |

后 3 个（ghostNumber/sectionNumber/header）是 queue 批次 V「视觉标识层」的 motif，骨架上是**可选装饰槽**——只有当 spec pack 提供了对应 motif、且该骨架声明了该槽位，才渲染。骨架本身不硬编码 motif 样式，样式全走 spec pack。

---

## 3. 七个对开骨架（Archetype Family × 参数）

每个骨架有一个**家族 `family`**（对齐现有 `LayoutStrategy`）+ 三维**参数**：

- **`mirror`（镜像）**：`false` 固定 / `true` 允许左右整体翻转（1b 抽签时可选镜像版，防单调）。
- **`imageTier`（图片档位）**：`.none / .small / .medium / .large / .fullBleed` —— 主图占位面积档位（小图≈0.25 页宽、中图≈0.5、大图≈0.75、跨页出血≈跨书脊）。
- **`pullQuotePosition`（抽言位）**：`.none / .top / .middle / .inlineLeft` —— 抽言在版心的位置。

家族 + 参数组合出**受控候选空间**；下表是 7 个家族的基线定义（几何为示意归一化值，1a-IMPL 按 spec pack 网格/版心校准）。

### A1 · 章节开篇对开 `chapter-opener`（family: `opener`）
非对称。左页大量留白 + `ghostNumber`（压底）+ `heading1`(章名) + `intro`(开节概述)；右页 `body` 起始 + 可选 `supportImage`。
- 固定 `mirror=false`（开篇的非对称是设计意图，翻转会破坏）。
- 承载 motif：`chapterNumber` / `header` / `sectionNumber`。
- 参数：`imageTier ∈ {.none,.small,.medium}`（右页配图档位）；`pullQuotePosition=.none`。
- 用途：每章第一对开。1b 强制每章起始用本骨架。

### A2 · 正文流对开 `running-text`（family: `textLed`）
主力骨架。左右页均为版心两栏 `body`，无主图或仅 `.small` 配图。可挂一个 `pullQuote`。
- `mirror` 无意义（对称），置 `false`。
- 参数：`imageTier ∈ {.none,.small}`；`pullQuotePosition ∈ {.none,.top,.inlineLeft}`。
- 用途：连续正文段落。占比最高，`weight` 最大。

### A3 · 图文均衡对开 `text-image-balanced`（family: `balanced`）
一页正文主导，另一页中图 + 图注。
- `mirror=true`（图可在左或右）。
- 参数：`imageTier ∈ {.medium,.large}`；`pullQuotePosition ∈ {.none,.top}`。
- 用途：解释密度高的内页。对应现有 `balancedImageText` 的对开升级。

### A4 · 大图气口对开 `hero-spread`（family: `imageLed`）
一张大图/跨书脊出血图 + 图注 + 短文。全书的「气口」（呼吸页）。
- `mirror=true`。
- 参数：`imageTier ∈ {.large,.fullBleed}`；`pullQuotePosition=.none`。
- 用途：章节转折、视觉高潮。1b 节奏规则控制「每 N 对开至少一次大图」（`rhythm.bigImageEveryMinSpreads`）。

### A5 · 图集对开 `gallery-grid`（family: `imageLed`）
2–4 张图网格排布 + 各自图注，少量说明文字。
- `mirror=true`。
- 参数：`imageSlots ∈ {2,3,4}`（图集专属，见 §4 schema）；`imageTier=.small`；`pullQuotePosition=.none`。
- 用途：多图并置（步骤图、对比图、图鉴）。

### A6 · 抽言强调对开 `pullquote-feature`（family: `balanced`）
大号抽言作视觉锚 + 正文流环绕。
- `mirror=true`。
- 参数：`pullQuoteSlots=1`（大号）；`imageTier ∈ {.none,.small}`；`pullQuotePosition ∈ {.middle,.top}`。
- 用途：强调金句、章节小结引言。

### A7 · 知识卡片对开 `knowledge-card`（family: `knowledgeCard`）
边栏卡片/知识框 + 正文。
- `mirror=true`（卡片可在左或右）。
- 参数：`imageTier ∈ {.none,.small}`；`pullQuotePosition=.none`；卡片档位 `.sidebar / .fullColumn`。
- 用途：定义、要点、复习页。对应现有 `knowledgeCardPage` 的对开升级。

> **为什么是 7 个**：覆盖真书对开的全部基本节奏——开篇（A1）、正文河（A2）、图文咬合（A3）、气口（A4）、多图（A5）、金句（A6）、知识块（A7）。少于此覆盖不全，多于此参数空间冗余、1b 抽签防单调更难。用户圈选时可再裁剪（§5）。

---

## 4. 数据模型 · 倒推 SPEC-PACK-2 的 `layoutGrammar` schema

spec-pack-guide 现有草稿：`spreadArchetypes[].{id,displayName,family,pages,imageSlots,pullQuoteSlots,mirror,weight}`。本设计**倒推**以下补充需求给 SPEC-PACK-2（Codex 道总闸），确保骨架能被完整表达且**每字段有消费者**：

```jsonc
"layoutGrammar": {
  "spreadArchetypes": [
    {
      "id": "hero-spread",            // 必填，唯一（现有校验保留）
      "displayName": "大图气口对开",   // 必填
      "family": "imageLed",           // 枚举，对齐 LayoutStrategy（见下）
      "pages": 2,                     // 固定 2（对开）；≠2 进 unsupportedFields
      "imageSlots": 1,                // 主图槽数（A5 图集可 2–4）
      "pullQuoteSlots": 0,            // 抽言槽数
      "mirror": true,                 // 是否允许左右翻转变体
      "weight": 0.8,                  // 抽签权重（1b 用）；>0
      // —— 本设计新增的参数轴（需 SPEC-PACK-2 支持，否则进 unsupported）——
      "imageTiers": ["large","fullBleed"],       // 允许的图片档位（§3 参数）
      "pullQuotePositions": ["none"],            // 允许的抽言位
      "carriesMotifs": ["header"],               // 声明本骨架渲染哪些 motif 装饰槽
      "role": "breathing"                        // 语义标签：opener/workhorse/breathing/feature/reference
    }
  ],
  "rhythm": {
    "maxSameFamilyRun": 2,           // 相邻同家族上限（现有）
    "bigImageEveryMinSpreads": 3,    // 大图气口最小间隔（现有）
    "accentEverySpread": true,       // 每对开至少一处 accent（现有）
    "openerAlwaysArchetype": "chapter-opener", // 新增：每章起始强制骨架
    "seed": "content-fingerprint-v1" // 固定种子（1b 确定性，现有）
  }
}
```

**给 SPEC-PACK-2 的明确需求**（写进 handoff 交 Codex）：
1. `family` 收敛为枚举，与 `LayoutStrategy`（`textLed/imageLed/balanced/comparison/knowledgeCard/fullPageImage/titlePage/cover`）+ 新增 `opener` 对齐；非法值报 JSON path 错误。
2. 新增字段 `imageTiers`、`pullQuotePositions`、`carriesMotifs`、`role`、`rhythm.openerAlwaysArchetype` —— **要么解析落地、要么明确进 `unsupportedFields`**，禁止静默忽略（遵循现有诚实上报机制，见 [[fidelity-investment-principle]] 与 guide「禁止装饰性空字段」）。
3. `imageTiers` 值域 `{none,small,medium,large,fullBleed}`；`pullQuotePositions` 值域 `{none,top,middle,inlineLeft}`；`carriesMotifs` 元素必须在 `motifs` 里存在，否则报错。
4. 校验：`spreadArchetypes` 非空时 `id` 唯一（现有）；`weight>0`；`imageSlots≥0`；至少有一个 `role:"workhorse"`（否则整本书没有正文河骨架，应报警告）。

> 若 SPEC-PACK-2 暂不支持新增字段，1a-IMPL 落地时用**内置默认骨架表**（本文 §3 的 7 个作为代码内 fallback），spec pack 未提供 `layoutGrammar` 时用默认；提供了就覆盖。这样两个任务解耦，不互相阻塞。

---

## 5. GUI 圈选交互（站4 · 骨架审批）

向导站4：用户看到 7 个骨架的**灰盒线框图**，圈选（勾选/启用）本书采用哪些骨架，并可调权重。审批结果写回 spec pack 的 `layoutGrammar.spreadArchetypes`（启用集合 + 权重），供 1b 抽签。

### 交互
- **线框图画廊**：7 张灰盒线框缩略图（对开比例），每张下方 `displayName` + `role` 标签 + 一句用途。
- **圈选**：每张左上角一个勾选框（默认全选）。取消勾选 = 从本书骨架池移除（写 `enabled:false` 或从数组剔除）。
- **权重滑杆**：每个启用骨架一个 `weight` 滑杆（0.2…2.0，默认取 §3 建议值）。A2 正文流默认权重最高。
- **参数预览**（可选，1a-IMPL 视工作量）：点开一个骨架，展开它的参数变体（镜像/图片档位/抽言位）小样，让用户圈选允许的变体子集。
- **约束提示**：若用户取消了所有 `role:"workhorse"` 骨架，红字警告「本书没有正文骨架，正文将无处安放」，禁止进入站5。

### 落盘
审批结果通过现有 `SpecPackImportResult` / spec pack JSON 回写 `layoutGrammar`；不引入新的持久化格式。GUI 层复用 `WizardView`（AG 刚完成 STYLE-LOCK-1 的站4 面板已在此），本步骤挂在站4「骨架审批」子面板。

---

## 6. 灰盒线框图渲染方案

线框图是**纯结构示意**，不含真实文字/图片，让用户一眼看清骨架的图文配比与节奏。

### 渲染规则（各槽位画法）
| 槽位 | 灰盒画法 |
|---|---|
| `body` | 浅灰底 + 若干等距水平细线（模拟文字行），两栏画两组 |
| `heroImage`/`supportImage` | 中灰底 + 对角交叉线（✕，摄影占位惯例）+ 角标图片图标 |
| `caption` | 单条短水平线 + 顶部 `captionTick` 小竖线（若 motif 启用） |
| `pullQuote` | 描边框 + 左侧明黄竖线（`pullQuoteRule`）+ 2–3 条粗水平线 |
| `heading` | 一条粗水平线（长度=标题宽）+ 底部下划线（`headingRule`，若启用） |
| `ghostNumber` | 超大淡灰数字「03」压在底层（`opacity` 取 motif 值） |
| `sectionNumber` | 小号明黄「01 /」 |
| `header` | 顶部细横线 + 左右两端小字块（章名 · EXPLORE） |
| 书脊 | 对开正中一条淡虚线（书脊参考） |

### 实现建议（给 1a-IMPL）
- **共享一套绘制**：线框图应走 RENDER-CORE-1 规划的「页面→绘制指令→薄适配」路径（若 RENDER-CORE-1 已落地则复用；未落地则先写独立的 `WireframeRenderer`，接口对齐将来迁移）。避免又制造一个「四渲染器各画一遍」的追平任务（教训见 queue RENDER-CORE-1 说明、[[idml-multicolumn-frame-grouping]]）。
- **输入**：`SpreadArchetype` + spec pack `motifs`（决定装饰槽是否画）+ 目标对开比例（来自 `pageSetup`）。
- **输出**：GUI 里 `NSImage`/`CALayer` 缩略图；同一函数出一张 headless PNG 供样张/文档用。
- **确定性**：纯函数，同骨架同输出（与 1b 的固定种子铁律一致，见 §7）。

---

## 7. 铁律与约束（落地不可破）

沿用 queue 批次 P 对 PLANNER-1b-IMPL 的三条硬约束，1a 的骨架设计必须**先天满足**，否则把坑留给 1b：

1. **正文永远一条河**：骨架只定义 `body` 槽的**几何框**，串接文流由现有 THREAD-1b 机制承载（见 [[layoutd-positioning-initial-pour]]）。骨架**不得**把正文切成互不串接的独立框——多个 `body` 槽必须声明串接顺序（`nextThreadedBlockId`/`previousThreadedBlockId`，`LayoutPlanBlock` 已有字段）。
2. **纯函数、可确定性**：骨架 → 候选几何是纯函数，无 `Date.now`/随机；变体选择由 1b 的固定种子驱动。否则 golden/逐字节护栏全废（[[idml-multicolumn-frame-grouping]] 同源教训）。
3. **端到端验收，不只靠单测**：1a-IMPL 的验收必须真出线框图 PNG 肉眼核对 + 圈选写回 spec pack 后 1b 能读到（本项目踩过「单测全绿功能坏」，见 [[visual-verification-not-automatable]]）。
4. **motif 不硬编码**：骨架只声明「有没有这个装饰槽」，样式（色/字号/透明度/锚点）全部来自 spec pack `motifs`。换 spec pack（方案 A/B/C）应换出不同视觉，骨架不变。

---

## 8. 交接边界（谁做什么）

| 任务 | 归属 | 依赖 | 产出 |
|---|---|---|---|
| **本设计文档** | Claude | SPEC-PACK-2（并行，倒推 schema） | 7 骨架定义 + 线框图方案 + 圈选交互 + schema 需求 |
| SPEC-PACK-2 `layoutGrammar` 扩展 | Codex | 本文 §4 需求 | 解析/校验新增字段，或诚实 unsupported |
| **PLANNER-1a-IMPL** | AG | 本设计 + SPEC-PACK-2 | 7 骨架落地（扩现有 4 单页→对开）+ `WireframeRenderer` + 站4 圈选界面 |
| **PLANNER-1b-DESIGN** | Claude | 本文（骨架候选空间） | 内容指纹→受控抽签→硬过滤→软评分→节奏记忆 |

**1a-IMPL 的最小可交付（MVP）**：先落 A1/A2/A3/A4 四个骨架（覆盖开篇+正文河+图文+气口，够跑 PILOT-3 的连续翻页节奏），A5/A6/A7 随后补。线框图先出静态 PNG 画廊，圈选交互后接。

**开放问题（留给 1a-IMPL / 1b-DESIGN 决议）**：
- 图集 A5 的 `imageSlots` 2–4 具体网格几何（等距 or 主次）——1a-IMPL 定，1b 按实际图数选档。
- 竖排（`vertical:true`）下的对开镜像与书脊方向（右开本）——本设计按横排左开本，竖排留待专项（见 [[idml-route-validated]] 复合字体+竖排批次）。
- 跨书脊出血图在 IDML 导出的真实几何——`SPREAD-1`/`E2-4` 已支持真 spread，1a-IMPL 标记、导出层落地。
