import Foundation
import SwiftUI
import LayoutDCore
import LayoutDEngine
import LayoutDImport
import LayoutDCheck

extension AppState {
    func updateParagraphStyle(
        id: String,
        fontSize: Double? = nil,
        lineHeight: Double? = nil,
        firstLineIndent: Double? = nil,
        spaceBefore: Double? = nil,
        spaceAfter: Double? = nil
    ) {
        commitState()
        var currentProject = project
        var styles = currentProject.styles.paragraphStyles
        if let idx = styles.firstIndex(where: { $0.id == id }) {
            var style = styles[idx]
            if let fSize = fontSize {
                style.fontSize = fSize
                style.fontSizeToken = nil
            }
            if let lHeight = lineHeight {
                style.lineHeight = lHeight
                style.lineHeightToken = nil
            }
            if let indent = firstLineIndent {
                style.firstLineIndent = indent
                style.firstLineIndentToken = nil
            }
            if let before = spaceBefore {
                style.spaceBefore = before
                style.spaceBeforeToken = nil
            }
            if let after = spaceAfter {
                style.spaceAfter = after
                style.spaceAfterToken = nil
            }
            styles[idx] = style
            currentProject.styles.paragraphStyles = styles
            self.project = currentProject
        }
    }

    func updateParagraphStyleCompositeFont(
        id: String,
        charClass: CompositeFontClass,
        fontName: String,
        sizeMultiplier: Double,
        baselineOffset: Double
    ) {
        commitState()
        var currentProject = project
        var styles = currentProject.styles.paragraphStyles
        if let idx = styles.firstIndex(where: { $0.id == id }) {
            var style = styles[idx]
            var cf = style.compositeFont ?? [:]
            cf[charClass] = CompositeFontMapping(
                fontName: fontName,
                sizeMultiplier: sizeMultiplier,
                baselineOffset: baselineOffset
            )
            style.compositeFont = cf
            styles[idx] = style
            currentProject.styles.paragraphStyles = styles
            self.project = currentProject
        }
    }

    func applyImportedTokens(_ importedTokens: DesignTokens, baselineGridCompensate: Double? = nil) {
        commitState()
        var currentProject = project
        let result = SpecPackImportResult(
            tokens: importedTokens,
            unsupportedFields: [],
            fontResolutions: []
        )
        currentProject.applySpecPack(result, baselineGridCompensate: baselineGridCompensate)
        self.project = currentProject
    }

    /// Apply a full spec-pack import result (fonts / role colors / decorations /
    /// trim), matching the CLI `--render-samples` apply path. Used by the GUI
    /// import sheet when the chosen file is a layoutD spec pack.
    func applySpecPackResult(_ result: SpecPackImportResult, baselineGridCompensate: Double? = nil) {
        commitState()
        var currentProject = project
        currentProject.applySpecPack(result, baselineGridCompensate: baselineGridCompensate)
        self.project = currentProject
    }

    func applyStyleTemplate(_ template: StyleTemplate) {
        commitState()
        var currentProject = project
        currentProject.styles = template.styleLibrary
        self.project = currentProject
    }

    func applyAvailablePreflightFixes() {
        commitState()
        guard let report else { return }
        let result = PreflightAutoFixer().applyAvailableFixes(
            to: project,
            issues: report.issues
        )
        guard !result.appliedFixes.isEmpty else { return }
        self.project = result.project
    }

    func applyPreflightFix(_ fix: PreflightAutoFixKind, targetingAssetId: UUID? = nil, targetingFrameId: UUID? = nil) {
        commitState()
        let result = PreflightAutoFixer().applyFixes(
            [fix],
            to: project,
            targetingAssetId: targetingAssetId,
            targetingFrameId: targetingFrameId
        )
        guard !result.appliedFixes.isEmpty else { return }
        self.project = result.project
    }

    func applyPreflightFixes(in category: PreflightIssueCategory) {
        commitState()
        guard let report else { return }
        let categoryIssues = report.issues.filter { $0.category == category }
        let result = PreflightAutoFixer().applyAvailableFixes(
            to: project,
            issues: categoryIssues
        )
        guard !result.appliedFixes.isEmpty else { return }
        self.project = result.project
    }
}
