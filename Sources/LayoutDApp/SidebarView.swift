import SwiftUI
import LayoutDCore

enum SidebarTab: String, CaseIterable, Identifiable, Sendable {
    case properties = "属性"
    case pages = "页面"
    case layers = "图层"
    case assets = "链接"
    case swatches = "色板"
    
    var id: String { self.rawValue }
}

struct PageSpread: Identifiable, Sendable {
    let id = UUID()
    let leftPage: LaidOutPage?
    let rightPage: LaidOutPage?
    
    var numberLabel: String {
        if let left = leftPage, let right = rightPage {
            return "\(left.number)-\(right.number)"
        } else if let left = leftPage {
            return "\(left.number)"
        } else if let right = rightPage {
            return "\(right.number)"
        }
        return ""
    }
}

struct SwatchItem: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let color: Color?
}

struct SidebarView: View {
    @ObservedObject var state: AppState
    var onPageClick: (Int) -> Void
    
    @State private var selectedTab: SidebarTab = .pages

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header Info & Tab Bar (custom buttons layout)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(state.project.metadata.title)
                            .font(.headline)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        Text(state.project.pageSetup.pageSize.label)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                
                HStack(spacing: 0) {
                    ForEach(SidebarTab.allCases) { tab in
                        Button(action: {
                            selectedTab = tab
                        }) {
                            Text(tab.rawValue)
                                .font(.system(size: 11, weight: selectedTab == tab ? .bold : .regular))
                                .foregroundColor(selectedTab == tab ? Color.accentColor : .secondary)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity)
                                .background(selectedTab == tab ? Color(NSColor.selectedControlColor).opacity(0.12) : Color.clear)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                .padding(.horizontal, 10)
            }
            .padding(.bottom, 10)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Tab Contents
            switch selectedTab {
            case .properties:
                propertiesTabContent
            case .pages:
                pagesTabContent
            case .layers:
                layersTabContent
            case .assets:
                assetsTabContent
            case .swatches:
                swatchesTabContent
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Properties Tab
    
    private var propertiesTabContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("项目属性")
                    .font(.headline)
                    .padding(.bottom, 2)
                
                VStack(alignment: .leading, spacing: 6) {
                    infoRow(label: "书稿名称", value: state.project.metadata.title)
                    infoRow(label: "主编作者", value: state.project.metadata.author)
                    if let publisher = state.project.metadata.publisher {
                        infoRow(label: "出版社", value: publisher)
                    }
                    if let isbn = state.project.metadata.isbn {
                        infoRow(label: "ISBN", value: isbn)
                    }
                }
                
                Divider()
                
                Text("版心网格属性")
                    .font(.headline)
                    .padding(.bottom, 2)
                
                VStack(alignment: .leading, spacing: 6) {
                    infoRow(label: "开本规格", value: state.project.pageSetup.pageSize.label)
                    infoRow(label: "双页对开", value: state.project.pageSetup.facingPages ? "启用" : "禁用")
                    infoRow(label: "栏数设置", value: "\(state.project.pageSetup.columns) 栏")
                    infoRow(label: "天头地脚 (页边距)", value: "\(state.project.pageSetup.margins.top) / \(state.project.pageSetup.margins.bottom) pt")
                    infoRow(label: "内侧外侧 (页边距)", value: "\(state.project.pageSetup.margins.left) / \(state.project.pageSetup.margins.right) pt")
                    infoRow(label: "印刷出血", value: "\(state.project.pageSetup.bleedMM ?? 3.0) mm")
                }
            }
            .padding(.all, 12)
        }
    }
    
    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
                .font(.caption)
            Spacer()
            Text(value)
                .foregroundColor(.primary)
                .font(.caption)
                .fontWeight(.semibold)
        }
    }
    
    // MARK: - Pages Tab
    
    private var pagesTabContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Master Pages section
            VStack(alignment: .leading, spacing: 4) {
                Text("主页")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fontWeight(.medium)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                
                HStack(spacing: 10) {
                    // None Master
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                            .background(Color.white)
                            .frame(width: 30, height: 40)
                        Text("[无]")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, 12)
                    
                    // Default Master
                    VStack(spacing: 4) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                                .background(Color(nsColor: NSColor(calibratedRed: 0.18, green: 0.48, blue: 0.46, alpha: 0.1)))
                                .frame(width: 30, height: 40)
                            Text("A")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.primary)
                        }
                        Text("A-主页")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    
                    // Saved templates
                    ForEach(state.project.safeSavedLayoutTemplates.prefix(3)) { template in
                        VStack(spacing: 4) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                                    .background(Color(nsColor: NSColor(calibratedRed: 0.18, green: 0.48, blue: 0.46, alpha: 0.15)))
                                    .frame(width: 30, height: 40)
                                Text(String(template.name.prefix(1)).uppercased())
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.primary)
                            }
                            Text(template.name)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                                .frame(width: 44)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
            
            Divider()
            
            // Spreads list
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(spreads) { spread in
                        spreadRow(spread)
                    }
                }
                .padding(.vertical, 16)
            }
            
            Divider()
            
            // Action Footer
            HStack(spacing: 12) {
                Text("\(state.laidOutDocument?.pages.count ?? 0) 页, \(spreads.count) 个跨页")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: {
                    state.saveCurrentPageLayoutAsTemplate(name: "主页 \(state.project.safeSavedLayoutTemplates.count + 1)")
                }) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("新建主页模板")
                
                Button(action: {
                    let nextNum = (state.laidOutDocument?.pages.count ?? 0) + 1
                    state.insertPage(at: nextNum)
                }) {
                    Image(systemName: "plus.rectangle")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("新建页面")
                
                Button(action: {
                    state.deletePage(at: state.currentPageNumber)
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .disabled((state.laidOutDocument?.pages.count ?? 0) <= 1)
                .help("删除页面")
            }
            .padding(.all, 10)
            .background(Color(NSColor.windowBackgroundColor))
        }
    }
    
    private var spreads: [PageSpread] {
        let pages = state.laidOutDocument?.pages ?? []
        guard !pages.isEmpty else { return [] }
        
        var result: [PageSpread] = []
        if state.project.pageSetup.facingPages {
            // Facing pages layout: Page 1 is single cover (right)
            if let p1 = pages.first(where: { $0.number == 1 }) {
                result.append(PageSpread(leftPage: nil, rightPage: p1))
            }
            
            var index = 1
            while index < pages.count {
                let left = pages[index]
                let right = (index + 1 < pages.count) ? pages[index + 1] : nil
                result.append(PageSpread(leftPage: left, rightPage: right))
                index += 2
            }
        } else {
            // Single pages stacked
            for page in pages {
                result.append(PageSpread(leftPage: nil, rightPage: page))
            }
        }
        return result
    }
    
    private var pageThumbnailHeight: CGFloat {
        let setup = state.project.pageSetup
        return 42 * CGFloat(setup.pageSize.height / setup.pageSize.width)
    }
    
    private func spreadRow(_ spread: PageSpread) -> some View {
        VStack(alignment: .center, spacing: 4) {
            HStack(spacing: 0) {
                // Left page
                if let left = spread.leftPage {
                    pageItemButton(left)
                } else {
                    if state.project.pageSetup.facingPages {
                        Spacer()
                            .frame(width: 42, height: pageThumbnailHeight)
                    }
                }
                
                // Spine Guide line
                if state.project.pageSetup.facingPages {
                    Divider()
                        .frame(width: 1, height: pageThumbnailHeight)
                        .background(Color.secondary.opacity(0.35))
                }
                
                // Right page
                if let right = spread.rightPage {
                    pageItemButton(right)
                } else {
                    Spacer()
                        .frame(width: 42, height: pageThumbnailHeight)
                }
            }
            
            Text(spread.numberLabel)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
    
    private func pageItemButton(_ page: LaidOutPage) -> some View {
        Button(action: {
            state.currentPageNumber = page.number
            onPageClick(page.number)
        }) {
            VStack(spacing: 2) {
                pageThumbnail(page)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(state.currentPageNumber == page.number ? Color.accentColor : Color.clear, lineWidth: 2)
                    )
                
                if state.project.safeLockedPages.contains(page.number) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
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
            Button("在当前页前插入新页面") {
                state.insertPage(at: page.number)
            }
            Button("在当前页后插入新页面") {
                state.insertPage(at: page.number + 1)
            }
            Button("删除当前页面") {
                state.deletePage(at: page.number)
            }
            .disabled((state.laidOutDocument?.pages.count ?? 0) <= 1)
            Divider()
            Button("清除自定义布局") {
                state.clearCustomLayoutForPage(number: page.number)
            }
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
        case .text, .footnote, .sideNote:
            color = .primary.opacity(0.35)
        case .footnoteDivider:
            color = .secondary.opacity(0.4)
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
    
    // MARK: - Layers Tab
    
    private var layersTabContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("当前页图层 (第 \(state.currentPageNumber) 页)")
                .font(.caption)
                .foregroundColor(.secondary)
                .fontWeight(.medium)
                .padding([.horizontal, .top], 12)
            
            if let page = state.laidOutDocument?.pages.first(where: { $0.number == state.currentPageNumber }),
               !page.frames.isEmpty {
                List {
                    ForEach(page.frames) { frame in
                        Button(action: {
                            state.selectedFrameId = frame.id
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: layerIcon(for: frame.kind))
                                    .foregroundColor(state.selectedFrameId == frame.id ? Color.accentColor : .secondary)
                                    .font(.system(size: 11))
                                    .frame(width: 14)
                                
                                Text(layerLabel(for: frame))
                                    .font(.body)
                                    .foregroundColor(state.selectedFrameId == frame.id ? Color.accentColor : .primary)
                                    .lineLimit(1)
                                
                                Spacer()
                            }
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.sidebar)
            } else {
                VStack {
                    Spacer()
                    Text("当前页面没有图层元素")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    private func layerIcon(for kind: PageFrameKind) -> String {
        switch kind {
        case .text, .footnote, .sideNote: return "text.alignleft"
        case .caption: return "text.alignleft"
        case .image: return "photo"
        case .callout: return "rectangle.inset.filled"
        case .table: return "tablecells"
        case .footnoteDivider: return "minus"
        }
    }
    
    private func layerLabel(for frame: PageFrame) -> String {
        switch frame.kind {
        case .text:
            if case .text(let txt) = frame.content {
                return "文本框: \(txt.prefix(12))"
            }
            return "空文本框"
        case .caption:
            if case .text(let txt) = frame.content {
                return "图注框: \(txt.prefix(12))"
            }
            return "图注框"
        case .image:
            return "图片框"
        case .callout:
            return "边栏呼应框"
        case .table:
            return "表格数据框"
        case .footnote:
            return "脚注信息"
        case .footnoteDivider:
            return "脚注分界线"
        case .sideNote:
            return "旁注信息"
        }
    }
    
    // MARK: - Assets/Links Tab
    
    private var assetsTabContent: some View {
        List {
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
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.sidebar)
    }
    
    // MARK: - Swatches Tab
    
    private var swatchesTabContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("色板库 (点击应用到所选容器的\(state.isFillActive ? "填充色" : "描边色"))")
                .font(.caption)
                .foregroundColor(.secondary)
                .fontWeight(.medium)
                .padding([.horizontal, .top], 12)
                .padding(.bottom, 6)
            
            let swatches = [
                SwatchItem(name: "[无]", color: nil),
                SwatchItem(name: "[纸色]", color: .white),
                SwatchItem(name: "[黑色]", color: .black),
                SwatchItem(name: "洋红 (Magenta)", color: .init(nsColor: NSColor(calibratedRed: 0.90, green: 0.05, blue: 0.45, alpha: 1))),
                SwatchItem(name: "青色 (Cyan)", color: .init(nsColor: NSColor(calibratedRed: 0.05, green: 0.70, blue: 0.90, alpha: 1))),
                SwatchItem(name: "黄色 (Yellow)", color: .init(nsColor: NSColor(calibratedRed: 0.95, green: 0.85, blue: 0.05, alpha: 1))),
                SwatchItem(name: "经典红 (Red)", color: .red),
                SwatchItem(name: "生态绿 (Green)", color: .green),
                SwatchItem(name: "科技蓝 (Blue)", color: .blue),
                SwatchItem(name: "系统青 (Teal)", color: Color(nsColor: NSColor(calibratedRed: 0.18, green: 0.48, blue: 0.46, alpha: 1)))
            ]
            
            List {
                ForEach(swatches) { swatch in
                    Button(action: {
                        if let color = swatch.color {
                            if state.isFillActive {
                                state.activeFillColor = color
                            } else {
                                state.activeStrokeColor = color
                            }
                            state.applyColorToSelectedFrame(color)
                        } else {
                            state.removeColorFromSelectedFrame()
                        }
                    }) {
                        HStack(spacing: 12) {
                            if let color = swatch.color {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(color)
                                    .frame(width: 16, height: 16)
                                    .border(Color.primary.opacity(0.4), width: 0.5)
                            } else {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 2)
                                        .stroke(Color.primary.opacity(0.4), lineWidth: 0.5)
                                        .background(Color(NSColor.controlBackgroundColor))
                                        .frame(width: 16, height: 16)
                                    
                                    GeometryReader { proxy in
                                        Path { path in
                                            path.move(to: CGPoint(x: proxy.size.width, y: 0))
                                            path.addLine(to: CGPoint(x: 0, y: proxy.size.height))
                                        }
                                        .stroke(Color.red, lineWidth: 1.0)
                                    }
                                }
                                .frame(width: 16, height: 16)
                            }
                            
                            Text(swatch.name)
                                .font(.body)
                                .foregroundColor(.primary)
                            
                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.sidebar)
        }
    }
    
    // MARK: - Helper Methods
    
    private func label(for usage: AssetUsage) -> String {
        switch usage {
        case .unused: return "未用"
        case .placed: return "已用"
        case .repeated: return "重复"
        }
    }

    private func color(for usage: AssetUsage) -> Color {
        switch usage {
        case .unused: return .secondary
        case .placed: return Color(nsColor: NSColor(calibratedRed: 0.18, green: 0.48, blue: 0.46, alpha: 1))
        case .repeated: return .orange
        }
    }
    
    private func iconName(for role: AssetRole) -> String {
        switch role {
        case .hero: return "photo.fill"
        case .diagram: return "square.grid.2x2"
        case .photo: return "camera.fill"
        case .chart: return "chart.bar.fill"
        case .step: return "list.number"
        case .comparison: return "rectangle.split.2x1.fill"
        case .decorative: return "sparkles"
        case .spread: return "photo.on.rectangle"
        }
    }

    private func sizeLabel(for asset: Asset) -> String {
        guard asset.pixelWidth > 0, asset.pixelHeight > 0 else {
            return "尺寸未知"
        }
        return "\(asset.pixelWidth)x\(asset.pixelHeight)"
    }
}
