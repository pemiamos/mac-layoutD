import Foundation
import LayoutDCore
import LayoutDImport

struct LoadedProject {
    var project: BookProject
    var sourceDescription: String
    var exportPDFURL: URL?
    var exportProjectURL: URL?
    var preflightReportURL: URL?
    var validateOnly: Bool
    var loadError: String?
}

struct ProjectLoader {
    func loadFromCommandLine(arguments: [String] = CommandLine.arguments) -> LoadedProject {
        let options = CommandLineOptions(arguments: Array(arguments.dropFirst()))
        guard let manuscriptPath = options.manuscriptPath else {
            return LoadedProject(
                project: .sample,
                sourceDescription: "内置样章",
                exportPDFURL: options.exportPDFPath.map { URL(fileURLWithPath: $0).standardizedFileURL },
                exportProjectURL: options.exportProjectPath.map { URL(fileURLWithPath: $0).standardizedFileURL },
                preflightReportURL: options.preflightReportPath.map { URL(fileURLWithPath: $0).standardizedFileURL },
                validateOnly: options.validateOnly,
                loadError: nil
            )
        }

        let manuscriptURL = URL(fileURLWithPath: manuscriptPath).standardizedFileURL
        do {
            let project = try loadProject(
                inputURL: manuscriptURL,
                assetDirectoryURL: options.assetDirectoryPath.map { URL(fileURLWithPath: $0).standardizedFileURL }
            )
            return LoadedProject(
                project: project,
                sourceDescription: sourceDescription(for: manuscriptURL),
                exportPDFURL: options.exportPDFPath.map { URL(fileURLWithPath: $0).standardizedFileURL },
                exportProjectURL: options.exportProjectPath.map { URL(fileURLWithPath: $0).standardizedFileURL },
                preflightReportURL: options.preflightReportPath.map { URL(fileURLWithPath: $0).standardizedFileURL },
                validateOnly: options.validateOnly,
                loadError: nil
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
                exportProjectURL: options.exportProjectPath.map { URL(fileURLWithPath: $0).standardizedFileURL },
                preflightReportURL: options.preflightReportPath.map { URL(fileURLWithPath: $0).standardizedFileURL },
                validateOnly: options.validateOnly,
                loadError: error.localizedDescription
            )
        }
    }

    func loadProject(inputURL: URL, assetDirectoryURL: URL? = nil) throws -> BookProject {
        switch inputURL.pathExtension.lowercased() {
        case "layoutd", "json":
            let data = try Data(contentsOf: inputURL)
            return try ProjectFile.decode(data)
        default:
            return try loadMarkdownProject(manuscriptURL: inputURL, assetDirectoryURL: assetDirectoryURL)
        }
    }

    func sourceDescription(for inputURL: URL) -> String {
        switch inputURL.pathExtension.lowercased() {
        case "layoutd", "json":
            return "项目：\(inputURL.lastPathComponent)"
        default:
            return "导入：\(inputURL.lastPathComponent)"
        }
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
}

private struct CommandLineOptions {
    var exportPDFPath: String?
    var exportProjectPath: String?
    var preflightReportPath: String?
    var validateOnly = false
    var manuscriptPath: String?
    var assetDirectoryPath: String?

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

            if argument == "--export-pdf", index + 1 < arguments.count {
                exportPDFPath = arguments[index + 1]
                index += 2
                continue
            }

            if argument == "--export-project", index + 1 < arguments.count {
                exportProjectPath = arguments[index + 1]
                index += 2
                continue
            }

            if argument == "--preflight-report", index + 1 < arguments.count {
                preflightReportPath = arguments[index + 1]
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
