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
- `LayoutDDesignAI`: rule-based AI-advisor boundary that can later call model providers.
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

- `File -> Open Project or Markdown...` opens `.layoutd`, `.json`, `.md`, `.markdown`, or `.txt`.
- `File -> Save Project...` saves the current structured project as `.layoutd`.
- `File -> Export PDF...` exports the current layout.
- `File -> Export Preflight Report...` exports the current project checks as JSON.
- `View -> Zoom In`, `Zoom Out`, `Actual Size`, and `Fit Width` control the canvas scale.
- `View -> Previous Page` and `Next Page` jump through the page stack.

To preview a manuscript with an image folder:

```bash
swift run layoutD -- path/to/manuscript.md path/to/images
```

To export an imported manuscript to PDF without opening the app window:

```bash
swift run layoutD -- --export-pdf /tmp/layoutD-demo.pdf Samples/demo.md
```

To export a structured layoutD project file:

```bash
swift run layoutD -- --export-project /tmp/layoutD-demo.layoutd Samples/demo.md
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
- Parse Markdown headings, body paragraphs, quotes, admonition-style knowledge cards, simple pipe tables, list items, and image references while ignoring draft separators and HTML comments.
- Convert Markdown images such as `![图注](images/demo.png "role=diagram; credit=作者")` into structured figure paragraphs.
- Use `span=wide`, `placement=wide`, `role=hero`, or `role=comparison` to request full content-width image placement.
- Scan an image directory with ImageIO and read pixel size, DPI, extension, and inferred image role.
- Merge optional `manifest.csv`, `assets.csv`, or `images.csv` metadata from the image directory.
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
- Full content-width image placement for hero/comparison/wide images, with a column barrier that prevents later text from overlapping the image.
- Automatic cross-column splitting for long body/callout text.
- Heading keep-with-next behavior to avoid stranded headings at the bottom of a column.
- Automatic figure caption numbering when captions do not already start with `图`.
- Captions, visually boxed callouts, running headers, and exported page numbers.
- Layout/project issues for incomplete book metadata, invalid ISBN-13, unreferenced library images, missing captions, effective print DPI, missing source images, duplicate filenames, missing asset references, empty structure, broken page sequences, extreme paragraph overflow, Chinese line-break punctuation violations, text overflow inside frames, frame overlap, out-of-bounds frames, empty text frames, and missing image frames.
- JSON preflight reports with issue counts, asset summary, layout frame summary including table frames, page count, and explicit `exportReady`.

Current verification:

```text
swift test: pass, 38 tests
Markdown -> PDF export: pass
Markdown -> .layoutd -> PDF export: pass
Markdown -> preflight JSON export: pass
CLI validate success/failure exits: pass
Wide image PDF page render: pass
Image manifest import: pass
Layout defect validation: pass
Text overflow validation: pass
Chinese line-break preflight: pass
Markdown knowledge-card import: pass
Heading keep-with-next layout: pass
Markdown draft-marker cleanup: pass
Callout PDF export: pass
Front matter margin/gutter import: pass
Page sequence preflight: pass
Layout frame summary: pass
Book metadata import and ISBN preflight: pass
Legacy .layoutd metadata decode: pass
Markdown table import and table frame layout: pass
```
