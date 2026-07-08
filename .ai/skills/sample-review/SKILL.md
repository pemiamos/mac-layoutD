---
name: sample-review
description: Review layoutD generated sample PDFs, PNGs, screenshots, or IDML previews against a reference image or approved spec pack. Use when judging whether a sample looks like the target style, diagnosing missing motifs, checking print-layout rhythm across pages, or producing a style report for station 3 baseline lock.
---

# Sample Review

## Workflow

1. Load the reference image or approved spec pack, the generated sample, and any support report from `SpecPackImportResult.unsupportedFields`.
2. Compare print-layout structure first, surface polish second. This project values editable IDML initial layout, not pixel-perfect screenshot cloning.
3. Score the sample on the dimensions below and identify the smallest spec-pack or renderer/planner change that would improve it.
4. Separate findings into:
   - spec-pack data problem,
   - parsed but not consumed,
   - renderer/planner implementation gap,
   - acceptable InDesign hand-tuning issue.

## Scoring Rubric

Use 0-5 for each dimension.

- **Page geometry**: trim ratio, margins, column count, gutter, baseline rhythm.
- **Type hierarchy**: chapter title scale, section title contrast, body size/leading, caption smallness, pull quote distinction.
- **Color discipline**: black/gray/paper base, accent sparseness, no accidental rainbow or muddy palette.
- **Motif fidelity**: ghost chapter number, section number, running header, caption tick, heading rule, pull-quote rule.
- **Spread rhythm**: no consecutive identical layouts, useful big-image breathing room, balanced text/image density.
- **Content integrity**: no role-label leakage, no missing images/captions, no overlapping frames, no overflow.
- **IDML handoff value**: threaded text remains editable; fixes needed in InDesign are localized and expected.

## Report Format

Return:

```markdown
## Verdict
Score: NN/35
Decision: pass / revise spec / renderer gap / planner gap

## Findings
- [P1] Concrete issue, evidence, affected page/spread, likely source.
- [P2] ...

## Spec-Pack Adjustments
- JSON path: proposed value and reason.

## Implementation Gaps
- Consumer missing for parsed field, or renderer/planner behavior needed.

## InDesign Manual Checks
- Items automation cannot verify visually.
```

## Diagnosis Heuristics

- If the sample has correct fonts, trim, and colors but lacks ghost numbers, headers, or section numbers, check whether `motifs` parsed and whether a renderer consumes them.
- If a motif appears in one output path but not another, suspect renderer parity. PDF/PNG/Canvas/IDML often need parallel consumers.
- If single pages look fine but a 12-20 page run feels monotonous, push the issue into `layoutGrammar.rhythm` or planner scoring, not paragraph styles.
- If body text edits in InDesign would break the layout completely, prioritize threaded flow and frame order over decorative fidelity.
- If a visual detail is rare and cheap to fix in InDesign, mark it as manual polish rather than blocking the initial-layout pipeline.
