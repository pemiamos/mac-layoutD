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

## 当前会显式上报但暂不落地的字段

仍未落地的角色级复杂版式字段会进入 `unsupportedFields`：`tracking_em`、`alignment`、`maxLineWidth_chars`、`span`、`format`、`blockColor`、`textColor`、`blockSize_mm`、`cornerRadius_mm`。`color`、`decoration`、`numberStyle`、`position`、`rule`、`treatment`、`opacity` 已被解析为角色颜色或 v2 motif，但除 `pullQuoteRule` / 既有段落点缀链路外，多数 motif 仍等待后续渲染任务消费。

AI 可以继续写这些字段，因为它们对人工审稿有价值；工程侧只是不把它们静默当作已生效。v2 顶层对象中的未知字段也会按 JSON path 进入 `unsupportedFields`，例如 `$.layoutGrammar.rhythm.experimentalScore`。

## 校验错误

错误信息会带 JSON 路径，例如 `$.roles.正文.font: unknown font alias '标题2'`。常见拒绝原因包括：缺少必填对象、数字小于等于 0、颜色不是 `#RRGGBB`、角色引用不存在的字体别名、字体别名无法解析到已安装真实字体、页边距超过页面尺寸。
