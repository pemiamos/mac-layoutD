# layoutD 视觉规范包编写指南

视觉规范包是给 AI 和批量样张命令使用的 JSON 输入。它描述页面网格、字体别名、颜色 token、角色样式、视觉 motif、对开骨架语法和质量闸；导入器会把可落地字段转换为 layoutD `DesignTokens` / `SpecPackImportResult`，把暂不支持的字段列入 `unsupportedFields`，避免静默忽略。

## 顶层结构

```json
{
  "meta": {
    "name": "方案A · 探索黄（杂志感）",
    "version": 1,
    "trim": "185×260mm",
    "inspiration": "参考来源",
    "designIntent": "设计意图"
  },
  "page": {
    "size_mm": { "width": 185, "height": 260 },
    "margins_mm": { "top": 22, "bottom": 26, "inner": 20, "outer": 24 },
    "grid": { "columns": 2, "gutter_mm": 8, "baselineGrid_pt": 15.5 }
  },
  "fonts": {
    "正文": "方正兰亭细黑",
    "标题": "黑体-简 Medium",
    "抽言": "江城律动宋",
    "西文": "Georgia"
  },
  "colors": {
    "modes": ["default"],
    "tokens": {
      "accent": { "default": "#F5C518" },
      "ink": { "default": "#1B1B1B" }
    }
  },
  "roles": {
    "正文": { "font": "正文", "fontSize_pt": 10, "lineHeight": 1.6, "firstLineIndent_em": 2 }
  },
  "motifs": {
    "chapterNumber": {
      "font": "西文",
      "fontSize_pt": 184,
      "color": "grayText",
      "opacity": 0.07,
      "anchor": "chapterStart.topRight",
      "layer": "behind"
    },
    "sectionNumber": { "style": "westernAccent", "color": "accent", "minDigits": 2, "suffix": " /" },
    "header": { "font": "西文", "fontSize_pt": 7.5, "color": "grayText", "rule": "thin-full-width", "label": "EXPLORE" },
    "captionTick": { "type": "top-tick", "color": "accent", "width_pt": 2, "length_mm": 6 },
    "headingRule": { "type": "bottom-rule", "color": "accent", "width_pt": 2, "length_mm": 20 },
    "pullQuoteRule": { "type": "left-rule", "color": "accent", "width_pt": 3 }
  },
  "layoutGrammar": {
    "spreadArchetypes": [
      { "id": "text-image-balanced", "displayName": "图文均衡对开", "family": "balanced", "pages": 2, "imageSlots": 1, "pullQuoteSlots": 1, "mirror": true, "weight": 1.2 }
    ],
    "rhythm": { "maxSameFamilyRun": 2, "bigImageEveryMinSpreads": 3, "accentEverySpread": true, "seed": "content-fingerprint-v1" }
  },
  "qualityGates": {
    "maxTemplateRepeat": 2,
    "minTextDensity": 0.35,
    "maxTextDensity": 0.72,
    "minImageDensity": 0.08,
    "maxImageDensity": 0.42,
    "requireAccentPerSpread": true,
    "maxOverflowRatio": 0.01
  },
  "vertical": false
}
```

## 字段规则

`meta.name` 必填，用于样张文件名和人工比选。`meta.version` 建议从 `1` 开始；`trim`、`inspiration`、`designIntent` 是说明字段。

`page.size_mm.width/height` 使用毫米，必须大于 0。`page.margins_mm.top/bottom/inner/outer` 使用毫米，必须为 0 或正数，且左右/上下相加不能超过页面尺寸。导入时会转换为 point，并输出 `page.margin.left/right/top/bottom` token；当前 `inner` 映射到 `left`，`outer` 映射到 `right`。

`page.grid.columns` 必须大于 0；`gutter_mm` 必须为 0 或正数；`baselineGrid_pt` 必须大于 0。`grid.marginColumn` 可写说明文字，但当前只会作为未支持字段上报。

`fonts` 是“角色别名 → 字体名”。导入器会先走批准别名映射，再检查实际字体是否已安装。当前批准别名包括：`方正兰亭细黑 → 方正兰亭细黑简体`、`黑体-简 Medium → Heiti SC Medium`、`宋体-简（标题用衬线） → Songti SC`、`江城律动宋 → JiangChengLvDongSong`。没有映射的值会按原名检查。

`colors.modes` 至少包含一个模式，通常为 `["default"]`。`colors.tokens.<name>.<mode>` 必须是 `#RRGGBB`。

`roles` 当前可落地到段落样式的中文角色：`章名`、`节名`、`正文`、`抽言`、`图注`、`开节概述`、`引文`。这些角色支持 `fontSize_pt`、`lineHeight`、`firstLineIndent_em`、`indent_em`、`spaceBefore_pt`、`spaceAfter_pt`。`lineHeight` 小于等于 4 时按倍数处理，例如 `1.6` 会转换为 `fontSize_pt * 1.6`；大于 4 时按 point 处理。

`motifs` 是 v2 视觉标识词表，当前导入器会强类型解析并保存在 `SpecPackImportResult.motifs`，供后续渲染器和规划器消费。支持项：`chapterNumber`（`font`、`fontSize_pt`、`color`、`opacity`、`anchor`、`layer`）、`sectionNumber`（`style`、`color`、`minDigits`、`prefix`、`suffix`）、`header`（`font`、`fontSize_pt`、`color`、`rule`、`label`、`showChapterTitle`、`showPageNumber`）、`captionTick` / `headingRule` / `pullQuoteRule`（共用装饰对象：`type`、`color`、`width_pt`、`length_mm`）。`font` 必须引用 `fonts` 里的别名；`opacity` 必须在 0...1。旧方案A 写在 `roles.章节序号`、`roles.节名.numberStyle`、`roles.页眉页码` 的字段会兼容解析到相应 motif，不再只作为 unsupported 上报。

`layoutGrammar` 是站4/站5规划器使用的对开骨架语法。`spreadArchetypes` 是非空数组时会校验 `id` 唯一；每项支持 `id`、`displayName`、`family`、`pages`、`imageSlots`、`pullQuoteSlots`、`mirror`、`weight`。`rhythm` 支持 `maxSameFamilyRun`、`bigImageEveryMinSpreads`、`accentEverySpread`、`seed`，用于后续受控抽签和防单调评分。当前导入器只解析和校验，不直接生成 `LayoutPlan`。

`qualityGates` 是风格报告和规划器的质量闸默认值。支持 `maxTemplateRepeat`、`minTextDensity`、`maxTextDensity`、`minImageDensity`、`maxImageDensity`、`requireAccentPerSpread`、`maxOverflowRatio`。密度和溢出比例必须在 0...1，最小值不能大于最大值。

`vertical` 当前会导出为 `page.vertical` token，供后续样张命令和竖排模板使用；现有 App token 绑定暂不自动切换项目排版方向。

## 印刷可移植默认规则

以下规则来自对屏幕/网页设计技能形态的筛选和转译，只保留能服务印刷内页的可测试部分；不要照搬网页组件、响应式断点、卡片装饰或营销 hero 结构。

1. **先定版心后定装饰**：先确定 trim、内外边距、栏数、gutter、baselineGrid，再放标题、图片和 motif。
2. **层级对比用比例表达**：章名字号约为正文的 3.0-3.8 倍，节名字号约为正文的 1.15-1.4 倍，图注约为正文的 0.7-0.85 倍；具体数值仍需按字体真实字面调整。
3. **大字号收紧字距但保持可读**：章名或 ghost number 可以使用轻微负 tracking；正文、图注、长段落不使用负 tracking。
4. **正文行高优先稳定**：横排正文 lineHeight 建议 1.5-1.75 倍字号，且尽量贴合 baselineGrid；不要为了视觉密度压到网页 UI 式紧行距。
5. **中文正文只用少数可靠字族**：正文、标题、抽言、数字/西文四类足够；每个字体必须能解析到真实安装权重。
6. **颜色保持一主一辅**：正文页以 `ink` / `grayText` / `paper` / `accent` 为主，accent 面积宁少勿多；每个 spread 至少可出现一个可识别 accent，但不要求每个元素都着色。
7. **motif 必须可复现**：ghost 章号、节序号、页眉、图注 tick、标题线、抽言竖线都应有明确 JSON path；不能只写在设计意图里。
8. **对开节奏优先于单页漂亮**：`layoutGrammar.rhythm.maxSameFamilyRun` 默认不超过 2，连续 12-20 页检查不应出现长串同骨架。
9. **大图气口要有间隔**：如有大图或跨栏图，`bigImageEveryMinSpreads` 建议 3-5；避免每页都抢主视觉。
10. **文本密度设上下限**：起始建议 `minTextDensity=0.30-0.35`、`maxTextDensity=0.70-0.75`，低于下限像广告页，高于上限像未排版稿。
11. **图片密度设安全区间**：起始建议 `minImageDensity=0.05-0.10`、`maxImageDensity=0.40-0.45`；无图章节可降级，但不要让偶发图片破坏正文流。
12. **重复约束可被机器检查**：`maxTemplateRepeat` 起始为 2；超过时应触发风格报告而不是靠肉眼回忆。
13. **装饰必须让位给文流**：任何 rule/tick/ghost/header 都不能打断 threaded story，也不能制造后期 InDesign 改稿时难以修复的固定坐标依赖。
14. **unsupportedFields 是交付物**：字段暂未消费时必须出现在支持率清单或评审报告里，不能静默消失。
15. **视觉样张不等于印前终稿**：AI/样张负责定风格和节奏，最终 CMYK、细微避头尾、页内局部微调仍由 InDesign 完成。
16. **所有默认值都允许被书稿推翻**：科普图书、文集、图册、竖排诗文的密度和 motif 频率不同；默认值是起点，不是硬编码审美。

## 当前会显式上报但暂不落地的字段

仍未落地的角色级复杂版式字段会进入 `unsupportedFields`：`tracking_em`、`alignment`、`maxLineWidth_chars`、`span`、`format`、`blockColor`、`textColor`、`blockSize_mm`、`cornerRadius_mm`。`color`、`decoration`、`numberStyle`、`position`、`rule`、`treatment`、`opacity` 已被解析为角色颜色或 v2 motif，但除 `pullQuoteRule` / 既有段落点缀链路外，多数 motif 仍等待后续渲染任务消费。

AI 可以继续写这些字段，因为它们对人工审稿有价值；工程侧只是不把它们静默当作已生效。v2 顶层对象中的未知字段也会按 JSON path 进入 `unsupportedFields`，例如 `$.layoutGrammar.rhythm.experimentalScore`。

## 校验错误

错误信息会带 JSON 路径，例如 `$.roles.正文.font: unknown font alias '标题2'`。常见拒绝原因包括：缺少必填对象、数字小于等于 0、颜色不是 `#RRGGBB`、角色引用不存在的字体别名、字体别名无法解析到已安装真实字体、页边距超过页面尺寸。
