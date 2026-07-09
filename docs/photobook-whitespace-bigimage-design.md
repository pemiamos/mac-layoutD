# 摄影集范式扩建设计 · 大留白 / 大图 / 跨页全幅

> 状态：设计（Claude @ feature/claude-pilot-3，2026-07-09）。缘起：PILOT-3 拿《长白山天池》样张比对，用户明确"**我们的书都是大留白、大量大图甚至跨页全幅图的**"（见记忆 [[books-are-whitespace-bigimage-fullbleed]]）。现有渲染器 + 7 骨架偏文字密排，排不出这类书。本文把样张 14 页拆成可落地的**渲染器 + 骨架 + 规划器**扩建清单，供 AG 实施、Codex 补 schema。
> 定位校准：这不是某本书的风格，是用户**所有书的共性** → 是 layoutD 该长成的核心，不是边角。

## 0. 样张实测：9 种版式 → 落地映射

《长白山天池》样张 14 跨页，实测归纳出 9 种版式。每种标注现状能力与所缺：

| # | 版式 | 样张页 | 现状 | 缺口 |
|---|---|---|---|---|
| 1 | **全出血跨页开篇**（地形图铺满 + CHAPTER + 巨标题 + 英文副标） | 01, 08 | A1 是文字型开篇，无全出血图 | **新骨架 + 全出血图渲染 + 标题叠图** |
| 2 | **整跨页出血照片**（一图占满跨页） | 03 | hero-spread 存在但没真全出血、没被选中 | **跨书脊全出血渲染 + 规划器气口选型** |
| 3 | **整页大图 + 短文 + 大留白** | 02, 09 | 图只会小内联 | **图片档位 large/fullPage + 留白分配** |
| 4 | **图解 + 文字**（青绿框示意图 + 正文） | 04, 06 | 图能放，但无描边框、图偏小 | 图框描边（accent frame）+ 中大图档 |
| 5 | **开节独占页 + 大留白**（节号+标题+引言，下方全空） | 11右, 04右 | 节紧接正文密排，无独占无留白 | **开节骨架 + 规划器给节留页 + 留白下限闸** |
| 6 | **圆形图鉴网格**（8 标本 + 编号图注表） | 11左 | A5 gallery 存在但没圆形遮罩、没被选中 | 圆形/网格遮罩（`ImageMaskShape` 已有 rect/fan/octagon，缺 circle）+ 编号图注 |
| 7 | **TIPS/注释知识块**（青绿标题 + 尾注①②③） | 07 | knowledge-card 结构在 | 青绿标题样式 + 尾注编号联动 |
| 8 | **2栏正文 + 首字放大** | 05, 06右 | 2栏可，无首字放大 | 首字下沉（drop cap） |
| 9 | **分色调页背景**（暖米白/淡青，跟章主题变） | 全部 | **引擎无页级背景机制**（只有 per-frame） | **页背景色渲染（最关键）** |

**一句话**：现有系统能排"文字为主、图为辅、填满版心"的书；样张要的是"**图为主、大留白、分色背景、每章全出血开篇**"——是另一套版式语言。

## 1. 渲染器扩建（RENDER-CORE-1 一并做，别 4 处追平）

### R1 · 页级背景色（最关键，单点最大提升）
- `PageSetup` 加 `pageBackgroundColor: String?`（或按对开/章的 `backgroundByTheme`）。
- `parseSpecPack` 把 `colors.tokens.paper` + 可选 `page.backgroundByChapter` 落地。
- 四渲染器（Canvas/PDF/PNG/IDML）在画任何 frame 前，先按页 rect 填背景色；IDML 用一个页大小的 `Rectangle` 置底或 Spread 背景。
- **建议走 RENDER-CORE-1 的"绘制指令→薄适配"**：加一条 `.pageFill(color)` 指令，四端各自实现一次，杜绝追平。

### R2 · 真·全出血图（跨书脊）
- 图片档位新增 `fullPage` / `fullBleed`；`fullBleed` 允许 frame 出版心到出血线、跨书脊（对开级）。
- 渲染器：图片 rect 允许超出版心；IDML 已有真 spread（SPREAD-1/E2-4），几何按出血计算。
- 章开篇（版式1）与气口（版式2）都依赖它。

### R3 · 图框描边 + 圆形遮罩
- `ImageMaskShape` 加 `circle`（现有 rect/fan/octagon）——图鉴用。
- 图 frame 可选 accent 描边（`strokeColorHex` 已有字段，接上渲染即可）——图解框用。

### R4 · 首字下沉（drop cap）
- 段落样式加 `dropCapLines: Int?`；正文/章首段首字放大 N 行。CoreText 可用首字符单独放大 + 环绕；IDML 有 `DropCapCharacters`/`DropCapLines` 原生属性。

## 2. 骨架词表扩建（7 → 增补摄影集骨架）

现有 7 骨架（见 [[planner-1a-skeleton-design]]）偏文字。**新增/重做**：

- **A1′ 全出血开篇** `fullbleed-opener`：全出血图铺满对开 + 标题/CHAPTER/英文副标叠在图上。取代现文字型 A1（或作 A1 的 `imageTier=fullBleed` 变体，需 SPEC-PACK-2 真支持 imageTiers）。
- **A4′ 全幅气口** `fullbleed-photo`：纯一张跨页出血图（可带角标图注）。hero-spread 的真全出血版。
- **A8 大图+短文** `photo-dominant`：整页大图 + 对页 1 栏短文 + 大留白。
- **A9 开节留白** `section-opener`：节号+标题+引言占页上部，**下部强制留白**。规划器遇 section 边界优先选它。
- **A5′ 图鉴网格** `gallery-grid`：圆形/矩形遮罩网格 + 编号图注表（真被选中 + 圆形遮罩）。

每个骨架声明 `minWhitespace`（留白下限），交规划器与质量闸用。

## 3. 规划器扩建：从"灌满"到"呼吸"（核心观念转变）

> 与 [[layoutd-positioning-initial-pour]] 的张力：layoutD 底座是"初排灌版填满框"；这类书要"**故意不填**"。这不是小调参，是教规划器/引擎**有意留白**。

- **内容慷慨分配**：`SpreadDemand` 的 `linesPerSpread` 对摄影集风格调低（每页少段），把省下的版面给图与留白。由 spec pack `qualityGates` 的密度区间驱动（`maxTextDensity` 调低到 ~0.45）。
- **软评分加"留白项"**：奖励达到 `minWhitespace` 的候选；现在只有"防过空"，要加"防过挤"。
- **留白质量闸**：`qualityGates` 加 `minWhitespaceRatio`（每对开留白下限），风格报告新增"留白达标率"。
- **节奏记忆扩项**：section 边界强制 `section-opener`；大图气口频率对摄影集调高（`bigImageEveryMinSpreads` 调小）。
- **章开篇强制** `fullbleed-opener`。

## 4. SPEC-PACK-2 补丁（Codex）

- 真支持 `layoutGrammar.spreadArchetypes[].imageTiers`（含 `fullPage`/`fullBleed`）、`role`、`carriesMotifs`、`rhythm.openerAlwaysArchetype`——现在全报 unsupported（PILOT-3 实测），导致规范包声明的全出血档没生效。
- `page.backgroundByChapter` / `colors.tokens.paper` → 页背景 token。
- `qualityGates.minWhitespaceRatio`、`roles.*.dropCapLines`。
- `applySpecPack` 把 `spreadArchetypes` 写进 `wizardState.enabledArchetypeIds`，让 auto-plan/GUI 真吃规范包骨架（现只吃内置默认）。

## 5. 分期建议（先见效后完善）

1. **P0 页背景色（R1）**：单点最大观感提升，样张所有页都有色底。先做。
2. **P0 全出血开篇骨架（A1′ + R2）**：每章第一眼，最出效果。
3. **P1 开节留白（A9）+ 规划器留白闸（§3）**：解决"排太紧"的根本。
4. **P1 全幅气口（A4′）+ 图鉴圆形遮罩（A5′/R3）**。
5. **P2 首字下沉（R4）+ 图框描边**：锦上添花。

## 6. 诚实边界

- 这是**一批**引擎/骨架/规划器工作，不是改几行；但它是 layoutD 能排用户这类书的**必要条件**，不建则"看图分析"再准也白搭（受限的是渲染能力不是分析）。
- 逐像素复刻样张不是目标（可编辑性 > 冻结，见 [[layoutd-positioning-initial-pour]]）；目标是**版式语言对**（留白/大图/分色/全出血开篇），漂移交 InDesign 微调。
- 视觉对错只有人在 InDesign/渲染里能判（见 [[visual-verification-not-automatable]]）。
