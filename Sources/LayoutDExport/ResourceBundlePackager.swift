import Foundation
import LayoutDCore
import LayoutDEngine

public enum PackagingError: Error, LocalizedError {
    case missingAssets([String])
    case emptyProject(String)
    case zipFailed(String)
    case tempDirCreationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingAssets(let paths):
            return "缺少以下引用的素材文件：\n" + paths.joined(separator: "\n")
        case .emptyProject(let reason):
            return "无法打包空项目：\(reason)"
        case .zipFailed(let reason):
            return "压缩项目包失败：\(reason)"
        case .tempDirCreationFailed(let reason):
            return "无法创建临时打包目录：\(reason)"
        }
    }
}

public struct ResourceBundlePackager {
    public init() {}

    public func validate(project: BookProject) throws {
        if project.metadata.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw PackagingError.emptyProject("项目标题不能为空")
        }
        if project.sections.isEmpty {
            throw PackagingError.emptyProject("项目必须至少包含一个章节")
        }

        var missingPaths: [String] = []
        for asset in project.assets {
            guard let sourcePath = asset.sourcePath else {
                missingPaths.append("\(asset.fileName) (未知源路径)")
                continue
            }
            if !FileManager.default.fileExists(atPath: sourcePath) {
                missingPaths.append("\(asset.fileName) (\(sourcePath))")
            }
        }

        if !missingPaths.isEmpty {
            throw PackagingError.missingAssets(missingPaths)
        }
    }

    public func package(project: BookProject, to destinationURL: URL) throws {
        // 1. Validate the project
        try validate(project: project)

        let fileManager = FileManager.default

        // 2. Create a temporary folder
        let tempDirURL = fileManager.temporaryDirectory
            .appendingPathComponent("layoutd-packager-\(UUID().uuidString)")
        do {
            try fileManager.createDirectory(at: tempDirURL, withIntermediateDirectories: true)
        } catch {
            throw PackagingError.tempDirCreationFailed(error.localizedDescription)
        }

        defer {
            try? fileManager.removeItem(at: tempDirURL)
        }

        // 3. Create assets/ directory in temp folder
        let assetsDirURL = tempDirURL.appendingPathComponent("assets")
        try fileManager.createDirectory(at: assetsDirURL, withIntermediateDirectories: true)

        // 4. Copy referenced assets and rewrite their paths to relative "assets/filename"
        var updatedProject = project
        var updatedAssets: [Asset] = []

        for asset in project.assets {
            guard let sourcePath = asset.sourcePath else { continue }
            let sourceURL = URL(fileURLWithPath: sourcePath)
            let destURL = assetsDirURL.appendingPathComponent(asset.fileName)
            try fileManager.createDirectory(
                at: destURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            
            // Delete existing file in temp asset folder just in case
            if fileManager.fileExists(atPath: destURL.path) {
                try? fileManager.removeItem(at: destURL)
            }
            
            try fileManager.copyItem(at: sourceURL, to: destURL)

            var updatedAsset = asset
            updatedAsset.sourcePath = "assets/\(asset.fileName)"
            updatedAssets.append(updatedAsset)
        }
        updatedProject.assets = updatedAssets

        // 5. Serialize the updated project to project.layoutd
        let projectData = try ProjectFile.encode(updatedProject)
        let projectFileURL = tempDirURL.appendingPathComponent("project.layoutd")
        try projectData.write(to: projectFileURL, options: .atomic)

        // 6. Layout document to get the correct page count for manifest
        let document = LayoutEngine().layout(project: project)
        let pageCount = document.pages.count

        // 7. Write manifest.json
        let manifest = DistributionManifest(
            projectId: project.id,
            title: project.metadata.title,
            author: project.metadata.author,
            publisher: project.metadata.publisher,
            isbn: project.metadata.isbn,
            pageCount: pageCount,
            sectionCount: project.sections.count,
            assetCount: updatedAssets.count,
            createdAt: project.metadata.createdAt,
            modifiedAt: project.metadata.modifiedAt,
            assets: updatedAssets.map { asset in
                DistributionAssetMetadata(
                    id: asset.id,
                    fileName: asset.fileName,
                    role: asset.role.rawValue,
                    pixelWidth: asset.pixelWidth,
                    pixelHeight: asset.pixelHeight,
                    dpi: asset.dpi
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let manifestData = try encoder.encode(manifest)
        let manifestURL = tempDirURL.appendingPathComponent("manifest.json")
        try manifestData.write(to: manifestURL, options: .atomic)

        // 8. Delete destination ZIP if it exists
        if fileManager.fileExists(atPath: destinationURL.path) {
            try? fileManager.removeItem(at: destinationURL)
        } else {
            // Ensure parent directory exists
            try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        }

        // 9. Run the zip command-line tool
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-q", "-r", destinationURL.path, "."]
        process.currentDirectoryURL = tempDirURL

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw PackagingError.zipFailed("无法执行 zip 命令：\(error.localizedDescription)")
        }

        if process.terminationStatus != 0 {
            throw PackagingError.zipFailed("zip 命令执行失败，状态码：\(process.terminationStatus)")
        }
    }
}

public struct DistributionManifest: Codable, Equatable, Sendable {
    public var manifestVersion: String = "1.0"
    public var projectId: UUID
    public var title: String
    public var author: String
    public var publisher: String?
    public var isbn: String?
    public var pageCount: Int
    public var sectionCount: Int
    public var assetCount: Int
    public var createdAt: Date
    public var modifiedAt: Date
    public var assets: [DistributionAssetMetadata]
}

public struct DistributionAssetMetadata: Codable, Equatable, Sendable {
    public var id: UUID
    public var fileName: String
    public var role: String
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var dpi: Double?
}
