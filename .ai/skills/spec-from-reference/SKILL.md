---
name: spec-from-reference
description: Extract a layoutD visual spec pack from one or more book, magazine, or reference layout images. Use when turning a reference image, screenshot, moodboard, or selected visual direction into a validated layoutD spec-pack JSON with page grid, type scale, color tokens, motifs, layoutGrammar, and qualityGates for Chinese science-book initial layout.
---

# Spec From Reference

## Workflow

1. Read `docs/spec-pack-guide.md` before writing JSON. Treat `StyleBaselineImporter.parseSpecPack` as the schema authority.
2. Inspect the reference image as a print spread, not as a web page. Extract measurable layout rules, then encode only what layoutD can parse or honestly report as unsupported.
3. Produce one spec-pack JSON candidate unless the user asks for multiple variants. For multiple variants, change only purposeful axes: accent color, type contrast, density, or rhythm.
4. Validate the JSON with the parser or an existing sample command when possible. Do not call a field "implemented" just because it appears in the JSON.

## What To Measure

- **Trim and grid**: infer page ratio, margins, columns, gutter, baseline rhythm, facing-page symmetry.
- **Type scale**: chapter title, section title, body, pull quote, caption, bibliography/reference text. Record font roles as aliases, not raw guesses from the image.
- **Color system**: keep a small token set: `ink`, `paper`, `grayText`, `accent`, plus only necessary extras. Prefer one strong accent over many decorative colors.
- **Motifs**: identify repeatable signals: ghost chapter number, section number style, running header, caption tick, heading rule, pull-quote rule.
- **Layout grammar**: describe spread archetype families, image slots, pull-quote slots, mirroring, and rhythm constraints. Do not draw exact coordinates unless a later planner task asks for them.
- **Quality gates**: set testable ranges for density, repeat limits, overflow tolerance, and required accent frequency.

## Print-Portable Defaults

Use these as defaults when the reference or manuscript is silent. They are adapted from screen-design skill patterns only where they survive print constraints; trim, margins, spreads, baseline rhythm, and IDML editability win over web-style decoration.

- Start with page architecture: define trim, margins, columns, gutter, and baseline grid before motifs or cards.
- Express hierarchy as ratios: chapter title `3.0-3.8x` body, section title `1.15-1.4x` body, caption `0.7-0.85x` body.
- Tighten tracking only for large display text. Keep body, captions, notes, and long paragraphs at non-negative tracking unless a print proof says otherwise.
- Keep body leading in the `1.5-1.75x` range and align repeated text roles to `grid.baseline`.
- Use one serif and one sans family at most for ordinary science-book layouts; map weights to installed font names or approved aliases.
- Prefer `ink`, `paper`, `grayText`, and one `accent`. Additional colors need semantic jobs such as warning, figure family, or sidebar class.
- Encode repeatable visual signals as `motifs` with source JSON paths, not prose-only intent.
- Keep spread rhythm testable: avoid more than two consecutive spreads from the same family, and give large-image spreads at least three to five spreads of breathing room.
- Set density gates before judging polish: text coverage normally belongs around `0.30-0.75`, image coverage around `0.05-0.45`.
- Treat unsupported fields as part of the deliverable. They preserve ideas for later planner/renderer work without pretending they already affect output.

## Spec-Pack Rules

- Use v2 top-level objects: `motifs`, `layoutGrammar`, and `qualityGates` when the reference implies them.
- Keep legacy `roles` for paragraph style tokens: `章名`, `节名`, `正文`, `抽言`, `图注`, `开节概述`, `引文`.
- Fonts must resolve to real installed weights or approved aliases. Prefer existing aliases such as `方正兰亭细黑`, `黑体-简 Medium`, `江城律动宋`, `宋体-简`, and `Georgia`. Never invent a weight like "Medium" unless CoreText can resolve it.
- Put uncertain or not-yet-consumed ideas in fields that will land in `unsupportedFields`, or in `meta.designIntent`; do not bury them in implemented-looking names.
- Do not use Figma as the main source of truth. The output is native layoutD JSON that drives sample PDFs and IDML.

## Output Shape

Return:

1. A short extraction summary: grid, typography, color, motifs, rhythm.
2. The spec-pack JSON.
3. A support report:
   - parsed/implemented now,
   - parsed but awaiting renderer/planner consumer,
   - unsupported and intentionally reported.
4. Suggested next validation command or manual check.

## Common Failure Modes

- Overfitting one screenshot: encode a reusable grammar, not a frozen page.
- Treating web design rules as print rules: check trim, margins, baseline, spreads, and InDesign handoff value.
- Adding decorative fields with no consumer and no unsupported trace.
- Choosing fonts by visual resemblance only. Real installed font names and weights matter for IDML.
