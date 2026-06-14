import Foundation
import LayoutDCore

public struct ProjectInspector {
    public init() {}

    public func inspect(project: BookProject) -> [LayoutIssue] {
        var issues: [LayoutIssue] = []
        issues.append(contentsOf: inspectStructure(project))
        issues.append(contentsOf: inspectAssets(project.assets))
        return issues
    }

    private func inspectStructure(_ project: BookProject) -> [LayoutIssue] {
        var issues: [LayoutIssue] = []
        if project.sections.isEmpty {
            issues.append(LayoutIssue(severity: .error, message: "项目没有章节"))
        }

        let storyCount = project.sections.flatMap(\.stories).count
        if storyCount == 0 {
            issues.append(LayoutIssue(severity: .error, message: "项目没有正文流"))
        }

        let paragraphCount = project.sections.flatMap(\.stories).flatMap(\.paragraphs).count
        if paragraphCount == 0 {
            issues.append(LayoutIssue(severity: .warning, message: "项目没有正文段落"))
        }

        return issues
    }

    private func inspectAssets(_ assets: [Asset]) -> [LayoutIssue] {
        var issues: [LayoutIssue] = []
        var fileNameCounts: [String: Int] = [:]

        for asset in assets {
            fileNameCounts[asset.fileName.normalizedAssetKey, default: 0] += 1

            if asset.caption?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                issues.append(
                    LayoutIssue(severity: .warning, message: "图片 \(asset.fileName) 缺少图注")
                )
            }

            if let dpi = asset.dpi, dpi < 220 {
                issues.append(
                    LayoutIssue(severity: .warning, message: "图片 \(asset.fileName) 分辨率低于 220 DPI")
                )
            }

            if let sourcePath = asset.sourcePath,
               !FileManager.default.fileExists(atPath: sourcePath) {
                issues.append(
                    LayoutIssue(severity: .warning, message: "图片 \(asset.fileName) 的源文件不存在")
                )
            }
        }

        for (fileName, count) in fileNameCounts where count > 1 {
            issues.append(
                LayoutIssue(severity: .warning, message: "图片文件名重复：\(fileName)")
            )
        }

        return issues
    }
}

private extension String {
    var normalizedAssetKey: String {
        URL(fileURLWithPath: self).lastPathComponent.lowercased()
    }
}
