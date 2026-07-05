import SwiftUI
import UniformTypeIdentifiers
import LayoutDCore
import LayoutDCheck
import LayoutDDesignAI
import LayoutDImport

enum IssueFilter: String, CaseIterable {
    case all
    case errors
    case warnings
    case info

    var title: String {
        switch self {
        case .all:
            return "全部"
        case .errors:
            return "错误"
        case .warnings:
            return "警告"
        case .info:
            return "信息"
        }
    }

    func matches(_ severity: IssueSeverity) -> Bool {
        switch self {
        case .all:
            return true
        case .errors:
            return severity == .error
        case .warnings:
            return severity == .warning
        case .info:
            return severity == .info
        }
    }
}

enum IssueCategoryFilter: String, CaseIterable {
    case all
    case metadata
    case structure
    case references
    case assets
    case pagination
    case layout
    case typography
    case tableOfContents
    case prepress
    case uncategorized

    var preflightCategory: PreflightIssueCategory? {
        switch self {
        case .all, .uncategorized:
            return nil
        case .metadata:
            return .metadata
        case .structure:
            return .structure
        case .references:
            return .references
        case .assets:
            return .assets
        case .pagination:
            return .pagination
        case .layout:
            return .layout
        case .typography:
            return .typography
        case .tableOfContents:
            return .tableOfContents
        case .prepress:
            return .prepress
        }
    }

    var title: String {
        switch self {
        case .all:
            return "全部分类"
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
        case .uncategorized:
            return "未分类"
        }
    }

    func matches(_ category: PreflightIssueCategory?) -> Bool {
        switch self {
        case .all:
            return true
        case .metadata:
            return category == .metadata
        case .structure:
            return category == .structure
        case .references:
            return category == .references
        case .assets:
            return category == .assets
        case .pagination:
            return category == .pagination
        case .layout:
            return category == .layout
        case .typography:
            return category == .typography
        case .tableOfContents:
            return category == .tableOfContents
        case .prepress:
            return category == .prepress
        case .uncategorized:
            return category == nil
        }
    }
}

struct InspectorView: View {
    @ObservedObject var state: AppState
    var onIssueClick: (LayoutIssue) -> Void
    var onApplyPlan: (LayoutPlan) -> Void

    // 对象级属性（选中元素的变换/外观/文字）已迁往「属性」标签的 ObjectPropertiesView，
    // 检查器专注项目/预检仪表盘，颜色拾取相关的 helper 也随之移出。

    @State private var selectedMetadata = true
    @State private var selectedAssets = true
    @State private var selectedSetup = true
    @State private var selectedStyles = true
    @State private var selectedIssues = true
    @State private var selectedAI = true
    @State private var selectedPageControl = true
    @State private var selectedQualityMetrics = true
    @State var issueFilter: IssueFilter = .all
    @State var issueCategoryFilter: IssueCategoryFilter = .all
    @State private var layoutTemplateName = ""
    @State private var selectedChapterTemplate: ChapterLayoutTemplate = .scienceChapter
    @State private var selectedChapterTemplateSectionIndex = 0
    @State private var chapterTemplateStartPage = 3
    @State private var selectedPageTemplate: PageLayoutTemplate = .textLedPage

    @State private var importedTokens: DesignTokens? = nil
    @State private var importedFormat: ImportFormat = .dtcg
    @State private var showImportSheet = false
    @State private var importErrorMessage: String? = nil
    @State private var showImportErrorAlert = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Section 1: Preflight Status Header
                if let report = state.report {
                    preflightHeader(report: report)
                    Divider()
                }

                // Section 1.2: Page Control
                DisclosureGroup("页面控制 (第 \(state.currentPageNumber) 页)", isExpanded: $selectedPageControl) {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("锁定当前页版式", isOn: Binding(
                            get: { state.project.safeLockedPages.contains(state.currentPageNumber) },
                            set: { isLocked in
                                if isLocked {
                                    state.lockPage(number: state.currentPageNumber)
                                } else {
                                    state.unlockPage(number: state.currentPageNumber)
                                }
                            }
                        ))
                        .toggleStyle(.checkbox)
                        
                        if state.project.safeLockedPages.contains(state.currentPageNumber) {
                            Text("⚠️ 页面已锁定，元素无法在画布上拖拽或修改尺寸。")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }

                        Divider()

                        TextField("模板名称", text: $layoutTemplateName)
                            .textFieldStyle(.roundedBorder)

                        Button("保存当前页为模板") {
                            state.saveCurrentPageLayoutAsTemplate(name: layoutTemplateName)
                            layoutTemplateName = ""
                        }
                        .buttonStyle(.bordered)

                        if state.project.safeSavedLayoutTemplates.isEmpty {
                            Text("暂无已保存版式模板")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("应用已保存模板")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                ForEach(state.project.safeSavedLayoutTemplates) { template in
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                TextField("模板名称", text: Binding(
                                                    get: { template.name },
                                                    set: { state.renameSavedLayoutTemplate(id: template.id, name: $0) }
                                                ))
                                                .font(.caption)
                                                .textFieldStyle(.roundedBorder)
                                                Text(template.plan.strategy.rawValue)
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                            Spacer()
                                            Button("应用") {
                                                state.applySavedLayoutTemplate(id: template.id, toPage: state.currentPageNumber)
                                            }
                                            .buttonStyle(.bordered)
                                            .disabled(state.project.safeLockedPages.contains(state.currentPageNumber))
                                            Button("删除") {
                                                state.deleteSavedLayoutTemplate(id: template.id)
                                            }
                                            .buttonStyle(.bordered)
                                            .foregroundColor(.red)
                                        }

                                        TemplateParametersEditorView(template: template, state: state)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("系统页模板")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            HStack {
                                Picker("模板", selection: $selectedPageTemplate) {
                                    ForEach(PageLayoutTemplate.allCases, id: \.self) { template in
                                        Text(template.displayName).tag(template)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()

                                Button("应用") {
                                    state.applyPageLayoutTemplate(selectedPageTemplate, toPage: state.currentPageNumber)
                                }
                                .buttonStyle(.bordered)
                                .disabled(state.project.safeLockedPages.contains(state.currentPageNumber))
                            }
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("应用章节模板")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Picker("章节", selection: $selectedChapterTemplateSectionIndex) {
                                ForEach(state.project.sections.indices, id: \.self) { index in
                                    Text(state.project.sections[index].title).tag(index)
                                }
                            }
                            .pickerStyle(.menu)
                            .disabled(state.project.sections.isEmpty)

                            Picker("模板", selection: $selectedChapterTemplate) {
                                ForEach(ChapterLayoutTemplate.allCases, id: \.self) { template in
                                    Text(template.displayName).tag(template)
                                }
                            }
                            .pickerStyle(.menu)

                            Stepper(
                                "起始页：\(chapterTemplateStartPage)",
                                value: $chapterTemplateStartPage,
                                in: 1...999
                            )

                            Button("应用章节模板") {
                                let maxIndex = max(state.project.sections.count - 1, 0)
                                selectedChapterTemplateSectionIndex = min(selectedChapterTemplateSectionIndex, maxIndex)
                                _ = state.applyChapterLayoutTemplate(
                                    selectedChapterTemplate,
                                    sectionIndex: selectedChapterTemplateSectionIndex,
                                    startPage: chapterTemplateStartPage
                                )
                            }
                            .buttonStyle(.bordered)
                            .disabled(state.project.sections.isEmpty)
                        }
                    }
                    .padding(.top, 6)
                }
                Divider()

                // Section 2: Book Metadata
                DisclosureGroup("图书元数据", isExpanded: $selectedMetadata) {
                    VStack(spacing: 8) {
                        HStack {
                            Text("书名").frame(width: 50, alignment: .leading)
                            TextField("书名", text: Binding(
                                get: { state.project.metadata.title },
                                set: { value in state.updateProject { $0.metadata.title = value } }
                            ))
                        }
                        HStack {
                            Text("副标题").frame(width: 50, alignment: .leading)
                            TextField("副标题", text: Binding(
                                get: { state.project.metadata.subtitle ?? "" },
                                set: { value in state.updateProject { $0.metadata.subtitle = value.isEmpty ? nil : value } }
                            ))
                        }
                        HStack {
                            Text("作者").frame(width: 50, alignment: .leading)
                            TextField("作者", text: Binding(
                                get: { state.project.metadata.author },
                                set: { value in state.updateProject { $0.metadata.author = value } }
                            ))
                        }
                        HStack {
                            Text("出版社").frame(width: 50, alignment: .leading)
                            TextField("出版社", text: Binding(
                                get: { state.project.metadata.publisher ?? "" },
                                set: { value in state.updateProject { $0.metadata.publisher = value.isEmpty ? nil : value } }
                            ))
                        }
                        HStack {
                            Text("ISBN").frame(width: 50, alignment: .leading)
                            TextField("ISBN", text: Binding(
                                get: { state.project.metadata.isbn ?? "" },
                                set: { value in state.updateProject { $0.metadata.isbn = value.isEmpty ? nil : value } }
                            ))
                        }
                        HStack {
                            Text("丛书").frame(width: 50, alignment: .leading)
                            TextField("丛书", text: Binding(
                                get: { state.project.metadata.series ?? "" },
                                set: { value in state.updateProject { $0.metadata.series = value.isEmpty ? nil : value } }
                            ))
                        }
                        HStack {
                            Text("关键词").frame(width: 50, alignment: .leading)
                            TextField("逗号分隔", text: Binding(
                                get: { state.project.metadata.keywords.joined(separator: ", ") },
                                set: { value in state.updateProject { $0.metadata.keywords = parseKeywords(value) } }
                            ))
                        }
                    }
                    .padding(.top, 6)
                    .textFieldStyle(.roundedBorder)
                }

                Divider()

                // Section 2.5: Asset Metadata
                DisclosureGroup("素材元数据 (\(state.project.assets.count))", isExpanded: $selectedAssets) {
                    if state.project.assets.isEmpty {
                        Text("当前项目没有素材")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 6)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(state.project.assets.indices, id: \.self) { index in
                                assetRow(index: index)
                            }
                        }
                        .padding(.top, 6)
                    }
                }

                Divider()

                // Section 3: Page Layout Setup
                DisclosureGroup("版面参数设置", isExpanded: $selectedSetup) {
                    VStack(spacing: 10) {
                        HStack {
                            Text("分栏数")
                            Spacer()
                            Stepper("\(state.project.pageSetup.columns) 栏", value: Binding(
                                get: { state.project.pageSetup.columns },
                                set: { value in state.updateProject { $0.pageSetup.columns = value } }
                            ), in: 1...4)
                        }
                        
                        HStack {
                            Text("栏间距 (mm)")
                            Spacer()
                            Stepper(
                                String(format: "%.1f mm", pointsToMillimeters(state.project.pageSetup.gutter)),
                                value: Binding(
                                    get: { pointsToMillimeters(state.project.pageSetup.gutter) },
                                    set: { value in state.updateProject { $0.pageSetup.gutter = millimetersToPoints(value) } }
                                ),
                                in: 2.0...15.0,
                                step: 0.5
                            )
                        }
                        
                        HStack {
                            Text("基线网格 (pt)")
                            Spacer()
                            Stepper("\(Int(state.project.pageSetup.baselineGrid)) pt", value: Binding(
                                get: { state.project.pageSetup.baselineGrid },
                                set: { value in state.updateProject { $0.pageSetup.baselineGrid = value } }
                            ), in: 8...24, step: 1)
                        }

                        Toggle("对页排版", isOn: Binding(
                            get: { state.project.pageSetup.facingPages },
                            set: { value in state.updateProject { $0.pageSetup.facingPages = value } }
                        ))
                            .toggleStyle(.checkbox)

                        HStack {
                            Text("印刷出血 (mm)")
                            Spacer()
                            Stepper(
                                String(format: "%.1f mm", state.project.pageSetup.bleedMM ?? 3.0),
                                value: Binding(
                                    get: { state.project.pageSetup.bleedMM ?? 3.0 },
                                    set: { value in state.updateProject { $0.pageSetup.bleedMM = value } }
                                ),
                                in: 0.0...10.0,
                                step: 0.5
                            )
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("页边距 (mm)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            HStack {
                                Text("上:")
                                Stepper(
                                    String(format: "%.1f", pointsToMillimeters(state.project.pageSetup.margins.top)),
                                    value: Binding(
                                        get: { pointsToMillimeters(state.project.pageSetup.margins.top) },
                                        set: { value in state.updateProject { $0.pageSetup.margins.top = millimetersToPoints(value) } }
                                    ),
                                    in: 8.0...40.0,
                                    step: 0.5
                                )
                                Spacer()
                                Text("下:")
                                Stepper(
                                    String(format: "%.1f", pointsToMillimeters(state.project.pageSetup.margins.bottom)),
                                    value: Binding(
                                        get: { pointsToMillimeters(state.project.pageSetup.margins.bottom) },
                                        set: { value in state.updateProject { $0.pageSetup.margins.bottom = millimetersToPoints(value) } }
                                    ),
                                    in: 8.0...40.0,
                                    step: 0.5
                                )
                            }
                            HStack {
                                Text("左:")
                                Stepper(
                                    String(format: "%.1f", pointsToMillimeters(state.project.pageSetup.margins.left)),
                                    value: Binding(
                                        get: { pointsToMillimeters(state.project.pageSetup.margins.left) },
                                        set: { value in state.updateProject { $0.pageSetup.margins.left = millimetersToPoints(value) } }
                                    ),
                                    in: 8.0...40.0,
                                    step: 0.5
                                )
                                Spacer()
                                Text("右:")
                                Stepper(
                                    String(format: "%.1f", pointsToMillimeters(state.project.pageSetup.margins.right)),
                                    value: Binding(
                                        get: { pointsToMillimeters(state.project.pageSetup.margins.right) },
                                        set: { value in state.updateProject { $0.pageSetup.margins.right = millimetersToPoints(value) } }
                                    ),
                                    in: 8.0...40.0,
                                    step: 0.5
                                )
                            }
                        }
                        .padding(.top, 4)
                    }
                    .padding(.top, 6)
                }

                Divider()

                // Section 4: Styles Editor
                DisclosureGroup("段落样式参数", isExpanded: $selectedStyles) {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("样式模板", selection: Binding(
                            get: { currentStyleTemplate },
                            set: { state.applyStyleTemplate($0) }
                        )) {
                            ForEach(StyleTemplate.allCases, id: \.self) { template in
                                Text(template.displayName).tag(template)
                            }
                        }
                        .pickerStyle(.menu)

                        Button("导入 Figma/DTCG 样式...") {
                            importStyleFile()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .padding(.vertical, 2)

                        ForEach(state.project.styles.paragraphStyles.indices, id: \.self) { index in
                            styleRow(index: index)
                        }
                    }
                    .padding(.top, 6)
                }

                Divider()

                // Section 5: Preflight Issues
                DisclosureGroup("排版问题检查 (\(filteredIssueCount))", isExpanded: $selectedIssues) {
                    if let report = state.report {
                        if report.issues.isEmpty {
                            Text("无任何排版问题")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 8)
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                Picker("问题筛选", selection: $issueFilter) {
                                    ForEach(IssueFilter.allCases, id: \.self) { filter in
                                        Text(filter.title).tag(filter)
                                    }
                                }
                                .pickerStyle(.segmented)

                                Picker("问题分类", selection: $issueCategoryFilter) {
                                    ForEach(IssueCategoryFilter.allCases, id: \.self) { filter in
                                        Text(filter.title).tag(filter)
                                    }
                                }
                                .pickerStyle(.menu)

                                HStack(spacing: 8) {
                                    if report.issues.contains(where: { $0.autoFixKind != nil }) {
                                        Button("自动修复全部") {
                                            state.applyAvailablePreflightFixes()
                                        }
                                        .buttonStyle(.borderedProminent)
                                    }

                                    if let selectedCategory = issueCategoryFilter.preflightCategory,
                                       report.issues.contains(where: { $0.category == selectedCategory && $0.autoFixKind != nil }) {
                                        Button("自动修复当前分类") {
                                            state.applyPreflightFixes(in: selectedCategory)
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }

                                if filteredIssues(report).isEmpty {
                                    Text("当前筛选下无问题")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding(.vertical, 6)
                                }

                                ForEach(filteredIssues(report), id: \.id) { issue in
                                    let location = issueLocation(for: issue, report: report)
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack(alignment: .top, spacing: 6) {
                                            issueIcon(issue.severity)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(issue.message)
                                                    .font(.subheadline)
                                                    .foregroundColor(.primary)
                                                    .multilineTextAlignment(.leading)
                                                    .lineLimit(2)
                                                if let suggestedFix = issue.suggestedFix {
                                                    Text("建议：\(suggestedFix)")
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                        .multilineTextAlignment(.leading)
                                                        .lineLimit(2)
                                                }
                                                if let category = issue.category {
                                                    Text("分类：\(categoryTitle(category))")
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                }
                                                if let page = issue.pageNumber {
                                                    Text("第 \(page) 页")
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                                if let location {
                                                    Text(locationLabel(location))
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                        .monospacedDigit()
                                                }
                                            }
                                            Spacer()
                                            
                                            if let fix = issue.autoFixKind {
                                                Button("修复") {
                                                    state.applyPreflightFix(fix, targetingAssetId: issue.assetId, targetingFrameId: issue.frameId)
                                                }
                                                .buttonStyle(.bordered)
                                                .controlSize(.small)
                                            }
                                        }
                                    }
                                    .padding(.all, 8)
                                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                                    .cornerRadius(6)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        onIssueClick(issue)
                                    }
                                }
                            }
                            .padding(.top, 6)
                        }
                    } else {
                        Text("无可用报告")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                // Section 6: AI Candidates
                DisclosureGroup("AI LayoutPlan 布局候选", isExpanded: $selectedAI) {
                    if state.plans.isEmpty {
                        Text("暂无布局候选")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(state.plans) { plan in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(plan.strategy.rawValue.capitalized)
                                            .font(.headline)
                                            .foregroundColor(Color(nsColor: NSColor(calibratedRed: 0.18, green: 0.48, blue: 0.46, alpha: 1)))
                                        Spacer()
                                        Button(action: {
                                            onApplyPlan(plan)
                                        }) {
                                            Text("应用布局")
                                                .font(.caption)
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 3)
                                                .background(Color(nsColor: NSColor(calibratedRed: 0.18, green: 0.48, blue: 0.46, alpha: 1)))
                                                .cornerRadius(4)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    
                                    Text("\(plan.blocks.count) 个布局块 (Blocks)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    ForEach(plan.notes, id: \.self) { note in
                                        Text("• \(note)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .multilineTextAlignment(.leading)
                                    }
                                }
                                .padding(.all, 10)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(8)
                            }
                        }
                        .padding(.top, 6)
                    }
                }

                Divider()

                // Section 7: Quality Metrics
                DisclosureGroup("排版质量指标", isExpanded: $selectedQualityMetrics) {
                    if let report = state.report {
                        qualityMetricsView(report: report)
                    } else {
                        Text("无可用质量数据")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                    }
                }
            }
            .padding(.all, 14)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showImportSheet) {
            if let tokens = importedTokens {
                StyleImportSheet(
                    state: state,
                    tokens: tokens,
                    format: importedFormat,
                    onDismiss: { showImportSheet = false }
                )
            }
        }
        .alert(isPresented: $showImportErrorAlert) {
            Alert(
                title: Text("导入样式错误"),
                message: Text(importErrorMessage ?? ""),
                dismissButton: .default(Text("好"))
            )
        }
    }

    private func importStyleFile() {
        let openPanel = NSOpenPanel()
        openPanel.title = "选择 Figma Variables 或 DTCG Design Tokens JSON 文件"
        openPanel.allowedContentTypes = [.json]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        
        openPanel.begin { response in
            if response == .OK, let url = openPanel.url {
                do {
                    let data = try Data(contentsOf: url)
                    let result = try StyleBaselineImporter.autoDetectAndParse(jsonData: data)
                    self.importedTokens = result.tokens
                    self.importedFormat = result.format
                    self.showImportSheet = true
                } catch {
                    self.importErrorMessage = "解析失败: \(error.localizedDescription)"
                    self.showImportErrorAlert = true
                }
            }
        }
    }

    private var filteredIssueCount: Int {
        guard let report = state.report else {
            return 0
        }
        return filteredIssues(report).count
    }

    private var currentStyleTemplate: StyleTemplate {
        StyleTemplate.allCases.first {
            $0.styleLibrary == state.project.styles
        } ?? .chineseScienceDefault
    }
}
