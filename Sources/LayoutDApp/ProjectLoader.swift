import Foundation
import LayoutDCore
import LayoutDDesignAI
import LayoutDImport
import LayoutDExport

struct LoadedProject {
    var project: BookProject
    var sourceDescription: String
    var exportPDFURL: URL?
    var exportPDFPageRange: String?
    var exportPDFDrawCropMarks: Bool
    var exportPDFDrawGridGuides: Bool
    var exportPNGDirectoryURL: URL?
    var exportPNGPageRange: String?
    var exportPNGScale: Double
    var exportProjectURL: URL?
    var exportTemplateLibraryURL: URL?
    var preflightReportURL: URL?
    var validateOnly: Bool
    var applyPreflightFixes: Bool
    var chapterLayoutTemplate: ChapterLayoutTemplate?
    var chapterLayoutTemplateSectionIndex: Int
    var chapterLayoutTemplateStartPage: Int
    var showHelp: Bool
    var loadError: String?
    var exportPackageURL: URL?
    var pdfxVersion: PDFXVersion
}

struct ProjectLoader {
    func loadFromCommandLine(arguments: [String] = CommandLine.arguments) -> LoadedProject {
        let options = CommandLineOptions(arguments: Array(arguments.dropFirst()))
        guard let manuscriptPath = options.manuscriptPath else {
            let project: BookProject
            let loadError: String?
            do {
                project = try importingTemplateLibraryIfNeeded(
                    into: .sample,
                    from: options.importTemplateLibraryPath
                )
                loadError = nil
            } catch {
                project = .sample
                loadError = error.localizedDescription
            }

            return LoadedProject(
                project: project,
                sourceDescription: "内置样章",
                exportPDFURL: options.exportPDFPath.map { URL(fileURLWithPath: $0).standardizedFileURL },
                exportPDFPageRange: options.exportPDFPageRange,
                exportPDFDrawCropMarks: options.exportPDFDrawCropMarks,
                exportPDFDrawGridGuides: options.exportPDFDrawGridGuides,
                exportPNGDirectoryURL: options.exportPNGDirectoryPath.map { URL(fileURLWithPath: $0).standardizedFileURL },
                exportPNGPageRange: options.exportPNGPageRange,
                exportPNGScale: options.exportPNGScale,
                exportProjectURL: options.exportProjectPath.map { URL(fileURLWithPath: $0).standardizedFileURL },
                exportTemplateLibraryURL: options.exportTemplateLibraryPath.map { URL(fileURLWithPath: $0).standardizedFileURL },
                preflightReportURL: options.preflightReportPath.map { URL(fileURLWithPath: $0).standardizedFileURL },
                validateOnly: options.validateOnly,
                applyPreflightFixes: options.applyPreflightFixes,
                chapterLayoutTemplate: options.chapterLayoutTemplate,
                chapterLayoutTemplateSectionIndex: options.chapterLayoutTemplateSectionIndex,
                chapterLayoutTemplateStartPage: options.chapterLayoutTemplateStartPage,
                showHelp: options.showHelp,
                loadError: loadError,
                exportPackageURL: options.exportPackagePath.map { URL(fileURLWithPath: $0).standardizedFileURL },
                pdfxVersion: options.pdfxVersion
            )
        }

        let manuscriptURL = URL(fileURLWithPath: manuscriptPath).standardizedFileURL
        do {
            let loadedProject = try loadProject(
                inputURL: manuscriptURL,
                assetDirectoryURL: options.assetDirectoryPath.map { URL(fileURLWithPath: $0).standardizedFileURL }
            )
            let project = try importingTemplateLibraryIfNeeded(
                into: loadedProject,
                from: options.importTemplateLibraryPath
            )
            return LoadedProject(
                project: project,
                sourceDescription: sourceDescription(for: manuscriptURL),
                exportPDFURL: options.exportPDFPath.map { URL(fileURLWithPath: $0).standardizedFileURL },
                exportPDFPageRange: options.exportPDFPageRange,
                exportPDFDrawCropMarks: options.exportPDFDrawCropMarks,
                exportPDFDrawGridGuides: options.exportPDFDrawGridGuides,
                exportPNGDirectoryURL: options.exportPNGDirectoryPath.map { URL(fileURLWithPath: $0).standardizedFileURL },
                exportPNGPageRange: options.exportPNGPageRange,
                exportPNGScale: options.exportPNGScale,
                exportProjectURL: options.exportProjectPath.map { URL(fileURLWithPath: $0).standardizedFileURL },
                exportTemplateLibraryURL: options.exportTemplateLibraryPath.map { URL(fileURLWithPath: $0).standardizedFileURL },
                preflightReportURL: options.preflightReportPath.map { URL(fileURLWithPath: $0).standardizedFileURL },
                validateOnly: options.validateOnly,
                applyPreflightFixes: options.applyPreflightFixes,
                chapterLayoutTemplate: options.chapterLayoutTemplate,
                chapterLayoutTemplateSectionIndex: options.chapterLayoutTemplateSectionIndex,
                chapterLayoutTemplateStartPage: options.chapterLayoutTemplateStartPage,
                showHelp: options.showHelp,
                loadError: nil,
                exportPackageURL: options.exportPackagePath.map { URL(fileURLWithPath: $0).standardizedFileURL },
                pdfxVersion: options.pdfxVersion
            )
        } catch {
            var project = BookProject.sample
            project.metadata.title = "导入失败"
            project.sections = [
                BookSection(
                    title: "导入失败",
                    stories: [
                        Story(
                            title: "导入失败",
                            paragraphs: [
                                Paragraph(
                                    kind: .heading(level: 1),
                                    text: "无法导入书稿",
                                    styleId: StyleID.heading1.rawValue
                                ),
                                Paragraph(
                                    kind: .body,
                                    text: "\(manuscriptURL.path)\n\n\(error.localizedDescription)",
                                    styleId: StyleID.body.rawValue
                                )
                            ]
                        )
                    ]
                )
            ]
            project.assets = []
            return LoadedProject(
                project: project,
                sourceDescription: "导入失败",
                exportPDFURL: options.exportPDFPath.map { URL(fileURLWithPath: $0).standardizedFileURL },
                exportPDFPageRange: options.exportPDFPageRange,
                exportPDFDrawCropMarks: options.exportPDFDrawCropMarks,
                exportPDFDrawGridGuides: options.exportPDFDrawGridGuides,
                exportPNGDirectoryURL: options.exportPNGDirectoryPath.map { URL(fileURLWithPath: $0).standardizedFileURL },
                exportPNGPageRange: options.exportPNGPageRange,
                exportPNGScale: options.exportPNGScale,
                exportProjectURL: options.exportProjectPath.map { URL(fileURLWithPath: $0).standardizedFileURL },
                exportTemplateLibraryURL: options.exportTemplateLibraryPath.map { URL(fileURLWithPath: $0).standardizedFileURL },
                preflightReportURL: options.preflightReportPath.map { URL(fileURLWithPath: $0).standardizedFileURL },
                validateOnly: options.validateOnly,
                applyPreflightFixes: options.applyPreflightFixes,
                chapterLayoutTemplate: options.chapterLayoutTemplate,
                chapterLayoutTemplateSectionIndex: options.chapterLayoutTemplateSectionIndex,
                chapterLayoutTemplateStartPage: options.chapterLayoutTemplateStartPage,
                showHelp: options.showHelp,
                loadError: error.localizedDescription,
                exportPackageURL: options.exportPackagePath.map { URL(fileURLWithPath: $0).standardizedFileURL },
                pdfxVersion: options.pdfxVersion
            )
        }
    }

    func loadProject(inputURL: URL, assetDirectoryURL: URL? = nil) throws -> BookProject {
        if isDirectory(inputURL) {
            return try loadPackageProject(packageURL: inputURL, assetDirectoryURL: assetDirectoryURL)
        }

        switch inputURL.pathExtension.lowercased() {
        case "layoutd", "json":
            let data = try Data(contentsOf: inputURL)
            let project = try ProjectFile.decode(data)
            return resolvingRelativeAssetPaths(in: project, relativeTo: inputURL.deletingLastPathComponent())
        default:
            return try loadMarkdownProject(manuscriptURL: inputURL, assetDirectoryURL: assetDirectoryURL)
        }
    }

    func sourceDescription(for inputURL: URL) -> String {
        if isDirectory(inputURL) {
            return "章节包：\(inputURL.lastPathComponent)"
        }

        switch inputURL.pathExtension.lowercased() {
        case "layoutd", "json":
            return "项目：\(inputURL.lastPathComponent)"
        default:
            return "导入：\(inputURL.lastPathComponent)"
        }
    }

    private func importingTemplateLibraryIfNeeded(
        into project: BookProject,
        from path: String?
    ) throws -> BookProject {
        guard let path else {
            return project
        }

        let url = URL(fileURLWithPath: path).standardizedFileURL
        let data = try Data(contentsOf: url)
        let library = try LayoutTemplateLibrary.decode(data)
        return project.importingLayoutTemplateLibrary(library)
    }

    private func loadPackageProject(packageURL: URL, assetDirectoryURL: URL?) throws -> BookProject {
        let manuscriptURLs = try packageManuscriptURLs(packageURL)
        let markdown = try manuscriptURLs
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n\n")
        let assets = try loadPackageAssets(
            packageURL: packageURL,
            explicitAssetDirectoryURL: assetDirectoryURL
        )
        var project = MarkdownBookImporter(defaultAuthor: NSUserName()).importDocument(
            markdown: markdown,
            assetCatalog: AssetCatalog(assets: assets),
            fallbackTitle: packageURL.lastPathComponent
        )
        
        let stylesURL = packageURL.appendingPathComponent("styles.json")
        let stylesAltURL = packageURL.appendingPathComponent("styles.layoutd-styles")
        var stylesData = try? Data(contentsOf: stylesURL)
        if stylesData == nil {
            stylesData = try? Data(contentsOf: stylesAltURL)
        }
        if let stylesData,
           let styleLibrary = try? JSONDecoder().decode(StyleLibrary.self, from: stylesData) {
            project.styles = styleLibrary
        }
        
        let templatesURL = packageURL.appendingPathComponent("templates.json")
        let templatesAltURL = packageURL.appendingPathComponent("templates.layoutd-templates")
        var templatesData = try? Data(contentsOf: templatesURL)
        if templatesData == nil {
            templatesData = try? Data(contentsOf: templatesAltURL)
        }
        if let templatesData,
           let templateLibrary = try? LayoutTemplateLibrary.decode(templatesData) {
            project.importLayoutTemplateLibrary(templateLibrary)
        }
        
        let metadataURL = packageURL.appendingPathComponent("metadata.json")
        let bookJSONURL = packageURL.appendingPathComponent("book.json")
        var metadataData = try? Data(contentsOf: metadataURL)
        if metadataData == nil {
            metadataData = try? Data(contentsOf: bookJSONURL)
        }
        if let metadataData,
           let metadata = try? JSONDecoder().decode(ProjectMetadata.self, from: metadataData) {
            project.metadata = metadata
        }
        
        return project
    }

    private func packageManuscriptURLs(_ packageURL: URL) throws -> [URL] {
        let rootCandidateNames = [
            "manuscript.md",
            "book.md",
            "chapter.md",
            "content.md"
        ]

        for name in rootCandidateNames {
            let candidate = packageURL.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return [candidate]
            }
        }

        let chaptersURL = packageURL.appendingPathComponent("chapters")
        if isDirectory(chaptersURL) {
            let chapterFiles = try FileManager.default.contentsOfDirectory(
                at: chaptersURL,
                includingPropertiesForKeys: nil
            )
            .filter { ["md", "markdown", "txt"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

            if !chapterFiles.isEmpty {
                return chapterFiles
            }
        }

        let readmeURL = packageURL.appendingPathComponent("README.md")
        if FileManager.default.fileExists(atPath: readmeURL.path) {
            return [readmeURL]
        }

        throw CocoaError(
            .fileNoSuchFile,
            userInfo: [
                NSFilePathErrorKey: packageURL.path,
                NSLocalizedDescriptionKey: "章节包缺少根目录 manuscript.md、book.md、chapter.md、content.md、README.md 或 chapters/*.md"
            ]
        )
    }

    private func loadPackageAssets(packageURL: URL, explicitAssetDirectoryURL: URL?) throws -> [Asset] {
        let scanner = AssetScanner()
        if let explicitAssetDirectoryURL {
            return try scanner.scan(directory: explicitAssetDirectoryURL)
        }

        for name in ["images", "assets"] {
            let candidate = packageURL.appendingPathComponent(name)
            if isDirectory(candidate) {
                return try scanner.scan(directory: candidate)
            }
        }

        return []
    }

    private func loadMarkdownProject(manuscriptURL: URL, assetDirectoryURL: URL?) throws -> BookProject {
        let markdown = try String(contentsOf: manuscriptURL, encoding: .utf8)
        let assets = try loadAssets(assetDirectoryURL: assetDirectoryURL, manuscriptURL: manuscriptURL)
        return MarkdownBookImporter(defaultAuthor: NSUserName()).importDocument(
            markdown: markdown,
            assetCatalog: AssetCatalog(assets: assets),
            fallbackTitle: manuscriptURL.deletingPathExtension().lastPathComponent
        )
    }

    private func loadAssets(assetDirectoryURL: URL?, manuscriptURL: URL) throws -> [Asset] {
        let scanner = AssetScanner()
        if let assetDirectoryURL {
            return try scanner.scan(directory: assetDirectoryURL)
        }

        let localImagesURL = manuscriptURL.deletingLastPathComponent().appendingPathComponent("images")
        guard FileManager.default.fileExists(atPath: localImagesURL.path) else {
            return []
        }
        return try scanner.scan(directory: localImagesURL)
    }

    private func resolvingRelativeAssetPaths(in project: BookProject, relativeTo baseURL: URL) -> BookProject {
        var project = project
        for index in project.assets.indices {
            guard let sourcePath = project.assets[index].sourcePath,
                  !sourcePath.isEmpty,
                  !sourcePath.hasPrefix("/") else {
                continue
            }
            project.assets[index].sourcePath = baseURL
                .appendingPathComponent(sourcePath)
                .standardizedFileURL
                .path
        }
        return project
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }
}

private struct CommandLineOptions {
    var exportPDFPath: String?
    var exportPDFPageRange: String?
    var exportPDFDrawCropMarks = false
    var exportPDFDrawGridGuides = false
    var exportPNGDirectoryPath: String?
    var exportPNGPageRange: String?
    var exportPNGScale = 2.0
    var exportProjectPath: String?
    var exportTemplateLibraryPath: String?
    var importTemplateLibraryPath: String?
    var preflightReportPath: String?
    var validateOnly = false
    var applyPreflightFixes = false
    var chapterLayoutTemplate: ChapterLayoutTemplate?
    var chapterLayoutTemplateSectionIndex = 0
    var chapterLayoutTemplateStartPage = 3
    var showHelp = false
    var manuscriptPath: String?
    var assetDirectoryPath: String?
    var exportPackagePath: String?
    var pdfxVersion: PDFXVersion = .none

    init(arguments: [String]) {
        var positionalArguments: [String] = []
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--" {
                index += 1
                continue
            }

            if argument == "--validate" {
                validateOnly = true
                index += 1
                continue
            }

            if argument == "--apply-preflight-fixes" {
                applyPreflightFixes = true
                index += 1
                continue
            }

            if argument == "--apply-chapter-template", index + 1 < arguments.count {
                chapterLayoutTemplate = ChapterLayoutTemplate(rawValue: arguments[index + 1])
                index += 2
                continue
            }

            if argument == "--chapter-template-section", index + 1 < arguments.count {
                if let sectionNumber = Int(arguments[index + 1]) {
                    chapterLayoutTemplateSectionIndex = max(sectionNumber - 1, 0)
                }
                index += 2
                continue
            }

            if argument == "--chapter-template-start-page", index + 1 < arguments.count {
                if let startPage = Int(arguments[index + 1]) {
                    chapterLayoutTemplateStartPage = max(startPage, 1)
                }
                index += 2
                continue
            }

            if argument == "--help" || argument == "-h" {
                showHelp = true
                index += 1
                continue
            }

            if argument == "--export-pdf", index + 1 < arguments.count {
                exportPDFPath = arguments[index + 1]
                index += 2
                continue
            }

            if argument == "--pdf-pages", index + 1 < arguments.count {
                exportPDFPageRange = arguments[index + 1]
                index += 2
                continue
            }

            if argument == "--pdf-crop-marks" {
                exportPDFDrawCropMarks = true
                index += 1
                continue
            }

            if argument == "--pdf-grid-guides" {
                exportPDFDrawGridGuides = true
                index += 1
                continue
            }

            if argument == "--export-png", index + 1 < arguments.count {
                exportPNGDirectoryPath = arguments[index + 1]
                index += 2
                continue
            }

            if argument == "--png-pages", index + 1 < arguments.count {
                exportPNGPageRange = arguments[index + 1]
                index += 2
                continue
            }

            if argument == "--png-scale", index + 1 < arguments.count {
                if let scale = Double(arguments[index + 1]) {
                    exportPNGScale = scale
                }
                index += 2
                continue
            }

            if argument == "--export-project", index + 1 < arguments.count {
                exportProjectPath = arguments[index + 1]
                index += 2
                continue
            }

            if argument == "--export-templates", index + 1 < arguments.count {
                exportTemplateLibraryPath = arguments[index + 1]
                index += 2
                continue
            }

            if argument == "--import-templates", index + 1 < arguments.count {
                importTemplateLibraryPath = arguments[index + 1]
                index += 2
                continue
            }

            if argument == "--preflight-report", index + 1 < arguments.count {
                preflightReportPath = arguments[index + 1]
                index += 2
                continue
            }

            if argument == "--export-package", index + 1 < arguments.count {
                exportPackagePath = arguments[index + 1]
                index += 2
                continue
            }

            if argument == "--pdf-version", index + 1 < arguments.count {
                let val = arguments[index + 1].lowercased()
                if val == "pdfx1a" || val == "1a" {
                    pdfxVersion = .pdfx1a
                } else if val == "pdfx3" || val == "3" {
                    pdfxVersion = .pdfx3
                } else {
                    pdfxVersion = .none
                }
                index += 2
                continue
            }

            positionalArguments.append(argument)
            index += 1
        }

        manuscriptPath = positionalArguments.first
        assetDirectoryPath = positionalArguments.dropFirst().first
    }
}
