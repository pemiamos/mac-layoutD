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
            issues.append(LayoutIssue(
                severity: .info,
                message: "项目缺少出版社信息",
                category: .metadata,
                suggestedFix: "在图书元数据中填写 publisher，或在 Markdown front matter 增加 publisher。",
                autoFixKind: .fillMissingPublisher
            ))
        }

        if metadata.keywords.isEmpty {
            issues.append(LayoutIssue(
                severity: .info,
                message: "项目缺少关键词",
                category: .metadata,
                suggestedFix: "在图书元数据中填写 keywords，便于检索、分类和后续 AI 语义分析。",
                autoFixKind: .fillMissingKeywords
            ))
        }

        if let isbn = metadata.isbn?.trimmingCharacters(in: .whitespacesAndNewlines), !isbn.isEmpty {
            if !isValidISBN13(isbn) {
                issues.append(LayoutIssue(
                    severity: .warning,
                    message: "项目 ISBN-13 校验失败：\(isbn)",
                    category: .metadata,
                    suggestedFix: "核对 ISBN-13 的 13 位数字和校验位，或暂时移除无效 ISBN。",
                    autoFixKind: .removeInvalidISBN
                ))
            }
        }

        if metadata.author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(LayoutIssue(
                severity: .warning,
                message: "项目缺少作者信息",
                category: .metadata,
                suggestedFix: "在图书元数据中填写 author，或在 Markdown front matter 增加 author。",
                autoFixKind: .fillMissingAuthor
            ))
        }

        if metadata.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            issues.append(LayoutIssue(
                severity: .info,
                message: "项目缺少副标题",
                category: .metadata,
                suggestedFix: "在图书元数据中填写 subtitle，以丰富图书信息。",
                autoFixKind: .fillMissingSubtitle
            ))
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
            issues.append(LayoutIssue(
                severity: .error,
                message: "项目没有章节",
                category: .structure,
                suggestedFix: "导入包含至少一个一级标题的 Markdown，或在项目中新增章节。"
            ))
        }

        let storyCount = project.sections.flatMap(\.stories).count
        if storyCount == 0 {
            issues.append(LayoutIssue(
                severity: .error,
                message: "项目没有正文流",
                category: .structure,
                suggestedFix: "为章节添加正文故事流，或检查导入文件是否只有元数据没有正文。"
            ))
        }

        let paragraphCount = project.sections.flatMap(\.stories).flatMap(\.paragraphs).count
        if paragraphCount == 0 {
            issues.append(LayoutIssue(severity: .warning, message: "项目没有正文段落", category: .structure))
        }

        let duplicateSectionTitles = Dictionary(grouping: project.sections.map(\.title.normalizedTitle), by: { $0 })
            .filter { !$0.key.isEmpty && $0.value.count > 1 }
            .keys
        for title in duplicateSectionTitles.sorted() {
            issues.append(LayoutIssue(severity: .warning, message: "章节标题重复：\(title)", category: .structure))
        }

        return issues
    }

    private func inspectReferences(_ project: BookProject) -> [LayoutIssue] {
        let assetIds = Set(project.assets.map(\.id))
        var issues: [LayoutIssue] = []

        for paragraph in project.sections.flatMap(\.stories).flatMap(\.paragraphs) {
            if case .figure(let assetId) = paragraph.kind, !assetIds.contains(assetId) {
                issues.append(LayoutIssue(severity: .error, message: "段落引用了不存在的图片素材", category: .references))
            }

            for assetId in paragraph.anchoredAssetIds where !assetIds.contains(assetId) {
                issues.append(LayoutIssue(severity: .error, message: "段落锚定了不存在的图片素材", category: .references))
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
                    LayoutIssue(severity: .info, message: "图片 \(asset.fileName) 在素材库中但未被正文引用", category: .assets)
                )
            }

            if asset.usage == .repeated {
                issues.append(
                    LayoutIssue(severity: .warning, message: "图片 \(asset.fileName) 被重复使用", category: .assets)
                )
            }

            if asset.caption?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                issues.append(
                    LayoutIssue(
                        severity: .warning,
                        message: "图片 \(asset.fileName) 缺少图注",
                        category: .assets,
                        suggestedFix: "在 Markdown 图片 alt 文本或 assets.csv 的 caption 字段中补充图注。",
                        autoFixKind: .fillMissingAssetCaptions,
                        assetId: asset.id
                    )
                )
            }

            if asset.role != .decorative,
               asset.credit?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                issues.append(
                    LayoutIssue(
                        severity: .info,
                        message: "图片 \(asset.fileName) 缺少版权或来源信息",
                        category: .assets,
                        suggestedFix: "在图片标题参数或 manifest 的 credit/source 字段中记录来源。",
                        autoFixKind: .fillMissingAssetCredits,
                        assetId: asset.id
                    )
                )
            }

            if asset.pixelWidth <= 0 || asset.pixelHeight <= 0 {
                issues.append(
                    LayoutIssue(severity: .warning, message: "图片 \(asset.fileName) 缺少像素尺寸信息", category: .assets)
                )
            }

            if let effectiveDPI = asset.effectiveDPI(pageSetup: project.pageSetup), effectiveDPI < 220 {
                issues.append(
                    LayoutIssue(
                        severity: .warning,
                        message: "图片 \(asset.fileName) 预计印刷分辨率低于 220 DPI",
                        category: .assets,
                        suggestedFix: "替换为更高分辨率图片，或将图片角色改为较小版面宽度的配图。",
                        autoFixKind: .downgradeLowDPIAssetRoles,
                        assetId: asset.id
                    )
                )
            }

            // RGB vs CMYK color space check
            let (detectedModel, fileDPI) = asset.detectColorModelAndActualDPI()
            if let model = detectedModel, model == "RGB" {
                issues.append(
                    LayoutIssue(
                        severity: .warning,
                        message: "图片 \(asset.fileName) 的颜色空间为 RGB，印刷建议转换为 CMYK",
                        category: .assets,
                        suggestedFix: "在图像编辑器中将颜色模式转换为 CMYK 并在项目设置中更新图片。",
                        assetId: asset.id
                    )
                )
            }

            // Hero/Diagram/Spread DPI >= 300 check
            if asset.pixelWidth > 0, asset.role == .hero || asset.role == .diagram || asset.role == .spread {
                let checkDPI = fileDPI ?? asset.dpi ?? 0.0
                if checkDPI > 0 && checkDPI < 300 {
                    issues.append(
                        LayoutIssue(
                            severity: .warning,
                            message: "大图/图示图片 \(asset.fileName) 原始分辨率为 \(Int(checkDPI)) DPI，低于印刷标准的 300 DPI",
                            category: .assets,
                            suggestedFix: "替换为高清晰度图片以确保印刷质量。",
                            assetId: asset.id
                        )
                    )
                }

                if let effDPI = asset.effectiveDPI(pageSetup: project.pageSetup), effDPI < 300 {
                    issues.append(
                        LayoutIssue(
                            severity: .warning,
                            message: "大图/图示图片 \(asset.fileName) 在版面中的预计印刷分辨率低于 300 DPI (当前为 \(Int(effDPI)) DPI)",
                            category: .assets,
                            suggestedFix: "替换为更高分辨率图片，或将图片角色改为较小版面宽度的配图。",
                            assetId: asset.id
                        )
                    )
                }
            }

            if let sourcePath = asset.sourcePath,
               !FileManager.default.fileExists(atPath: sourcePath) {
                issues.append(
                    LayoutIssue(
                        severity: .warning,
                        message: "图片 \(asset.fileName) 的源文件不存在",
                        category: .assets,
                        suggestedFix: "重新选择图片文件，或清除失效 sourcePath 以避免导出时继续查找不存在的文件。",
                        autoFixKind: .clearMissingAssetSourcePaths,
                        assetId: asset.id
                    )
                )
            }
        }

        for (fileName, count) in fileNameCounts where count > 1 {
            issues.append(
                LayoutIssue(severity: .warning, message: "图片文件名重复：\(fileName)", category: .assets)
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
