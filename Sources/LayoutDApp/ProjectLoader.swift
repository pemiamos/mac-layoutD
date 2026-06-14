import Foundation
import LayoutDCore
import LayoutDImport

struct LoadedProject {
    var project: BookProject
    var sourceDescription: String
    var exportPDFURL: URL?
}

struct ProjectLoader {
    func loadFromCommandLine(arguments: [String] = CommandLine.arguments) -> LoadedProject {
        let options = CommandLineOptions(arguments: Array(arguments.dropFirst()))
        guard let manuscriptPath = options.manuscriptPath else {
            return LoadedProject(
                project: .sample,
                sourceDescription: "内置样章",
                exportPDFURL: options.exportPDFPath.map { URL(fileURLWithPath: $0).standardizedFileURL }
            )
        }

        let manuscriptURL = URL(fileURLWithPath: manuscriptPath).standardizedFileURL
        do {
            let markdown = try String(contentsOf: manuscriptURL, encoding: .utf8)
            let assets = try loadAssets(assetPath: options.assetDirectoryPath, manuscriptURL: manuscriptURL)
            let project = MarkdownBookImporter(defaultAuthor: NSUserName()).importDocument(
                markdown: markdown,
                assetCatalog: AssetCatalog(assets: assets),
                fallbackTitle: manuscriptURL.deletingPathExtension().lastPathComponent
            )

            return LoadedProject(
                project: project,
                sourceDescription: "导入：\(manuscriptURL.lastPathComponent)",
                exportPDFURL: options.exportPDFPath.map { URL(fileURLWithPath: $0).standardizedFileURL }
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
                exportPDFURL: options.exportPDFPath.map { URL(fileURLWithPath: $0).standardizedFileURL }
            )
        }
    }

    private func loadAssets(assetPath: String?, manuscriptURL: URL) throws -> [Asset] {
        let scanner = AssetScanner()
        if let explicitAssetPath = assetPath {
            let assetURL = URL(fileURLWithPath: explicitAssetPath).standardizedFileURL
            return try scanner.scan(directory: assetURL)
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

            if argument == "--export-pdf", index + 1 < arguments.count {
                exportPDFPath = arguments[index + 1]
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
