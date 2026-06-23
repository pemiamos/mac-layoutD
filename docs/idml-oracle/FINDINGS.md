# IDML 真值机（oracle）发现记录

第②层保真策略：手搓真·InDesign 文档 → 导出 IDML 当"标准答案" → diff 我们的输出，
抽取规范不写、只能实测的渲染搭档规则。决策见 `.ai/DECISIONS.md`（2026-06-23）。

## goldens/

| 文件 | 来源 | 覆盖 |
|---|---|---|
| `indesign2026-footnote-cjk.idml` | 用户在 InDesign 2026 中文版手搓（含一个脚注），DOMVersion 21.3 | 脚注序列化 + CJK 排版器真值 |
| `indesign2026-kenten-cjk.idml` | 用户手搓（手动应用着重号），DOMVersion 21.3 | 着重号字符级真值（中文习惯） |

## 2026-06-23 比对结论（footnote golden）

### 🔴 排版器（Composer）—— 此前实现三处全错，已修

| | 旧实现（错） | InDesign 2026 真值 |
|---|---|---|
| 属性名 | `AppliedComposer` | **`Composer`**（InDesign 无 `AppliedComposer`，会被忽略） |
| 值 | `$ID/HL Composer Optyca`（其实是**拉丁**排版器） | **`HL Composer J`**（CJK/World-Ready，无 `$ID/` 前缀） |
| 位置 | 逐 Story 段落内联 | **段落样式定义 + 文档 `<TextDefault>`**，不逐段内联 |

根因：旧代码用了 InDesign 不认的属性名 + 拉丁排版器值 → 排版器实际从未生效 →
一直退回默认拉丁排版器 → 着重号(KentenKind)被静默忽略。代码注释还把 Optyca/J 的
中西身份写反了。

**修复**（IDMLExporter.swift）：常量改 `HL Composer J`；`Composer="HL Composer J"`
写进每个 `<ParagraphStyle>` + `[No paragraph style]` 根 + Preferences `<TextDefault>`；
删除 Story 段落上无效的 `AppliedComposer`。断言闸 rule① 同步改为跨 Styles.xml 解析
段落样式的 `Composer`（白名单去掉错误的 Optyca）。

### 🟢 脚注序列化真值

- 脚注段落用 `AppliedParagraphStyle="ParagraphStyle/$ID/NormalParagraphStyle"`——**不是**
  `[No paragraph style]`；NormalParagraphStyle 的 Properties 带 CJK 字体
  `<AppliedFont>Adobe 宋体 Std</AppliedFont>`，所以中文不豆腐。
  （我们的对策：脚注挂带复合字体的 caption/body 样式，方向一致。）
- 承载脚注的字符范围带 `Position="Superscript"`。
- 脚注引用标记真值 = `<?ACE 4?>`（自动编号 PI）+ 全角空格 `　` + 正文。

## 2026-06-23 比对结论（kenten golden）

排版器修复后用户复看：着重号从"整页不出"恢复显示，但样子是日文习惯（字上方芝麻点），
中文书不对。用户手搓 kenten golden 给出中文习惯真值。

### 着重号字符级真值（CharacterStyleRange 上）

InDesign 实际只写**三个**属性，且很精简：

```
KentenKind="KentenBlackCircle" KentenPlacement="-1" KentenPosition="BelowLeft"
```

- `KentenBlackCircle`：实心黑圆点 ●（中文着重号），**非** `KentenSesameDot`（芝麻点，日文习惯）。
- `KentenPosition="BelowLeft"`：点在字**下方**（横排）；旧实现 `AboveRight`=字上方是日文习惯。
- `KentenPlacement="-1"`：自动；旧实现没写。
- `KentenAlignment` **不写在 CharacterStyleRange 上**——它是段落级属性（见 footnote golden 的段落样式默认 `AlignKentenCenter`）；旧实现错误地塞在字符范围上。

**修复**（IDMLExporter.styledCharacterRanges）：着重号改 emit
`KentenKind="KentenBlackCircle" KentenPlacement="-1" KentenPosition="BelowLeft"`，
删除字符级 `KentenAlignment`。已与 golden 逐字段一致。

### 待后续 golden 验证（本份未覆盖）

- 真·**着重号**已应用时的完整字符级属性（本 golden 只有脚注，KentenKind 是段落默认 None）。
- 竖排、复合字体 slot 名、避头尾在真存盘里的精确写法。
- 标准做法：每加一个难功能，手搓一份 golden 存入 `goldens/`，并在此追加比对结论。
