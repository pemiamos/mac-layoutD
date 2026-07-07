# layoutD 视觉规范包编写指南

视觉规范包是给 AI 和批量样张命令使用的 JSON 输入。它描述页面网格、字体别名、颜色 token、角色样式和竖排意图；导入器会把可落地字段转换为 layoutD `DesignTokens`，把暂不支持的字段列入 `unsupportedFields`，避免静默忽略。

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

`vertical` 当前会导出为 `page.vertical` token，供后续样张命令和竖排模板使用；现有 App token 绑定暂不自动切换项目排版方向。

## 当前会显式上报但暂不落地的字段

装饰和复杂版式字段会进入 `unsupportedFields`：`tracking_em`、`color`、`alignment`、`decoration`、`numberStyle`、`maxLineWidth_chars`、`position`、`span`、`rule`、`treatment`、`opacity`、`format`、`blockColor`、`textColor`、`blockSize_mm`、`cornerRadius_mm`。

AI 可以继续写这些字段，因为它们对人工审稿有价值；工程侧只是不把它们静默当作已生效。

## 校验错误

错误信息会带 JSON 路径，例如 `$.roles.正文.font: unknown font alias '标题2'`。常见拒绝原因包括：缺少必填对象、数字小于等于 0、颜色不是 `#RRGGBB`、角色引用不存在的字体别名、字体别名无法解析到已安装真实字体、页边距超过页面尺寸。
