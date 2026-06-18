# layoutD

layoutD is a macOS-first AI-assisted layout system for Chinese popular science books.

The first architecture slice focuses on:

- Structured book projects instead of page-only documents.
- Deterministic layout engine for text, images, captions, and science-book components.
- AI layout plans as validated structured data, not final static artwork.
- Native macOS AppKit shell for canvas, sidebar, inspector, and export workflows.

## Current Status

This repository currently contains a Swift Package scaffold:

- `LayoutDCore`: document model, typography, assets, page geometry, layout plan types.
- `LayoutDEngine`: deterministic pagination and frame generation.
- `LayoutDDesignAI`: rule-based and provider-backed AI-advisor boundary for structured `LayoutPlan` candidates.
- `LayoutDImport`: Markdown manuscript importer and image asset scanner.
- `LayoutDCheck`: project and asset issue inspection.
- `LayoutDExport`: PDF export boundary.
- `LayoutDApp`: macOS AppKit desktop shell.

The MVP now supports a practical end-to-end loop: import a Markdown manuscript, scan referenced images, generate cover/contents/body pages, preview the deterministic layout, save a `.layoutd` project, and export a PDF.

## Local Commands

```bash
swift build
swift test
swift run layoutD
```

To preview the sample imported from Markdown:

```bash
swift run layoutD -- Samples/demo.md
```

Inside the app:

- `File -> Open Project, Markdown, or Chapter Package...` opens `.layoutd`, `.json`, `.md`, `.markdown`, `.txt`, or a chapter package directory.
- `File -> Save Project...` saves the current structured project as `.layoutd`.
- `File -> Export PDF...` exports the current layout.
- `File -> Export PNG Previews...` exports page preview images as `page-001.png`, `page-002.png`, and so on.
- `File -> Export Preflight Report...` exports the current project checks as JSON.
- `File -> Import Layout Templates...` and `Export Layout Templates...` move saved layout templates between projects.
- `View -> Zoom In`, `Zoom Out`, `Actual Size`, and `Fit Width` control the canvas scale.
- `View -> Previous Page` and `Next Page` jump through the page stack.
- The left sidebar shows asset role, usage state, pixel size, DPI, and captions; the inspector can edit asset role, caption, and credit/source.
- The inspector edits book metadata including title, subtitle, author, publisher, ISBN, series, and keywords, plus page setup values in millimeters and facing-page layout.
- The inspector can apply project-level style templates: Chinese science default, compact study guide, and image-rich science.
- The inspector can apply reusable chapter layout templates to a selected section and write the resulting page plans into the project.
- Clicking a canvas frame selects it for inspector-based coordinate/size edits; selected image frames can be reassigned to another project asset.
- Clicking a frame-level preflight issue scrolls to the page, highlights and selects the frame, and shows its kind/rect location in the issue list.
- The page sidebar shows lightweight thumbnails based on laid-out frames, with text/image/component counts and lock state.

To preview a manuscript with an image folder:

```bash
swift run layoutD -- path/to/manuscript.md path/to/images
```

To preview a chapter package directory, place the manuscript at `manuscript.md`, `book.md`, `chapter.md`, `content.md`, or `README.md`; alternatively place multiple files in `chapters/*.md` and they will be imported in filename order. Assets can live in `images/` or `assets/`:

```bash
swift run layoutD -- path/to/chapter-package
```

To export an imported manuscript to PDF without opening the app window:

```bash
swift run layoutD -- --export-pdf /tmp/layoutD-demo.pdf Samples/demo.md
```

PDF export also supports page ranges and proofing guides:

```bash
swift run layoutD -- --export-pdf /tmp/layoutD-proof.pdf --pdf-pages 1,3 --pdf-crop-marks --pdf-grid-guides Samples/demo.md
```

To export a structured layoutD project file:

```bash
swift run layoutD -- --export-project /tmp/layoutD-demo.layoutd Samples/demo.md
```

To export saved layout templates as a reusable library:

```bash
swift run layoutD -- --export-templates /tmp/layoutD-templates.json /tmp/layoutD-demo.layoutd
```

To import a template library before exporting or validating:

```bash
swift run layoutD -- --import-templates /tmp/layoutD-templates.json --export-project /tmp/layoutD-with-templates.layoutd Samples/demo.md
```

To apply a reusable chapter template while exporting a project:

```bash
swift run layoutD -- --apply-chapter-template scienceChapter --chapter-template-start-page 3 --export-project /tmp/layoutD-chapter-plan.layoutd Samples/demo.md
```

To export page preview PNG files without opening the app window:

```bash
swift run layoutD -- --export-png /tmp/layoutD-pages Samples/demo.md
```

PNG export also supports page ranges and output scale:

```bash
swift run layoutD -- --export-png /tmp/layoutD-pages --png-pages 1,3 --png-scale 1.5 Samples/demo.md
```

To export a machine-readable preflight report:

```bash
swift run layoutD -- --preflight-report /tmp/layoutD-preflight.json Samples/demo.md
```

To run validation only, using the process exit code as the quality gate:

```bash
swift run layoutD -- --validate Samples/demo.md
```

`--validate` exits with `0` when `exportReady` is true and exits non-zero when loading fails or blocking preflight errors exist.

CLI export and validation can also apply conservative preflight fixes before producing outputs:

```bash
swift run layoutD -- --apply-preflight-fixes --export-project /tmp/layoutD-fixed.layoutd Samples/demo.md
```

To export PDF from a saved layoutD project:

```bash
swift run layoutD -- --export-pdf /tmp/layoutD-from-project.pdf /tmp/layoutD-demo.layoutd
```

The exported PDF can be previewed from Finder, Preview, or rendered with:

```bash
sips -s format png /tmp/layoutD-demo.pdf --out /tmp/layoutD-demo.png
```

The first UI is intentionally minimal. It exists to validate the architecture and rendering loop before adding complex editing behavior.

## Import Pipeline

`LayoutDImport` provides the first MVP input path:

- Parse optional YAML-like front matter for book metadata (`title`, `subtitle`, `author`, `publisher`, `isbn`, `series`, `keywords`) and page setup (`columns`, `page`, `page_width_mm`, `page_height_mm`, `margins`, `gutter_mm`, `baseline_grid_pt`).
- Parse Markdown ATX headings from level 1 through 6, Setext level 1/2 headings, body paragraphs, quotes, admonition-style knowledge cards, simple pipe tables, unordered and ordered list items, and image references while ignoring draft separators and single-line or multi-line HTML comments.
- Clean common inline Markdown markers in imported text, including links, emphasis, strong emphasis, inline code, and escaped marker characters, while preserving literal symbols in terms and formulas such as `snake_case` or `3 * 4`.
- Convert inline or reference-style Markdown images such as `![图注](images/demo.png "role=diagram; credit=作者")` and `![图注][demo]` into structured figure paragraphs.
- Read image metadata from double-quoted or single-quoted Markdown title parameters, including `credit`, `source`, `来源`, and `版权` aliases for image attribution.
- Accept angle-bracket image destinations such as `![图注](<images/cell detail.png>)` for filenames containing spaces.
- Use `anchor=previous` on Markdown images to attach an image to the preceding paragraph instead of creating a standalone figure paragraph.
- Use `span=wide`, `placement=wide`, `role=hero`, or `role=comparison` to request full content-width image placement.
- Scan an image directory with ImageIO and read pixel size, DPI, extension, and inferred image role.
- Merge optional `manifest.csv`, `assets.csv`, or `images.csv` metadata from the image directory, including per-chapter manifests stored in nested asset folders.
- Load a chapter package directory by finding a root Markdown manuscript or ordered `chapters/*.md` files, then scanning `images/` or `assets/` automatically.
- Match image references against scanned assets by exact relative path first, including chapter-package `assets/` or `images/` prefixes, with filename-only matching as a fallback for simple manuscripts.
- Keep unreferenced image files in the asset library for preflight, without automatically placing them into the manuscript layout.
- Return a `BookProject` that can be passed directly into `LayoutDEngine`.

Example manuscript header:

```markdown
---
title: 细胞里的城市
subtitle: 一章面向青少年的生命科学样张
author: layoutD 示例
publisher: layoutD Press
isbn: 978-7-115-54608-1
series: AI 图书排版实验
keywords: 细胞，生命科学，科普图书
columns: 2
page: 185mm x 260mm
margins: 20mm 18mm 24mm 22mm
gutter_mm: 7
baseline_grid_pt: 14
---

![线粒体像城市里的发电站](images/cell-diagram.png "span=wide; credit=layoutD")

细胞膜像城市的边界，控制物质进出。

![细胞膜局部结构](images/membrane-detail.png "anchor=previous; role=diagram; credit=layoutD")
```

Image metadata can also live beside the images:

```csv
file,caption,span,credit
cell-diagram.png,线粒体像城市里的发电站,wide,layoutD
```

With that CSV present in the image folder, Markdown can simply reference the asset:

```markdown
![](images/cell-diagram.png)
```

Admonition quotes become science-book callouts:

```markdown
> [!NOTE] 线粒体
> 它负责把营养物质转化成细胞能直接使用的能量。
```

This keeps manuscript import separate from final page layout. Importers create structured content; the layout engine decides pagination and placement.

`Samples/demo.md` and `Samples/images/cell-diagram.png` provide a small end-to-end sample with a real image.

## Layout And Export

The deterministic engine currently generates:

- Cover page from project metadata.
- Contents page from section/story headings.
- Two-column Chinese science-book body pages on a 185mm x 260mm page setup.
- Image frames sized by asset role and aspect ratio.
- Image placement only for figures explicitly referenced by the manuscript or anchored to a paragraph.
- Lightweight page thumbnails in the navigation sidebar, derived from the same `LaidOutPage` frames used by canvas/PDF export.
- Sidebar asset library with role, usage state, pixel size, DPI, and caption summary, plus inspector editing for asset role, caption, and credit/source.
- Full content-width image placement for hero/comparison/wide images, with a column barrier that prevents later text from overlapping the image.
- Automatic cross-column splitting for long body/callout text.
- Heading keep-with-next behavior to avoid stranded headings at the bottom of a column.
- Automatic spacing between adjacent Chinese ideographs and ASCII letters/numbers in laid-out text.
- Automatic figure caption numbering when captions do not already start with `图`.
- Captions, visually boxed callouts, running headers, and exported page numbers.
- Page preview PNG export for quick review or downstream thumbnails, including page-range and output-scale options.
- Canvas frame selection with inspector-based manual positioning and image replacement, constrained to valid page bounds and minimum frame size; preflight issue clicks select the affected frame for immediate editing.
- Reusable page-level layout templates for text-led, image-led, balanced image/text, and knowledge-card pages, shared by the rule-based layout advisor.
- Reusable chapter-level layout templates that produce page-keyed plan sets for science chapters, image-rich chapters, and study-guide chapters, with App and CLI application into `appliedLayoutPlans`.
- Saved layout templates in project data, with retargeting support for reusing a saved `LayoutPlan` on another page, spread, or section; the inspector can save the current page as a template, apply saved templates to the current page, rename templates, and delete stale templates. App and CLI template libraries can export/import saved templates across projects.
- Layout/project issues for incomplete book metadata, invalid ISBN-13, unreferenced library images, repeated image use, missing captions, effective print DPI, missing source images, duplicate filenames, missing asset references, empty structure, broken page sequences, table-of-contents page drift, extreme paragraph overflow, Chinese line-break punctuation violations including common Chinese quotes/brackets, text overflow inside frames, frame overlap, out-of-bounds frames, empty text frames, and missing image frames.
- JSON preflight reports with issue counts, category counts, asset summary, layout frame summary including table frames, page count, explicit `exportReady`, frame-level `issueLocations`, `suggestedFix` guidance for common issues, and a `qualityMetrics` block (page count, AI/template plan-applied pages, auto laid-out pages, low-DPI and missing-caption asset counts, layout issue count) aligned with the PRD success indicators, plus inspector severity/category filtering for focused issue review.
- Conservative preflight auto-fixes for missing publisher/keywords, invalid ISBN removal, missing asset captions/credits, and stale source paths, exposed from the inspector and CLI for issues that advertise an `autoFixKind`.
- Inspector editing for book metadata, image metadata, styles, project-level style templates, and page setup with millimeter-based spacing controls and facing-page toggle.

## Verification

`swift build` and `swift test` both pass on a full Xcode toolchain. The suite
currently holds 124 test functions covering import, pagination, Chinese
line-break and spacing rules, the AI provider fallback, page/chapter/saved
layout templates and library import/export, preflight categories and auto-fixes,
layout-plan validation fallback, and PDF/PNG/project/preflight export. The exact
count is whatever `swift test` reports — it is intentionally not pinned here so
the README does not drift as tests are added.
