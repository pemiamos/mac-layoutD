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

- Parse Markdown headings, body paragraphs, quotes, list items, and image references.
- Convert Markdown images such as `![图注](images/demo.png)` into structured figure paragraphs.
- Scan an image directory with ImageIO and read pixel size, DPI, extension, and inferred image role.
- Return a `BookProject` that can be passed directly into `LayoutDEngine`.

This keeps manuscript import separate from final page layout. Importers create structured content; the layout engine decides pagination and placement.

`Samples/demo.md` and `Samples/images/cell-diagram.png` provide a small end-to-end sample with a real image.
