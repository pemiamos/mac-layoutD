import Foundation
import LayoutDCore

public struct PreflightAutoFixResult: Codable, Equatable, Sendable {
    public var project: BookProject
    public var appliedFixes: [PreflightAutoFixKind]
    public var changedAssetIds: [UUID]

    public init(
        project: BookProject,
        appliedFixes: [PreflightAutoFixKind],
        changedAssetIds: [UUID] = []
    ) {
        self.project = project
        self.appliedFixes = appliedFixes
        self.changedAssetIds = changedAssetIds
    }
}

public struct PreflightAutoFixer {
    public init() {}

    public func applyAvailableFixes(
        to project: BookProject,
        issues: [LayoutIssue]
    ) -> PreflightAutoFixResult {
        let requestedFixes = Set(issues.compactMap(\.autoFixKind))
        return applyFixes(Array(requestedFixes), to: project)
    }

    public func applyFixes(
        _ fixes: [PreflightAutoFixKind],
        to project: BookProject
    ) -> PreflightAutoFixResult {
        var fixedProject = project
        var appliedFixes: [PreflightAutoFixKind] = []
        var changedAssetIds: Set<UUID> = []

        for fix in fixes.sorted(by: { $0.rawValue < $1.rawValue }) {
            switch fix {
            case .fillMissingPublisher:
                if fixedProject.metadata.publisher?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                    fixedProject.metadata.publisher = "待补充出版社"
                    appliedFixes.append(fix)
                }
            case .fillMissingKeywords:
                if fixedProject.metadata.keywords.isEmpty {
                    fixedProject.metadata.keywords = fallbackKeywords(from: fixedProject.metadata.title)
                    appliedFixes.append(fix)
                }
            case .removeInvalidISBN:
                if let isbn = fixedProject.metadata.isbn?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !isbn.isEmpty,
                   !isValidISBN13ForAutoFix(isbn) {
                    fixedProject.metadata.isbn = nil
                    appliedFixes.append(fix)
                }
            case .fillMissingAssetCaptions:
                var changed = false
                for index in fixedProject.assets.indices {
                    if fixedProject.assets[index].caption?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                        fixedProject.assets[index].caption = fallbackCaption(for: fixedProject.assets[index])
                        changedAssetIds.insert(fixedProject.assets[index].id)
                        changed = true
                    }
                }
                if changed {
                    appliedFixes.append(fix)
                }
            case .fillMissingAssetCredits:
                var changed = false
                for index in fixedProject.assets.indices where fixedProject.assets[index].role != .decorative {
                    if fixedProject.assets[index].credit?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                        fixedProject.assets[index].credit = "待补充来源"
                        changedAssetIds.insert(fixedProject.assets[index].id)
                        changed = true
                    }
                }
                if changed {
                    appliedFixes.append(fix)
                }
            case .clearMissingAssetSourcePaths:
                var changed = false
                for index in fixedProject.assets.indices {
                    guard let sourcePath = fixedProject.assets[index].sourcePath,
                          !FileManager.default.fileExists(atPath: sourcePath) else {
                        continue
                    }
                    fixedProject.assets[index].sourcePath = nil
                    changedAssetIds.insert(fixedProject.assets[index].id)
                    changed = true
                }
                if changed {
                    appliedFixes.append(fix)
                }
            }
        }

        if !appliedFixes.isEmpty {
            fixedProject.metadata.modifiedAt = Date()
        }

        return PreflightAutoFixResult(
            project: fixedProject,
            appliedFixes: appliedFixes,
            changedAssetIds: Array(changedAssetIds).sorted { $0.uuidString < $1.uuidString }
        )
    }

    private func fallbackKeywords(from title: String) -> [String] {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? ["待补充关键词"] : [trimmedTitle]
    }

    private func fallbackCaption(for asset: Asset) -> String {
        let stem = URL(fileURLWithPath: asset.fileName).deletingPathExtension().lastPathComponent
        let cleaned = stem
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "待补充图注" : cleaned
    }
}

private func isValidISBN13ForAutoFix(_ value: String) -> Bool {
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
