import SwiftUI
import LayoutDCore

extension InspectorView {
    // Sub-view: Asset Edit Row
    func assetRow(index: Int) -> some View {
        let asset = state.project.assets[index]
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(asset.fileName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text(assetDetailLabel(asset))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(assetUsageLabel(asset.usage))
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(assetUsageColor(asset.usage).opacity(0.15))
                    .foregroundColor(assetUsageColor(asset.usage))
                    .cornerRadius(4)
            }

            Picker("角色", selection: Binding(
                get: { state.project.assets[index].role },
                set: { value in
                    state.updateProject { project in
                        guard project.assets.indices.contains(index) else { return }
                        project.assets[index].role = value
                    }
                }
            )) {
                ForEach(AssetRole.allCases, id: \.self) { role in
                    Text(assetRoleLabel(role)).tag(role)
                }
            }

            TextField("图注", text: Binding(
                get: { state.project.assets[index].caption ?? "" },
                set: { value in
                    state.updateProject { project in
                        guard project.assets.indices.contains(index) else { return }
                        project.assets[index].caption = value.isEmpty ? nil : value
                    }
                }
            ))

            TextField("版权或来源", text: Binding(
                get: { state.project.assets[index].credit ?? "" },
                set: { value in
                    state.updateProject { project in
                        guard project.assets.indices.contains(index) else { return }
                        project.assets[index].credit = value.isEmpty ? nil : value
                    }
                }
            ))
        }
        .textFieldStyle(.roundedBorder)
        .padding(.all, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        .cornerRadius(6)
    }

    func assetDetailLabel(_ asset: Asset) -> String {
        let size = asset.pixelWidth > 0 && asset.pixelHeight > 0
            ? "\(asset.pixelWidth)x\(asset.pixelHeight)"
            : "尺寸未知"
        let dpi = asset.dpi.map { "\(Int($0)) DPI" } ?? "DPI ?"
        return "\(size) · \(dpi)"
    }

    func assetUsageLabel(_ usage: AssetUsage) -> String {
        switch usage {
        case .unused:
            return "未用"
        case .placed:
            return "已用"
        case .repeated:
            return "重复"
        }
    }

    func assetUsageColor(_ usage: AssetUsage) -> Color {
        switch usage {
        case .unused:
            return .secondary
        case .placed:
            return Color(nsColor: NSColor(calibratedRed: 0.18, green: 0.48, blue: 0.46, alpha: 1))
        case .repeated:
            return .orange
        }
    }

    func assetRoleLabel(_ role: AssetRole) -> String {
        switch role {
        case .hero:
            return "章节主图"
        case .diagram:
            return "示意图"
        case .photo:
            return "照片"
        case .chart:
            return "图表"
        case .step:
            return "步骤图"
        case .comparison:
            return "对比图"
        case .decorative:
            return "装饰图"
        case .spread:
            return "跨页图"
        }
    }

    func parseKeywords(_ text: String) -> [String] {
        text
            .split(whereSeparator: { $0 == "," || $0 == "，" })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func pointsToMillimeters(_ points: Double) -> Double {
        points / 72 * 25.4
    }

    func millimetersToPoints(_ millimeters: Double) -> Double {
        millimeters / 25.4 * 72
    }
}
