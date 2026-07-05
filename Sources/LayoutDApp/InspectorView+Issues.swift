import SwiftUI
import LayoutDCheck
import LayoutDCore

extension InspectorView {
    // Sub-view: Preflight Header
    func preflightHeader(report: PreflightReport) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("项目状态")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(report.isExportReady ? "可安全导出 PDF" : "存在错误需修复")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(report.isExportReady ? .green : .red)
            }
            Spacer()
            Image(systemName: report.isExportReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(report.isExportReady ? .green : .red)
                .font(.system(size: 28))
        }
        .padding(.horizontal, 4)
    }

    func filteredIssues(_ report: PreflightReport) -> [LayoutIssue] {
        report.issues.filter {
            issueFilter.matches($0.severity) && issueCategoryFilter.matches($0.category)
        }
    }

    func issueLocation(for issue: LayoutIssue, report: PreflightReport) -> IssueLocation? {
        report.issueLocations.first { $0.issueId == issue.id }
    }

    func categoryTitle(_ category: PreflightIssueCategory) -> String {
        switch category {
        case .metadata:
            return "元数据"
        case .structure:
            return "结构"
        case .references:
            return "引用"
        case .assets:
            return "素材"
        case .pagination:
            return "页码"
        case .layout:
            return "版面"
        case .typography:
            return "排印"
        case .tableOfContents:
            return "目录"
        case .prepress:
            return "印前"
        }
    }

    func locationLabel(_ location: IssueLocation) -> String {
        String(
            format: "%@ frame · x %.0f y %.0f w %.0f h %.0f",
            location.frameKind,
            location.rect.x,
            location.rect.y,
            location.rect.width,
            location.rect.height
        )
    }

    // Sub-view: Issue Icon
    func issueIcon(_ severity: IssueSeverity) -> some View {
        let color: Color
        let name: String
        switch severity {
        case .error:
            color = .red
            name = "xmark.circle.fill"
        case .warning:
            color = .orange
            name = "exclamationmark.triangle.fill"
        case .info:
            color = .blue
            name = "info.circle.fill"
        }
        return Image(systemName: name)
            .foregroundColor(color)
            .font(.system(size: 14))
    }
}
