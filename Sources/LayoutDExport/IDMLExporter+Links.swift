import CoreText
import Foundation
import LayoutDCore

extension IDMLExporter {
    struct PackagedLink {
        let sourceURL: URL
        let fileName: String
    }

    /// 只打包实际置入页面且源文件存在的素材。同一素材重复置入时复用链接；不同素材
    /// basename 冲突时保留扩展名并追加序号（figure.png、figure-2.png）。
    func packagedLinks(for pages: [LaidOutPage], assets: [Asset]) -> [UUID: PackagedLink] {
        let assetsById = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
        var result: [UUID: PackagedLink] = [:]
        var usedNames: Set<String> = []

        for page in pages {
            for frame in page.frames {
                let assetId: UUID
                switch frame.content {
                case .asset(let id), .spreadAsset(let id, _): assetId = id
                case .text, .empty: continue
                }
                guard result[assetId] == nil,
                      let asset = assetsById[assetId],
                      let sourcePath = asset.sourcePath,
                      !sourcePath.isEmpty else { continue }

                let sourceURL = URL(fileURLWithPath: sourcePath, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
                    .standardizedFileURL
                guard FileManager.default.fileExists(atPath: sourceURL.path) else { continue }

                let requestedName = URL(fileURLWithPath: asset.fileName).lastPathComponent
                let baseName = requestedName.isEmpty ? sourceURL.lastPathComponent : requestedName
                let uniqueName = uniqueLinkName(baseName, usedNames: &usedNames)
                result[assetId] = PackagedLink(sourceURL: sourceURL, fileName: uniqueName)
            }
        }
        return result
    }

    func uniqueLinkName(_ fileName: String, usedNames: inout Set<String>) -> String {
        if usedNames.insert(fileName).inserted { return fileName }
        let url = URL(fileURLWithPath: fileName)
        let ext = url.pathExtension
        let stem = url.deletingPathExtension().lastPathComponent
        var sequence = 2
        while true {
            let candidate = ext.isEmpty ? "\(stem)-\(sequence)" : "\(stem)-\(sequence).\(ext)"
            if usedNames.insert(candidate).inserted { return candidate }
            sequence += 1
        }
    }

    func copyPackagedLinks(_ links: Dictionary<UUID, PackagedLink>.Values, beside outputURL: URL) throws {
        guard !links.isEmpty else { return }
        let fm = FileManager.default
        let linksDirectory = outputURL.deletingLastPathComponent().appendingPathComponent("Links", isDirectory: true)
        try fm.createDirectory(at: linksDirectory, withIntermediateDirectories: true)
        for link in links {
            let destination = linksDirectory.appendingPathComponent(link.fileName)
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.copyItem(at: link.sourceURL, to: destination)
        }
    }

}
