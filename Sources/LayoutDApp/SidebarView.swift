import SwiftUI
import LayoutDCore

struct SidebarView: View {
    @ObservedObject var state: AppState
    var onPageClick: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header Info
            VStack(alignment: .leading, spacing: 6) {
                Text(state.project.metadata.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                
                if let subtitle = state.project.metadata.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Text(state.project.pageSetup.pageSize.label)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(4)
                    .foregroundColor(.secondary)
            }
            .padding(.all, 16)
            
            Divider()
            
            // Sidebar Lists
            List {
                Section(header: Text("章节").font(.caption).foregroundColor(.secondary)) {
                    ForEach(state.project.sections) { section in
                        HStack(spacing: 8) {
                            Image(systemName: "bookmark.fill")
                                .foregroundColor(Color(nsColor: NSColor(calibratedRed: 0.18, green: 0.48, blue: 0.46, alpha: 1)))
                                .font(.system(size: 11))
                            Text(section.title)
                                .font(.body)
                                .lineLimit(1)
                        }
                    }
                }
                
                Section(header: Text("页面 (\(state.laidOutDocument?.pages.count ?? 0) 页)").font(.caption).foregroundColor(.secondary)) {
                    if let pages = state.laidOutDocument?.pages {
                        ForEach(pages, id: \.id) { page in
                            Button(action: {
                                state.currentPageNumber = page.number
                                onPageClick(page.number)
                            }) {
                                HStack(alignment: .top, spacing: 10) {
                                    pageThumbnail(page)

                                    VStack(alignment: .leading, spacing: 5) {
                                        HStack(spacing: 5) {
                                            if state.project.safeLockedPages.contains(page.number) {
                                                Image(systemName: "lock.fill")
                                                    .foregroundColor(state.currentPageNumber == page.number ? .white : .secondary)
                                                    .font(.system(size: 11))
                                            }

                                            Text("第 \(page.number) 页")
                                                .font(.body)
                                                .fontWeight(state.currentPageNumber == page.number ? .semibold : .regular)
                                                .foregroundColor(state.currentPageNumber == page.number ? .white : .primary)
                                        }

                                        Text(pageSummary(page))
                                            .font(.caption)
                                            .foregroundColor(state.currentPageNumber == page.number ? Color.white.opacity(0.85) : .secondary)
                                            .lineLimit(1)
                                    }

                                    Spacer()
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .background(
                                state.currentPageNumber == page.number
                                ? Color(nsColor: NSColor(calibratedRed: 0.18, green: 0.48, blue: 0.46, alpha: 1))
                                : Color.clear
                            )
                            .cornerRadius(6)
                            .contextMenu {
                                if state.project.safeLockedPages.contains(page.number) {
                                    Button("解锁页面版式") {
                                        state.unlockPage(number: page.number)
                                    }
                                } else {
                                    Button("锁定页面版式") {
                                        state.lockPage(number: page.number)
                                    }
                                }
                                Divider()
                                Button("清除自定义布局") {
                                    state.clearCustomLayoutForPage(number: page.number)
                                }
                            }
                        }
                    } else {
                        Text("无可用页面")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text("素材 (\(state.project.assets.count) 张)").font(.caption).foregroundColor(.secondary)) {
                    if state.project.assets.isEmpty {
                        Text("无素材")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(state.project.assets) { asset in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 8) {
                                    Image(systemName: iconName(for: asset.role))
                                        .foregroundColor(color(for: asset.usage))
                                        .font(.system(size: 12))
                                        .frame(width: 14)

                                    Text(asset.fileName)
                                        .font(.body)
                                        .lineLimit(1)

                                    Spacer()

                                    Text(label(for: asset.usage))
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(color(for: asset.usage).opacity(0.15))
                                        .foregroundColor(color(for: asset.usage))
                                        .cornerRadius(4)
                                }

                                HStack(spacing: 6) {
                                    Text(asset.role.rawValue)
                                    Text(sizeLabel(for: asset))
                                    if let dpi = asset.dpi {
                                        Text("\(Int(dpi)) DPI")
                                    } else {
                                        Text("DPI ?")
                                    }
                                }
                                .font(.caption2)
                                .foregroundColor(.secondary)

                                if let caption = asset.caption, !caption.isEmpty {
                                    Text(caption)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func label(for usage: AssetUsage) -> String {
        switch usage {
        case .unused:
            return "未用"
        case .placed:
            return "已用"
        case .repeated:
            return "重复"
        }
    }

    private func color(for usage: AssetUsage) -> Color {
        switch usage {
        case .unused:
            return .secondary
        case .placed:
            return Color(nsColor: NSColor(calibratedRed: 0.18, green: 0.48, blue: 0.46, alpha: 1))
        case .repeated:
            return .orange
        }
    }

    private func pageThumbnail(_ page: LaidOutPage) -> some View {
        let setup = state.project.pageSetup
        let pageWidth = setup.pageSize.width
        let pageHeight = setup.pageSize.height
        let thumbWidth: CGFloat = 42
        let thumbHeight = thumbWidth * CGFloat(pageHeight / pageWidth)

        return ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 0.8)
                )

            ForEach(page.frames.prefix(18)) { frame in
                frameThumbnail(frame, pageWidth: pageWidth, pageHeight: pageHeight)
            }
        }
        .frame(width: thumbWidth, height: thumbHeight)
        .shadow(color: .black.opacity(0.08), radius: 1, x: 0, y: 1)
    }

    private func frameThumbnail(_ frame: PageFrame, pageWidth: Double, pageHeight: Double) -> some View {
        let color: Color
        switch frame.kind {
        case .image:
            color = Color(nsColor: NSColor(calibratedRed: 0.18, green: 0.48, blue: 0.46, alpha: 1))
        case .callout:
            color = .orange
        case .table:
            color = .purple
        case .caption:
            color = .secondary.opacity(0.55)
        case .text:
            color = .primary.opacity(0.35)
        }

        return GeometryReader { proxy in
            let x = CGFloat(frame.rect.x / pageWidth) * proxy.size.width
            let y = CGFloat(frame.rect.y / pageHeight) * proxy.size.height
            let width = max(CGFloat(frame.rect.width / pageWidth) * proxy.size.width, 1.5)
            let height = max(CGFloat(frame.rect.height / pageHeight) * proxy.size.height, 1.5)

            RoundedRectangle(cornerRadius: 1)
                .fill(color.opacity(frame.kind == .image ? 0.45 : 0.32))
                .frame(width: width, height: height)
                .position(x: x + width / 2, y: y + height / 2)
        }
    }

    private func pageSummary(_ page: LaidOutPage) -> String {
        let imageCount = page.frames.filter { $0.kind == .image }.count
        let textCount = page.frames.filter { $0.kind == .text }.count
        let componentCount = page.frames.filter { $0.kind == .callout || $0.kind == .table }.count
        return "\(page.frames.count) 框 · \(textCount) 文 · \(imageCount) 图 · \(componentCount) 组件"
    }

    private func iconName(for role: AssetRole) -> String {
        switch role {
        case .hero:
            return "photo.fill"
        case .diagram:
            return "square.grid.2x2"
        case .photo:
            return "camera.fill"
        case .chart:
            return "chart.bar.fill"
        case .step:
            return "list.number"
        case .comparison:
            return "rectangle.split.2x1.fill"
        case .decorative:
            return "sparkles"
        case .spread:
            return "photo.on.rectangle"
        }
    }

    private func sizeLabel(for asset: Asset) -> String {
        guard asset.pixelWidth > 0, asset.pixelHeight > 0 else {
            return "尺寸未知"
        }
        return "\(asset.pixelWidth)x\(asset.pixelHeight)"
    }
}
