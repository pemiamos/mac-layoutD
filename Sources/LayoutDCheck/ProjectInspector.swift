import Foundation
import LayoutDCore

public struct ProjectInspector {
    public init() {}

    public func inspect(project: BookProject) -> [LayoutIssue] {
        var issues: [LayoutIssue] = []
        issues.append(contentsOf: inspectMetadata(project.metadata))
        issues.append(contentsOf: inspectStructure(project))
        issues.append(contentsOf: inspectReferences(project))
        issues.append(contentsOf: inspectAssets(project))
        return issues
    }

    private func inspectMetadata(_ metadata: ProjectMetadata) -> [LayoutIssue] {
        var issues: [LayoutIssue] = []

        if metadata.publisher?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            issues.append(LayoutIssue(severity: .info, message: "项目缺少出版社信息"))
        }

        if metadata.keywords.isEmpty {
            issues.append(LayoutIssue(severity: .info, message: "项目缺少关键词"))
        }

        if let isbn = metadata.isbn?.trimmingCharacters(in: .whitespacesAndNewlines), !isbn.isEmpty {
            if !isValidISBN13(isbn) {
                issues.append(LayoutIssue(severity: .warning, message: "项目 ISBN-13 校验失败：\(isbn)"))
            }
        }

        return issues
    }

    public func preflight(project: BookProject, document: LaidOutDocument? = nil) -> PreflightReport {
        let documentIssues = document.map {
            $0.issues + LayoutDocumentValidator().validate(document: $0, project: project)
        } ?? []
        let issues = deduplicatedIssues(inspect(project: project) + documentIssues)
        return PreflightReport(project: project, issues: issues, document: document)
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

        let duplicateSectionTitles = Dictionary(grouping: project.sections.map(\.title.normalizedTitle), by: { $0 })
            .filter { !$0.key.isEmpty && $0.value.count > 1 }
            .keys
        for title in duplicateSectionTitles.sorted() {
            issues.append(LayoutIssue(severity: .warning, message: "章节标题重复：\(title)"))
        }

        return issues
    }

    private func inspectReferences(_ project: BookProject) -> [LayoutIssue] {
        let assetIds = Set(project.assets.map(\.id))
        var issues: [LayoutIssue] = []

        for paragraph in project.sections.flatMap(\.stories).flatMap(\.paragraphs) {
            if case .figure(let assetId) = paragraph.kind, !assetIds.contains(assetId) {
                issues.append(LayoutIssue(severity: .error, message: "段落引用了不存在的图片素材"))
            }

            for assetId in paragraph.anchoredAssetIds where !assetIds.contains(assetId) {
                issues.append(LayoutIssue(severity: .error, message: "段落锚定了不存在的图片素材"))
            }
        }

        return issues
    }

    private func inspectAssets(_ project: BookProject) -> [LayoutIssue] {
        var issues: [LayoutIssue] = []
        var fileNameCounts: [String: Int] = [:]
        let referencedAssetIds = referencedAssetIds(in: project)

        for asset in project.assets {
            fileNameCounts[asset.fileName.normalizedAssetKey, default: 0] += 1

            if !referencedAssetIds.contains(asset.id) {
                issues.append(
                    LayoutIssue(severity: .info, message: "图片 \(asset.fileName) 在素材库中但未被正文引用")
                )
            }

            if asset.caption?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                issues.append(
                    LayoutIssue(severity: .warning, message: "图片 \(asset.fileName) 缺少图注")
                )
            }

            if asset.role != .decorative,
               asset.credit?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                issues.append(
                    LayoutIssue(severity: .info, message: "图片 \(asset.fileName) 缺少版权或来源信息")
                )
            }

            if asset.pixelWidth <= 0 || asset.pixelHeight <= 0 {
                issues.append(
                    LayoutIssue(severity: .warning, message: "图片 \(asset.fileName) 缺少像素尺寸信息")
                )
            }

            if let effectiveDPI = asset.effectiveDPI(pageSetup: project.pageSetup), effectiveDPI < 220 {
                issues.append(
                    LayoutIssue(severity: .warning, message: "图片 \(asset.fileName) 预计印刷分辨率低于 220 DPI")
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

    private func referencedAssetIds(in project: BookProject) -> Set<UUID> {
        project.sections
            .flatMap(\.stories)
            .flatMap(\.paragraphs)
            .reduce(into: Set<UUID>()) { result, paragraph in
                if case .figure(let assetId) = paragraph.kind {
                    result.insert(assetId)
                }
                result.formUnion(paragraph.anchoredAssetIds)
            }
    }

    private func deduplicatedIssues(_ issues: [LayoutIssue]) -> [LayoutIssue] {
        issues.reduce(into: [LayoutIssue]()) { result, issue in
            if let index = result.firstIndex(where: {
                $0.severity == issue.severity && $0.message == issue.message
            }) {
                if result[index].pageNumber == nil, issue.pageNumber != nil {
                    result[index] = issue
                }
                return
            }

            result.append(issue)
        }
    }
}

private func isValidISBN13(_ value: String) -> Bool {
    guard value.allSatisfy({ $0.isNumber || $0 == "-" || $0 == " " }) else {
        return false
    }

    let digits = value.compactMap(\.wholeNumberValue)
    guard digits.count == 13 else {
        return false
    }

    let sum = digits.prefix(12).enumerated().reduce(0) { partial, item in
        partial + item.element * (item.offset.isMultiple(of: 2) ? 1 : 3)
    }
    let checkDigit = (10 - sum % 10) % 10
    return checkDigit == digits[12]
}

private extension String {
    var normalizedAssetKey: String {
        URL(fileURLWithPath: self).lastPathComponent.lowercased()
    }

    var normalizedTitle: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
