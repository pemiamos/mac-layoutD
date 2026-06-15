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
                                HStack {
                                    if state.project.safeLockedPages.contains(page.number) {
                                        Image(systemName: "lock.fill")
                                            .foregroundColor(state.currentPageNumber == page.number ? .white : .secondary)
                                            .font(.system(size: 11))
                                    }
                                    
                                    Text("第 \(page.number) 页")
                                        .font(.body)
                                        .fontWeight(state.currentPageNumber == page.number ? .semibold : .regular)
                                        .foregroundColor(state.currentPageNumber == page.number ? .white : .primary)
                                    Spacer()
                                    Text("\(page.frames.count) 框")
                                        .font(.caption)
                                        .foregroundColor(state.currentPageNumber == page.number ? Color.white.opacity(0.8) : .secondary)
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
            }
            .listStyle(.sidebar)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}
