# PLANNER-1b-DESIGN · 受控变体规划器设计文档

> 状态：设计（先设计后动手）。作者 Claude @ `feature/claude-planner-1b-design`，2026-07-09。
> 关键路径：`SPEC-PACK-2 → PLANNER-1a → **PLANNER-1b** → REROLL-1 → PILOT-3`。
> 依赖：[PLANNER-1a-DESIGN](planner-1a-skeleton-design.md)（骨架候选空间）。消费方：PLANNER-1b-IMPL（AG，引擎核心高风险）、REROLL-1（AG，单页重抽）。
> 一句话：**给定一本书的内容 + 一组已审批的对开骨架，为每个对开确定性地选出「用哪个骨架 + 哪套参数」，选择过程是「受控抽签」——有随机感、但固定种子可复现。**

---

## 0. 职责边界：1b 选「哪个骨架」，1a-IMPL 把骨架变成帧

- **1a**（已完成）：定义**有哪些合法对开骨架**（7 个家族 × 镜像/图片档位/抽言位参数），以及骨架→帧几何的实例化（1a-IMPL）。
- **1b**（本文）：对每个对开，从**已审批启用**的骨架里，按内容**选一个骨架 + 一套参数**，输出一串 `SpreadSelection`。
- **materialize**：`SpreadSelection` 交 1a-IMPL 的实例化函数变成 per-page `LayoutPlan`（写进 `project.appliedLayoutPlans`），再由现有引擎排版。

> 1b **不直接摆帧、不碰文字排布**。它只做「选型 + 定参」这一层决策。帧几何是纯函数产物（1a-IMPL），文本灌流是现有 THREAD-1b 机制。这条分层是「正文永远一条河」铁律的前提（见 [[layoutd-positioning-initial-pour]]）。

---

## 1. 数据流总览

```
BookProject ──► ContentFingerprint ──► [SpreadDemand]  (每对开一条内容需求)
                                              │
   spec pack: enabledArchetypes(1a) ─────────┤
              rhythm / qualityGates ──────────┤
              seed ───────────────────────────┤
                                              ▼
                        ┌─────────────────────────────────┐
   for each spread ───► │ 1. 强制骨架判定(章起/大图逾期)      │
   （阅读顺序，带节奏记忆）│ 2. 候选生成(骨架×参数展开)        │
                        │ 3. 硬过滤(越界/重叠/文流序/DPI)   │
                        │ 4. 软评分(防单调/图大小/贴近/留白/accent)│
                        │ 5. 受控抽签(seed → top-K 加权采样) │
                        │ 6. 提交 + 更新节奏记忆             │
                        └─────────────────────────────────┘
                                              ▼
                                   [SpreadSelection]
                                              │  (1a-IMPL 实例化)
                                              ▼
                              project.appliedLayoutPlans[pageN] = LayoutPlan
```

**纯函数签名（1b-IMPL 落地目标）**：

```swift
func planSpreads(
    fingerprint: ContentFingerprint,   // 由 BookProject 确定性导出
    archetypes: [SpreadArchetype],     // spec pack 已启用集合（1a）
    rhythm: RhythmRules,               // spec pack layoutGrammar.rhythm
    gates: QualityGates,               // spec pack qualityGates
    seed: UInt64,                      // rhythm.seed 哈希；固定 → 可复现
    locked: [Int: SpreadSelection]     // 用户锁定的对开（REROLL/手工微调用）
) -> [SpreadSelection]
```

**同输入同输出**（无 `Date.now`/无系统随机）——否则 golden / 逐字节护栏全废（铁律②，同源教训见 [[idml-multicolumn-frame-grouping]]）。

---

## 2. 内容指纹（Content Fingerprint）

现有 `LayoutPlanContext`（`Sources/LayoutDDesignAI/LayoutAdvisor.swift:24`）已有雏形：title / keywords / `SectionSummary`(paragraphCount/figureCount/calloutCount/tableCount) / `AssetSummary`(pixelWidth/Height/role)。1b 在其上导出**逐对开的内容需求 `SpreadDemand`**。

### 2.1 从「段落流」切成「对开需求」
正文是一条连续的河，1b 不预先知道每段落落在哪一对开（那是排版结果）。因此用**估算**切分：

- 用现有引擎的行高/版心估算每对开可容纳的正文行数（复用 `LayoutEngine+Measurement` 的度量，不重排）。
- 按段落顺序累加，估算「第 k 对开大致覆盖哪些段落」，得到该对开的：
  - `bodyLoad`：正文密集度估计（0…1，满版正文≈1）。
  - `imageDemand`：落在该段落窗口内的图片数 + 各自 `AssetSummary`（长宽比、role=hero/supporting/decorative、像素尺寸）。
  - `pullQuoteDemand`：callout/抽言数。
  - `knowledgeCardDemand` / `tableDemand`。
  - `isChapterStart`：该对开是否某章第一对开（来自 `section` 边界）。

> 估算只为**选型**，不追求精确落点——真实落点由排版引擎定，漂移可接受（[[layoutd-positioning-initial-pour]] 可编辑性 > 逐像素）。估算必须确定性（同 project 同结果）。

### 2.2 指纹哈希 → 种子
`seed = stableHash(rhythm.seed 字符串 + 书籍内容摘要)`。内容摘要取**稳定字段**（段落数/图数/章数/标题），不取 UUID/时间戳。这样：
- 同一本书 → 同一 seed → 同一版面（可复现、golden 稳）。
- 内容真变了（加了一章/换了图）→ seed 变 → 版面允许重排（合理）。

---

## 3. 受控抽签（Controlled Draw）

「受控」= **有界随机**：既不是纯 argmax（每次都选最高分 → 全书千篇一律、防单调失效），也不是自由随机（不可复现）。做法：

1. 对该对开所有**通过硬过滤**的候选算软分 `score`（§5）。
2. 取 `score` 最高的 **top-K**（K≈3）。
3. 用 **seeded PRNG** 在 top-K 里按 `score × archetype.weight` 加权采样一个。
4. PRNG 是**可分裂确定性**的：`subSeed(spreadIndex, rerollCounter)`——
   - `rerollCounter=0` 是首次规划；
   - REROLL-1「换一版」把某对开的 `rerollCounter++`，**只改这一对开的子种子**，邻居不动（REROLL 铁律：锁页不被覆盖）。

> PRNG 用确定性算法（如 SplitMix64），种子来自 §2.2；**禁止** `Math.random`/`SystemRandomNumberGenerator`。子种子分裂保证「重抽一页不扰动全书」，这是 REROLL-1 能做的前提。

---

## 4. 硬过滤（Hard Filters）—— 不满足直接淘汰

候选 = (archetype, mirror, imageTier, pullQuotePosition)。逐个校验，任一不过即淘汰：

| 过滤 | 判据 | 说明 |
|---|---|---|
| **不越界** | 每个 block 的 `Rect` ⊂ 版心活区（去页边距） | 复用 `pageSetup` 版心；出血图例外（`bleedAcrossSpine` 允许到出血线） |
| **不重叠** | 任意两个非背景 block 交叠面积 ≤ ε | ghostNumber 压底层(`layer:behind`)不计入重叠；body 分栏是相邻非重叠 |
| **文流顺序** | 骨架的多个 `body` 槽串接链 = 全局阅读序（左页先于右页、栏内上→下） | **绝不重排正文河**（铁律①）；串接用 `nextThreadedBlockId`（`LayoutPlanBlock` 已有字段） |
| **图片 DPI** | `asset.pixelWidth / slot物理宽(in) ≥ DPI阈值`（印刷≈150） | 大图槽放低分辨率图 → 淘汰或降档；阈值进 `qualityGates`（见 §7 给 SPEC-PACK-2 的需求） |
| **槽位供需** | 骨架 `imageSlots ≥ 该对开必放图数`；无图内容不选强制图骨架(A4/A5) | 供需不匹配的骨架先天淘汰，减少候选空间 |

硬过滤是**规划器的护栏**：只要过了，输出一定是「不越界、不重叠、文流不乱、图不糊」的合法版面。软评分只在合法候选里挑「更好看的」。

---

## 5. 软评分（Soft Scoring）—— 合法候选里挑更优

每项归一化 0…1，加权求和。权重是可调常量（进 `qualityGates` 或代码默认，见 §7）。**评分口径对齐 STYLE-LOCK-1 的 `StyleReport`**——1b 预测性优化的，正是风格报告事后打分的那几项，闭环一致：

| 信号 | 打分逻辑 | 对应 StyleReport 项 |
|---|---|---|
| **防单调** | 与前 N 个对开的 (family, imageTier) 相似度越高分越低 | `layoutRepeatCount` / `repeatViolationCount` |
| **图大小贴切** | imageTier 与图的自然重要度匹配（hero 图→偏好 large/fullBleed；supporting→medium/small；被塞进不合档位扣分） | 图文密度合理 |
| **贴近度** | 骨架容量 vs `SpreadDemand`（正文能装下不溢出、图槽数 == 图数、抽言位有需求才用） | `overflowsCheck` |
| **留白** | 预估 `textDensity`/`imageDensity` 落在 gates 区间内得高分，过挤/过空扣分 | `PageDensity` + gates 区间 |
| **accent 频率** | 满足 `requireAccentPerSpread`（本对开有抽言竖线/标题线/图注短横之一）加分 | `motifsChecklist` |

> 评分是「相对偏好」，不是硬约束——分低的候选仍合法，只是不优先。硬 vs 软的分界：**会出坏版面的**（越界/重叠/糊图/乱序）走硬过滤；**只是不够好看的**（单调/密度/留白）走软评分。

---

## 6. 节奏记忆（Rhythm Memory）—— 跨对开的状态

规划按阅读顺序逐对开推进，携带一个**节奏状态**，让「全书翻页有节奏」（PILOT-3 的验收标准从「单页像不像」升级为「连续翻页有没有节奏」）：

```swift
struct RhythmMemory {
    var recentFamilies: [String]        // 滑窗，查 maxSameFamilyRun
    var spreadsSinceBigImage: Int       // 查 bigImageEveryMinSpreads
    var strategyRepeatCounts: [String:Int] // 查 maxTemplateRepeat（对齐 StyleReportGenerator）
    var accentStreak: Int
}
```

三条节奏规则（spec pack `rhythm`）：
- **相邻不重复**：`recentFamilies` 里连续同 family 达到 `maxSameFamilyRun` → 下一对开**硬性排除**该 family（升格为硬过滤，因为连续 3 个同版式是明显的「机器排版感」）。
- **大图气口**：`spreadsSinceBigImage ≥ bigImageEveryMinSpreads` 且后续有可用大图 → **强制**选 A4 `hero-spread`（呼吸页），防止全书密不透风。
- **章起强制**：`isChapterStart` → 强制 A1 `chapter-opener`（`rhythm.openerAlwaysArchetype`），忽略抽签。

强制骨架（章起/大图逾期）在 §1 流程第 1 步短路抽签；其余走 2–5 步正常抽签。每提交一个对开，更新记忆。

---

## 7. 倒推给 SPEC-PACK-2 / 现有类型的需求

1b 消费 spec pack 的 `rhythm` + `qualityGates`，已基本齐备（见 spec-pack-guide）。**补充需求**（写进 handoff 交 Codex，或 1b-IMPL 自带默认）：

1. `qualityGates` 新增 `minImageDPI`（默认 150）——硬过滤图片 DPI 用；不加则代码内默认。
2. `qualityGates` 可选 `softWeights{monotony,imageFit,fitToDemand,whitespace,accent}`——软评分权重，让不同 spec pack 调性不同（杂志感 vs 素雅）；不加则代码内默认。
3. `rhythm.topK`（默认 3）——受控抽签的候选池大小；越大越多样、越小越稳。
4. 以上若 SPEC-PACK-2 暂不支持，**进 `unsupportedFields` 诚实上报**（现有机制），1b-IMPL 用代码默认值，不阻塞。

**复用现有接缝**：1b-IMPL 实现现有 `LayoutPlanProvider` 协议（`LayoutAdvisor.swift:8`），插入 `ProviderBackedLayoutAdvisor`——规划失败时自动回退 `RuleBasedLayoutAdvisor`（现有 4 单页模板），保证永远有版面。

---

## 8. 铁律与验收（1b-IMPL 不可破）

沿用 queue 批次 P 对 1b-IMPL 的三条硬约束：

1. **只动帧几何、不破串接文流**：1b 只输出「选型 + 参数」，帧由 1a-IMPL 出、正文串接由 THREAD-1b 出；多 body 槽必须声明串接链（[[layoutd-positioning-initial-pour]]）。
2. **纯函数、同输入同输出**：固定种子、确定性 PRNG、稳定哈希；无时间/系统随机。**验收必须证明**：同一 project 连跑两次，`[SpreadSelection]` 逐字段一致（golden 级）。
3. **端到端验收不能只靠单测**：本项目踩过「单测全绿功能坏」（[[visual-verification-not-automatable]]）。1b-IMPL 验收 = 拿 PILOT（村落）真书跑完整规划 → 出 PDF/线框图 → **人肉眼看连续翻页节奏**（无连续 3 同骨架 / 大图气口分布合理 / 每章开篇是 opener / motif 全出现），再进 STYLE-LOCK-1 风格报告全绿。

### 建议的自动化护栏（补单测之不足）
- **确定性探针**：同 project 两次 `planSpreads` 结果哈希一致（进 `review-idml.sh`，仿 GUARD-4 串接探针）。
- **合法性探针**：随机造 N 本合成书跑规划，断言输出**零硬过滤违例**（越界/重叠/乱序/糊图）——硬过滤是护栏，输出必须已满足。
- **节奏探针**：断言输出满足 `maxSameFamilyRun` / 章起=opener / 大图间隔 ≤ `bigImageEveryMinSpreads`（有大图可用时）。

---

## 9. 与 REROLL-1 / 锁页 / 手工微调的协同

- **锁页**：`planSpreads(locked:)` 接收用户锁定的 `SpreadSelection`——锁定对开**跳过抽签**直接采用，但**仍参与节奏记忆**（邻居要避开它的 family，气口计数照算）。
- **REROLL-1「换一版」**：对某对开 `rerollCounter++` → 子种子变 → 在该对开 top-K 里换一个候选；`locked` 里的邻居不动。因子种子按 `spreadIndex` 分裂，重抽一页**不扰动**其余全书（这正是 §3 子种子分裂的目的）。
- **手工微调**：微调是 1a-IMPL/引擎层的帧 override（LayoutPlan/frame override，见 [[manual-edit-via-layoutplan]]），不回灌 1b；1b 只管「选哪个骨架」，具体某帧被手工挪了 2mm 不影响选型。

---

## 10. 交接边界（谁做什么）

| 任务 | 归属 | 依赖 | 产出 |
|---|---|---|---|
| **本设计文档** | Claude | 1a-DESIGN | 内容指纹→受控抽签→硬过滤→软评分→节奏记忆 全链设计 |
| SPEC-PACK-2 补 gates 字段 | Codex | §7 需求 | minImageDPI/softWeights/topK 落地或诚实 unsupported |
| **PLANNER-1a-IMPL** | AG | 1a-DESIGN | 7 骨架实例化（1b 的 materialize 依赖它）+ 线框图 + 圈选 |
| **PLANNER-1b-IMPL** | AG | 本文 + 1a-IMPL | `planSpreads` 纯函数 + 3 道护栏探针 |
| **REROLL-1** | AG | 1b-IMPL | 单对开子种子重抽 + 锁页协同 |
| **PILOT-3** | Claude + 用户 | 以上全部 | 村落 12–20 页连续翻页节奏终验 |

**1b-IMPL 的最小可交付（MVP）**：先支持 1a-IMPL 已落的 A1–A4 四骨架的选型；硬过滤四条全上；软评分先上「防单调 + 贴近度 + 留白」三项（图大小/accent 随 motif 渲染成熟再补）；节奏记忆三条规则全上（它们决定「有没有节奏」这个 PILOT-3 核心验收点）。

**开放问题**：
- 正文行数估算精度 vs 排版真实落点的偏差容忍——1b-IMPL 先用粗估，PILOT-3 校准。
- top-K 采样在小书（<6 对开）上多样性不足——可能退化为按 weight 直选；PILOT-3 观察。
- 竖排/右开本的阅读序镜像——本设计按横排左开本，竖排随专项（见 [[idml-route-validated]]）。
