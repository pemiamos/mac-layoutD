import SwiftUI
import LayoutDCore
import LayoutDCheck

extension InspectorView {
    // MARK: - Quality Metrics Helpers
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter
    }()

    func metricCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.all, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }

    func historyCard(entry: QualityHistoryEntry) -> some View {
        let hasErrors = entry.blockingErrors > 0
        let hasIssues = entry.layoutIssues > 0
        let statusColor: Color = hasErrors ? .red : (hasIssues ? .orange : .green)
        
        return VStack(alignment: .leading, spacing: 4) {
            Text(Self.dateFormatter.string(from: entry.timestamp))
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
            
            Divider()
                .padding(.vertical, 2)
            
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("📄 页: \(entry.pageCount)")
                    Text("🤖 AI: \(entry.planAppliedPages)/\(entry.pageCount)")
                    Text("🖼️ 帧: \(entry.totalFrames)")
                }
                .font(.system(size: 10))
                .foregroundColor(.primary)
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    if entry.blockingErrors > 0 {
                        Text("❌ 错: \(entry.blockingErrors)")
                            .foregroundColor(.red)
                    }
                    if entry.layoutIssues > 0 {
                        Text("⚠️ 问: \(entry.layoutIssues)")
                            .foregroundColor(.orange)
                    }
                    if entry.blockingErrors == 0 && entry.layoutIssues == 0 {
                        Text("✅ 正常")
                            .foregroundColor(.green)
                    }
                    Text("低DPI: \(entry.lowResolutionAssets)")
                        .foregroundColor(entry.lowResolutionAssets > 0 ? .orange : .secondary)
                }
                .font(.system(size: 10))
            }
        }
        .padding(.all, 8)
        .frame(width: 160)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(statusColor.opacity(0.3), lineWidth: 1)
        )
    }

    func qualityMetricsView(report: PreflightReport) -> some View {
        let metrics = report.qualityMetrics
        
        let columns = [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
        ]
        
        let aiAdoptionRate = metrics.pageCount > 0 ? (Double(metrics.planAppliedPages) / Double(metrics.pageCount)) * 100 : 0.0
        let aiAdoptionText = String(format: "%.0f%%", aiAdoptionRate)
        
        return VStack(alignment: .leading, spacing: 12) {
            Text("当前质量指标")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 4)
            
            LazyVGrid(columns: columns, spacing: 8) {
                metricCard(
                    title: "总页数 / 自动流排页",
                    value: "\(metrics.pageCount) 页 / \(metrics.autoLaidOutPages) 页",
                    icon: "doc.text.fill",
                    color: .blue
                )
                
                metricCard(
                    title: "AI 模板采纳率",
                    value: "\(aiAdoptionText) (\(metrics.planAppliedPages)/\(metrics.pageCount))",
                    icon: "wand.and.stars",
                    color: .purple
                )
                
                metricCard(
                    title: "阻断错误 / 布局问题",
                    value: "\(metrics.blockingErrors) 个 / \(metrics.layoutIssues) 个",
                    icon: "exclamationmark.triangle.fill",
                    color: (metrics.blockingErrors > 0) ? .red : ((metrics.layoutIssues > 0) ? .orange : .green)
                )
                
                metricCard(
                    title: "低 DPI / 缺图注素材",
                    value: "\(metrics.lowResolutionAssets) 个 / \(metrics.missingCaptionAssets) 个",
                    icon: "photo.fill.on.rectangle.fill",
                    color: (metrics.lowResolutionAssets > 0 || metrics.missingCaptionAssets > 0) ? .orange : .secondary
                )
                
                metricCard(
                    title: "总帧数 / 页均帧数",
                    value: "\(metrics.totalFrames) / \(String(format: "%.1f", metrics.averageFramesPerPage))",
                    icon: "square.dashed",
                    color: .teal
                )
            }
            
            let history = state.project.safeQualityMetricsHistory
            if !history.isEmpty {
                Divider()
                    .padding(.vertical, 4)
                
                HStack {
                    Text("历史趋势 (最新 \(history.count) 次)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("清除历史") {
                        state.updateProject { project in
                            project.qualityMetricsHistory = []
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .foregroundColor(.blue)
                }
                
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(spacing: 8) {
                        ForEach(history.reversed(), id: \.timestamp) { entry in
                            historyCard(entry: entry)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(.vertical, 8)
    }
}
