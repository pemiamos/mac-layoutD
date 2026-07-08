import AppKit
import Combine
import Foundation
import LayoutDCheck
import LayoutDCore
import LayoutDDesignAI
import LayoutDEngine
import LayoutDExport
import LayoutDImport
import SwiftUI
import UniformTypeIdentifiers

let commandLineUsage = """
layoutD

Usage:
  swift run layoutD -- [options] [manuscript.md|project.layoutd|chapter-directory] [image-directory]

Options:
  --export-pdf PATH          Export a proof PDF without opening the app window.
  --export-pdf-flow PATH     Export a proof PDF in flowing layout (ignoring templates).
  --pdf-pages RANGE          Limit PDF export to pages such as "1,3" or "2-5".
  --pdf-crop-marks          Add crop and bleed guide marks to PDF export.
  --pdf-grid-guides         Add margin, column, and baseline guides to PDF export.
  --pdf-version VERSION     Select RGB output intent tag: none, pdfx1a/SWOP, or pdfx3/FOGRA39.
  --export-png DIRECTORY    Export page preview PNG files.
  --export-png-flow DIRECTORY Export page preview PNG files in flowing layout (ignoring templates).
  --png-pages RANGE         Limit PNG export to pages such as "1,3" or "2-5".
  --png-scale VALUE         Set PNG output scale, default 2.0.
  --export-project PATH     Export a structured .layoutd project file.
  --export-package PATH     Export a packaged ZIP resource bundle (.layoutd-pack).
  --export-idml PATH        Export an IDML package for InDesign 人工精调 + 印前 (阶段 E1 最小可用).
  --idml-facing             Export IDML in facing-pages (对开跨页) spreads (默认单页).
  --export-templates PATH   Export saved layout templates as a reusable JSON library.
  --import-templates PATH   Import a layout template library before export or validation.
  --spec-pack PATH          Apply a layoutD visual spec pack (规范包 JSON: 字体/角色色/开本/网格) before any export (IDML/PDF/PNG).
  --apply-chapter-template NAME
                            Apply a chapter template: scienceChapter, imageRichChapter, or studyGuideChapter.
  --chapter-template-section N
                            Section number for --apply-chapter-template, default 1.
  --chapter-template-start-page N
                            First page for --apply-chapter-template plans, default 3.
  --preflight-report PATH   Export preflight JSON.
  --validate                Run preflight as a CLI quality gate.
  --apply-preflight-fixes   Apply conservative auto-fixes before export or validation.
  --idml-spike PATH         Write a minimal IDML probe (spread + 中文/竖排文本框 + 置入图 + CMYK Swatch) to open in InDesign. Optional second arg: image path.
  --render-samples JSON...  Batch render a set of visual specification packages as proof PDFs on the Desktop.
  --chapter PATH            Specify the chapter manuscript or package path to use for rendering samples.
  --help, -h                Show this help.
"""

// 阶段 E0：IDML 灌版路线最小验证。独立早退分支，不经 ProjectLoader——它写死一份
// 最小 IDML，用于在 InDesign 中文版里证伪 CJK（尤其竖排）能否干净落地。
if let idmlFlagIndex = CommandLine.arguments.firstIndex(of: "--idml-spike") {
    let args = CommandLine.arguments
    guard idmlFlagIndex + 1 < args.count else {
        fputs("--idml-spike 需要一个输出路径。\n", stderr)
        exit(EXIT_FAILURE)
    }
    let outputURL = URL(fileURLWithPath: args[idmlFlagIndex + 1])
    // 可选第二参（不以 - 开头）作为置入图路径；缺省回退到 Samples/images/cell-diagram.png。
    var imagePath: String? = nil
    let maybeImageIndex = idmlFlagIndex + 2
    if maybeImageIndex < args.count, !args[maybeImageIndex].hasPrefix("-") {
        imagePath = args[maybeImageIndex]
    } else if FileManager.default.fileExists(atPath: "Samples/images/cell-diagram.png") {
        imagePath = "Samples/images/cell-diagram.png"
    }
    do {
        try IDMLSpikeExporter().export(to: outputURL, imagePath: imagePath)
        print("Wrote IDML spike: \(outputURL.path)")
        if let imagePath { print("Linked image: \(imagePath)") }
        print("下一步：在 InDesign 中文版打开它，确认能干净打开、样式/图链/颜色/竖排都在。")
        exit(EXIT_SUCCESS)
    } catch {
        fputs("IDML spike failed: \(error.localizedDescription)\n", stderr)
        exit(EXIT_FAILURE)
    }
}

let launchProject = ProjectLoader().loadFromCommandLine()

if let renderSamplesPaths = launchProject.renderSamplesPaths, !renderSamplesPaths.isEmpty {
    let chapterPath = launchProject.renderSamplesChapterPath ?? "Samples/fixture-standard-chapter.md"
    let chapterURL = URL(fileURLWithPath: chapterPath).standardizedFileURL
    print("Loading chapter fixture from: \(chapterURL.path)")
    
    let baseProject: BookProject
    do {
        baseProject = try ProjectLoader().loadProject(inputURL: chapterURL)
    } catch {
        fputs("Failed to load chapter fixture: \(error.localizedDescription)\n", stderr)
        exit(EXIT_FAILURE)
    }
    
    let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop")
    
    for specPath in renderSamplesPaths {
        let specURL = URL(fileURLWithPath: specPath).standardizedFileURL
        print("Processing spec package: \(specURL.path)")
        
        do {
            let jsonData = try Data(contentsOf: specURL)
            let result = try StyleBaselineImporter.parseSpecPack(jsonData: jsonData)
            
            if !result.unsupportedFields.isEmpty {
                fputs("Warning: Unsupported spec fields in \(specURL.lastPathComponent): \(result.unsupportedFields.joined(separator: ", "))\n", stderr)
            }
            
            var updatedProject = baseProject
            updatedProject.applySpecPack(result)
            let document = LayoutEngine().layout(project: updatedProject)
            
            let baseName = specURL.deletingPathExtension().lastPathComponent
            let filename = "layoutD-样张-\(baseName).pdf"
            let outputPDFURL = desktopURL.appendingPathComponent(filename)
            
            try PDFExporter().export(
                document: document,
                project: updatedProject,
                to: outputPDFURL,
                pageRange: nil,
                drawCropMarks: false,
                drawGridGuides: false,
                pdfxVersion: .none
            )
            print("Successfully rendered: \(outputPDFURL.path)")
        } catch {
            fputs("Error rendering spec \(specPath): \(error.localizedDescription)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
    exit(EXIT_SUCCESS)
}

if launchProject.showHelp {
    print(commandLineUsage)
    exit(EXIT_SUCCESS)
}

if launchProject.exportPDFURL != nil
    || launchProject.exportPDFFlowURL != nil
    || launchProject.exportPNGDirectoryURL != nil
    || launchProject.exportPNGFlowDirectoryURL != nil
    || launchProject.exportProjectURL != nil
    || launchProject.exportPackageURL != nil
    || launchProject.exportIDMLURL != nil
    || launchProject.exportTemplateLibraryURL != nil
    || launchProject.preflightReportURL != nil
    || launchProject.validateOnly {
    do {
        if let loadError = launchProject.loadError {
            fputs("Load failed: \(loadError)\n", stderr)
            exit(EXIT_FAILURE)
        }

        var project = launchProject.project
        var document = LayoutEngine().layout(project: project)
        var report = ProjectInspector().preflight(
            project: project,
            document: document,
            exportOptions: PrepressExportOptions(
                pdfxRequested: launchProject.pdfxVersion != .none,
                pdfxLabel: launchProject.pdfxVersion.pdfxStandardName,
                drawCropMarks: launchProject.exportPDFDrawCropMarks
            )
        )

        if let chapterLayoutTemplate = launchProject.chapterLayoutTemplate {
            let appliedCount = project.applyChapterLayoutTemplate(
                chapterLayoutTemplate,
                sectionIndex: launchProject.chapterLayoutTemplateSectionIndex,
                startPage: launchProject.chapterLayoutTemplateStartPage
            )
            document = LayoutEngine().layout(project: project)
            report = ProjectInspector().preflight(
                project: project,
                document: document,
                exportOptions: PrepressExportOptions(
                    pdfxRequested: launchProject.pdfxVersion != .none,
                    pdfxLabel: launchProject.pdfxVersion.pdfxStandardName,
                    drawCropMarks: launchProject.exportPDFDrawCropMarks
                )
            )
            print("Applied chapter template: \(chapterLayoutTemplate.rawValue), \(appliedCount) page plan(s)")
        }

        if launchProject.applyPreflightFixes {
            let result = PreflightAutoFixer().applyAvailableFixes(
                to: project,
                issues: report.issues
            )
            if !result.appliedFixes.isEmpty {
                project = result.project
                document = LayoutEngine().layout(project: project)
                report = ProjectInspector().preflight(
                    project: project,
                    document: document,
                    exportOptions: PrepressExportOptions(
                        pdfxRequested: launchProject.pdfxVersion != .none,
                        pdfxLabel: launchProject.pdfxVersion.pdfxStandardName,
                        drawCropMarks: launchProject.exportPDFDrawCropMarks
                    )
                )
            }
            print("Applied preflight fixes: \(result.appliedFixes.count)")
        }

        if let exportProjectURL = launchProject.exportProjectURL {
            let data = try ProjectFile.encode(projectForSaving(project))
            try createParentDirectory(for: exportProjectURL)
            try data.write(to: exportProjectURL, options: .atomic)
            print("Exported project: \(exportProjectURL.path)")
        }

        if let exportPackageURL = launchProject.exportPackageURL {
            try ResourceBundlePackager().package(project: project, to: exportPackageURL)
            print("Exported project package: \(exportPackageURL.path)")
        }

        if let exportTemplateLibraryURL = launchProject.exportTemplateLibraryURL {
            let library = LayoutTemplateLibrary(project: project)
            let data = try LayoutTemplateLibrary.encode(library)
            try createParentDirectory(for: exportTemplateLibraryURL)
            try data.write(to: exportTemplateLibraryURL, options: .atomic)
            print("Exported layout templates: \(library.templates.count) template(s) to \(exportTemplateLibraryURL.path)")
        }

        if let preflightReportURL = launchProject.preflightReportURL {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(report)
            try createParentDirectory(for: preflightReportURL)
            try data.write(to: preflightReportURL, options: .atomic)
            print("Exported preflight report: \(preflightReportURL.path)")
        }

        if let exportPDFURL = launchProject.exportPDFURL {
            try PDFExporter().export(
                document: document,
                project: project,
                to: exportPDFURL,
                pageRange: launchProject.exportPDFPageRange,
                drawCropMarks: launchProject.exportPDFDrawCropMarks,
                drawGridGuides: launchProject.exportPDFDrawGridGuides,
                pdfxVersion: launchProject.pdfxVersion
            )
            print("Exported PDF: \(exportPDFURL.path)")
        }

        if let exportPDFFlowURL = launchProject.exportPDFFlowURL {
            var flowProject = project
            flowProject.appliedLayoutPlans = nil
            let flowDocument = LayoutEngine().layout(project: flowProject)
            try PDFExporter().export(
                document: flowDocument,
                project: flowProject,
                to: exportPDFFlowURL,
                pageRange: launchProject.exportPDFPageRange,
                drawCropMarks: launchProject.exportPDFDrawCropMarks,
                drawGridGuides: launchProject.exportPDFDrawGridGuides,
                pdfxVersion: launchProject.pdfxVersion
            )
            print("Exported PDF Flow: \(exportPDFFlowURL.path)")
        }

        if let exportIDMLURL = launchProject.exportIDMLURL {
            try IDMLExporter().export(document: document, project: project, to: exportIDMLURL,
                                      options: IDMLExportOptions(facingPages: launchProject.exportIDMLFacing))
            print("Exported IDML: \(exportIDMLURL.path)\(launchProject.exportIDMLFacing ? " (对开)" : "")")
        }

        if let exportPNGDirectoryURL = launchProject.exportPNGDirectoryURL {
            let outputURLs = try PNGExporter().export(
                document: document,
                project: project,
                to: exportPNGDirectoryURL,
                pageRange: launchProject.exportPNGPageRange,
                scale: launchProject.exportPNGScale
            )
            print("Exported PNG previews: \(outputURLs.count) file(s) to \(exportPNGDirectoryURL.path)")
        }

        if let exportPNGFlowDirectoryURL = launchProject.exportPNGFlowDirectoryURL {
            var flowProject = project
            flowProject.appliedLayoutPlans = nil
            let flowDocument = LayoutEngine().layout(project: flowProject)
            let outputURLs = try PNGExporter().export(
                document: flowDocument,
                project: flowProject,
                to: exportPNGFlowDirectoryURL,
                pageRange: launchProject.exportPNGPageRange,
                scale: launchProject.exportPNGScale
            )
            print("Exported PNG Flow previews: \(outputURLs.count) file(s) to \(exportPNGFlowDirectoryURL.path)")
        }

        if launchProject.validateOnly {
            if report.exportReady {
                print("Validation passed: \(project.metadata.title)")
            } else {
                fputs("Validation failed: \(report.severityCounts[IssueSeverity.error.rawValue, default: 0]) error(s)\n", stderr)
                for issue in report.issues where issue.severity == .error {
                    fputs("- \(issue.message)\n", stderr)
                }
                exit(2)
            }
        }
        exit(EXIT_SUCCESS)
    } catch {
        fputs("Export failed: \(error.localizedDescription)\n", stderr)
        exit(EXIT_FAILURE)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate(launchProject: launchProject)
app.delegate = delegate
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()

func createParentDirectory(for url: URL) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
}

func projectForSaving(_ project: BookProject) -> BookProject {
    var project = project
    project.metadata.modifiedAt = Date()
    return project
}
