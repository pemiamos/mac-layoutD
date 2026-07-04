import SwiftUI
import UniformTypeIdentifiers
import LayoutDCore
import LayoutDCheck
import LayoutDDesignAI
import LayoutDImport

private enum IssueFilter: String, CaseIterable {
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

private enum IssueCategoryFilter: String, CaseIterable {
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
    @State private var issueFilter: IssueFilter = .all
    @State private var issueCategoryFilter: IssueCategoryFilter = .all
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

    private func filteredIssues(_ report: PreflightReport) -> [LayoutIssue] {
        report.issues.filter {
            issueFilter.matches($0.severity) && issueCategoryFilter.matches($0.category)
        }
    }

    private var currentStyleTemplate: StyleTemplate {
        StyleTemplate.allCases.first {
            $0.styleLibrary == state.project.styles
        } ?? .chineseScienceDefault
    }

    private func issueLocation(for issue: LayoutIssue, report: PreflightReport) -> IssueLocation? {
        report.issueLocations.first { $0.issueId == issue.id }
    }

    private func categoryTitle(_ category: PreflightIssueCategory) -> String {
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

    private func locationLabel(_ location: IssueLocation) -> String {
        String(
            format: "%@ frame · x %.0f y %.0f w %.0f h %.0f",
            location.frameKind,
            location.rect.x,
            location.rect.y,
            location.rect.width,
            location.rect.height
        )
    }

    // Sub-view: Preflight Header
    private func preflightHeader(report: PreflightReport) -> some View {
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

    // Sub-view: Style Edit Row
    private func styleRow(index: Int) -> some View {
        let style = state.project.styles.paragraphStyles[index]
        return VStack(alignment: .leading, spacing: 6) {
            Text(style.displayName)
                .font(.subheadline)
                .fontWeight(.medium)
            
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow {
                    Text("字号:")
                    Stepper(String(format: "%.1f pt", style.fontSize), value: Binding(
                        get: { style.fontSize },
                        set: { state.updateParagraphStyle(id: style.id, fontSize: $0) }
                    ), in: 8.0...36.0, step: 0.5)
                    
                    Text("行高:")
                    Stepper("\(Int(style.lineHeight)) pt", value: Binding(
                        get: { style.lineHeight },
                        set: { state.updateParagraphStyle(id: style.id, lineHeight: $0) }
                    ), in: 10.0...50.0, step: 1.0)
                }
                
                GridRow {
                    Text("段前:")
                    Stepper("\(Int(style.spaceBefore)) pt", value: Binding(
                        get: { style.spaceBefore },
                        set: { state.updateParagraphStyle(id: style.id, spaceBefore: $0) }
                    ), in: 0.0...40.0, step: 1.0)
                    
                    Text("段后:")
                    Stepper("\(Int(style.spaceAfter)) pt", value: Binding(
                        get: { style.spaceAfter },
                        set: { state.updateParagraphStyle(id: style.id, spaceAfter: $0) }
                    ), in: 0.0...40.0, step: 1.0)
                }
                
                if style.id == StyleID.body.rawValue {
                    GridRow {
                        Text("缩进:")
                        Stepper("\(Int(style.firstLineIndent)) pt", value: Binding(
                            get: { style.firstLineIndent },
                            set: { state.updateParagraphStyle(id: style.id, firstLineIndent: $0) }
                        ), in: 0.0...40.0, step: 1.0)
                    }
                }
            }
            .font(.caption)

            DisclosureGroup("复合字体设置") {
                VStack(alignment: .leading, spacing: 6) {
                    compositeFontEditor(styleId: style.id, charClass: .chinese, label: "中文/全角标点", style: style)
                    compositeFontEditor(styleId: style.id, charClass: .latin, label: "英文/半角标点", style: style)
                    compositeFontEditor(styleId: style.id, charClass: .digit, label: "数字", style: style)
                }
                .padding(.top, 4)
            }
            .font(.caption)
        }
        .padding(.all, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        .cornerRadius(6)
    }

    private func compositeFontEditor(
        styleId: String,
        charClass: CompositeFontClass,
        label: String,
        style: ParagraphStyle
    ) -> some View {
        let mapping = style.compositeFont?[charClass] ?? CompositeFontMapping(
            fontName: style.fontName,
            sizeMultiplier: 1.0,
            baselineOffset: 0.0
        )
        let curatedFonts = [
            "Songti SC",
            "PingFang SC",
            "Heiti SC",
            "Kaiti SC",
            "Times New Roman",
            "Helvetica",
            "Georgia",
            "Arial"
        ]
        
        return VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            
            HStack(spacing: 4) {
                Picker("字体", selection: Binding(
                    get: { mapping.fontName },
                    set: { state.updateParagraphStyleCompositeFont(id: styleId, charClass: charClass, fontName: $0, sizeMultiplier: mapping.sizeMultiplier, baselineOffset: mapping.baselineOffset) }
                )) {
                    ForEach(curatedFonts, id: \.self) { font in
                        Text(font).tag(font)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                
                Spacer()
                
                Text("大小:")
                    .font(.system(size: 9))
                Stepper(String(format: "%d%%", Int(mapping.sizeMultiplier * 100)), value: Binding(
                    get: { mapping.sizeMultiplier },
                    set: { state.updateParagraphStyleCompositeFont(id: styleId, charClass: charClass, fontName: mapping.fontName, sizeMultiplier: $0, baselineOffset: mapping.baselineOffset) }
                ), in: 0.5...2.0, step: 0.05)
                .labelsHidden()
                
                Text("基线:")
                    .font(.system(size: 9))
                Stepper(String(format: "%.1f", mapping.baselineOffset), value: Binding(
                    get: { mapping.baselineOffset },
                    set: { state.updateParagraphStyleCompositeFont(id: styleId, charClass: charClass, fontName: mapping.fontName, sizeMultiplier: mapping.sizeMultiplier, baselineOffset: $0) }
                ), in: -10.0...10.0, step: 0.5)
                .labelsHidden()
            }
        }
    }

    // Sub-view: Asset Edit Row
    private func assetRow(index: Int) -> some View {
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

    private func assetDetailLabel(_ asset: Asset) -> String {
        let size = asset.pixelWidth > 0 && asset.pixelHeight > 0
            ? "\(asset.pixelWidth)x\(asset.pixelHeight)"
            : "尺寸未知"
        let dpi = asset.dpi.map { "\(Int($0)) DPI" } ?? "DPI ?"
        return "\(size) · \(dpi)"
    }

    private func assetUsageLabel(_ usage: AssetUsage) -> String {
        switch usage {
        case .unused:
            return "未用"
        case .placed:
            return "已用"
        case .repeated:
            return "重复"
        }
    }

    private func assetUsageColor(_ usage: AssetUsage) -> Color {
        switch usage {
        case .unused:
            return .secondary
        case .placed:
            return Color(nsColor: NSColor(calibratedRed: 0.18, green: 0.48, blue: 0.46, alpha: 1))
        case .repeated:
            return .orange
        }
    }

    private func assetRoleLabel(_ role: AssetRole) -> String {
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

    private func parseKeywords(_ text: String) -> [String] {
        text
            .split(whereSeparator: { $0 == "," || $0 == "，" })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func pointsToMillimeters(_ points: Double) -> Double {
        points / 72 * 25.4
    }

    private func millimetersToPoints(_ millimeters: Double) -> Double {
        millimeters / 25.4 * 72
    }

    // Sub-view: Issue Icon
    private func issueIcon(_ severity: IssueSeverity) -> some View {
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

    // MARK: - Quality Metrics Helpers
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter
    }()

    private func metricCard(title: String, value: String, icon: String, color: Color) -> some View {
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

    private func historyCard(entry: QualityHistoryEntry) -> some View {
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

    private func qualityMetricsView(report: PreflightReport) -> some View {
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

struct TemplateParametersEditorView: View {
    let template: SavedLayoutTemplate
    let state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Margins override
            HStack {
                Toggle("自定义边距", isOn: Binding(
                    get: { template.plan.marginOverride != nil },
                    set: { enable in
                        let newMargins = enable ? (template.plan.marginOverride ?? state.project.pageSetup.margins) : nil
                        state.updateSavedLayoutTemplateParameters(
                            id: template.id,
                            marginOverride: newMargins,
                            columnsOverride: template.plan.columnsOverride,
                            showHeadersFooters: template.plan.showHeadersFooters
                        )
                    }
                ))
                .font(.caption2)
                
                Spacer()
            }
            
            if let margins = template.plan.marginOverride {
                VStack(spacing: 4) {
                    HStack(spacing: 8) {
                        HStack(spacing: 2) {
                            Text("上:").font(.caption2).foregroundColor(.secondary)
                            TextField("", value: Binding(
                                get: { margins.top },
                                set: { val in
                                    var m = margins
                                    m.top = val
                                    state.updateSavedLayoutTemplateParameters(
                                        id: template.id,
                                        marginOverride: m,
                                        columnsOverride: template.plan.columnsOverride,
                                        showHeadersFooters: template.plan.showHeadersFooters
                                    )
                                }
                            ), format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 45)
                        }
                        HStack(spacing: 2) {
                            Text("下:").font(.caption2).foregroundColor(.secondary)
                            TextField("", value: Binding(
                                get: { margins.bottom },
                                set: { val in
                                    var m = margins
                                    m.bottom = val
                                    state.updateSavedLayoutTemplateParameters(
                                        id: template.id,
                                        marginOverride: m,
                                        columnsOverride: template.plan.columnsOverride,
                                        showHeadersFooters: template.plan.showHeadersFooters
                                    )
                                }
                            ), format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 45)
                        }
                    }
                    HStack(spacing: 8) {
                        HStack(spacing: 2) {
                            Text("左:").font(.caption2).foregroundColor(.secondary)
                            TextField("", value: Binding(
                                get: { margins.left },
                                set: { val in
                                    var m = margins
                                    m.left = val
                                    state.updateSavedLayoutTemplateParameters(
                                        id: template.id,
                                        marginOverride: m,
                                        columnsOverride: template.plan.columnsOverride,
                                        showHeadersFooters: template.plan.showHeadersFooters
                                    )
                                }
                            ), format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 45)
                        }
                        HStack(spacing: 2) {
                            Text("右:").font(.caption2).foregroundColor(.secondary)
                            TextField("", value: Binding(
                                get: { margins.right },
                                set: { val in
                                    var m = margins
                                    m.right = val
                                    state.updateSavedLayoutTemplateParameters(
                                        id: template.id,
                                        marginOverride: m,
                                        columnsOverride: template.plan.columnsOverride,
                                        showHeadersFooters: template.plan.showHeadersFooters
                                    )
                                }
                            ), format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 45)
                        }
                    }
                }
            }
            
            // Columns override
            HStack {
                Toggle("自定义分栏", isOn: Binding(
                    get: { template.plan.columnsOverride != nil },
                    set: { enable in
                        let cols = enable ? (template.plan.columnsOverride ?? state.project.pageSetup.columns) : nil
                        state.updateSavedLayoutTemplateParameters(
                            id: template.id,
                            marginOverride: template.plan.marginOverride,
                            columnsOverride: cols,
                            showHeadersFooters: template.plan.showHeadersFooters
                        )
                    }
                ))
                .font(.caption2)
                
                Spacer()
                
                if let cols = template.plan.columnsOverride {
                    Picker("", selection: Binding(
                        get: { cols },
                        set: { val in
                            state.updateSavedLayoutTemplateParameters(
                                id: template.id,
                                marginOverride: template.plan.marginOverride,
                                columnsOverride: val,
                                showHeadersFooters: template.plan.showHeadersFooters
                            )
                        }
                    )) {
                        ForEach(1...4, id: \.self) { c in
                            Text("\(c) 栏").tag(c)
                        }
                    }
                    .frame(width: 70)
                    .labelsHidden()
                }
            }
            
            // Show Headers & Footers
            Picker("页眉页脚", selection: Binding(
                get: {
                    if let show = template.plan.showHeadersFooters {
                        return show ? 1 : 2
                    }
                    return 0
                },
                set: { val in
                    let opt: Bool?
                    if val == 1 { opt = true }
                    else if val == 2 { opt = false }
                    else { opt = nil }
                    state.updateSavedLayoutTemplateParameters(
                        id: template.id,
                        marginOverride: template.plan.marginOverride,
                        columnsOverride: template.plan.columnsOverride,
                        showHeadersFooters: opt
                    )
                }
            )) {
                Text("默认").tag(0)
                Text("显示").tag(1)
                Text("隐藏").tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(6)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(4)
    }
}
