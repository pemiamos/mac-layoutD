import SwiftUI
import LayoutDCore

/// 右侧面板坞第四段「线框图」：辅助排版的常驻控制器。
/// 把散在向导站 4/5 里的骨架圈选、权重、规划调节收进一个随排随调的面板：
/// - 当前页图文/留白密度读数（来自已排版文档，实时）
/// - 留白比例 / 大图气口频率两个规划旋钮（写进 wizardState，重新规划时生效）
/// - 全部预置对开骨架的灰盒线框图 + 启用开关 + 权重滑杆（复用 WireframeRenderer）
/// - 「重新规划」一键重跑 SpreadPlanner，并显示当前对开骨架序列
struct WireframePanelView: View {
    @ObservedObject var state: AppState
    var onRunPlanner: (@escaping ([String]?) -> Void) -> Void

    @State private var isPlanning = false
    @State private var lastPlanResult: String?

    // 线框缩略图按骨架 id 缓存，避免每次刷新重画
    @State private var thumbnailCache: [String: NSImage] = [:]

    private var wizardState: WizardState {
        state.project.wizardState ?? WizardState()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                densitySection
                Divider()
                knobsSection
                Divider()
                archetypeSection
                Divider()
                planSection
            }
            .padding(10)
        }
    }

    // MARK: - 当前页密度读数

    private var currentPageDensity: (text: Double, image: Double, whitespace: Double)? {
        guard let doc = state.laidOutDocument,
              let page = doc.pages.first(where: { $0.number == state.currentPageNumber }) else {
            return nil
        }
        let pageSize = state.project.pageSetup.pageSize
        let pageArea = pageSize.width * pageSize.height
        guard pageArea > 0 else { return nil }

        var textArea = 0.0
        var imageArea = 0.0
        for frame in page.frames {
            let area = frame.rect.width * frame.rect.height
            switch frame.kind {
            case .image:
                imageArea += area
            case .text, .caption, .footnote, .sideNote:
                textArea += area
            default:
                break
            }
        }
        let text = min(textArea / pageArea, 1.0)
        let image = min(imageArea / pageArea, 1.0)
        return (text, image, max(0, 1.0 - text - image))
    }

    private var densitySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("当前页 \(state.currentPageNumber) · 图文比例")
                .font(.system(size: 11, weight: .semibold))
            if let d = currentPageDensity {
                densityBar(label: "正文", value: d.text, color: .secondary)
                densityBar(label: "图片", value: d.image, color: .accentColor)
                densityBar(label: "留白", value: d.whitespace, color: Color(nsColor: .tertiaryLabelColor))
            } else {
                Text("尚未排版")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func densityBar(label: String, value: Double, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10))
                .frame(width: 26, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(nsColor: .quaternaryLabelColor))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color.opacity(0.65))
                        .frame(width: max(2, geo.size.width * value))
                }
            }
            .frame(height: 8)
            Text("\(Int(value * 100))%")
                .font(.system(size: 10).monospacedDigit())
                .frame(width: 34, alignment: .trailing)
        }
    }

    // MARK: - 规划旋钮

    private var whitespaceRatioBinding: Binding<Double> {
        Binding(
            get: { wizardState.plannerWhitespaceRatio ?? 0.0 },
            set: { newValue in
                state.updateProject { project in
                    if project.wizardState == nil { project.wizardState = WizardState() }
                    project.wizardState?.plannerWhitespaceRatio = newValue
                }
            }
        )
    }

    private var bigImageEveryBinding: Binding<Double> {
        Binding(
            get: { Double(wizardState.plannerBigImageEvery ?? 3) },
            set: { newValue in
                state.updateProject { project in
                    if project.wizardState == nil { project.wizardState = WizardState() }
                    project.wizardState?.plannerBigImageEvery = Int(newValue)
                }
            }
        )
    }

    private var knobsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("规划调节")
                .font(.system(size: 11, weight: .semibold))

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("留白比例")
                        .font(.system(size: 10))
                    Spacer()
                    Text("+\(Int((wizardState.plannerWhitespaceRatio ?? 0) * 100))%")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundColor(.secondary)
                }
                Slider(value: whitespaceRatioBinding, in: 0...0.5, step: 0.05)
                Text("越大每对开装的正文越少、留白越多（重新规划后生效）")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("大图气口频率")
                        .font(.system(size: 10))
                    Spacer()
                    Text("每 \(wizardState.plannerBigImageEvery ?? 3) 对开")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundColor(.secondary)
                }
                Slider(value: bigImageEveryBinding, in: 2...6, step: 1)
                Text("有可用大图时，至少每 N 对开安排一次整幅大图")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - 骨架圈选

    private var enabledIds: Set<String> {
        Set(wizardState.enabledArchetypeIds ?? SpreadArchetype.defaults.map(\.id))
    }

    private func enabledBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { enabledIds.contains(id) },
            set: { isOn in
                state.updateProject { project in
                    if project.wizardState == nil { project.wizardState = WizardState() }
                    var ids = Set(project.wizardState?.enabledArchetypeIds ?? SpreadArchetype.defaults.map(\.id))
                    if isOn { ids.insert(id) } else { ids.remove(id) }
                    project.wizardState?.enabledArchetypeIds = Array(ids).sorted()
                }
            }
        )
    }

    private func weightBinding(for archetype: SpreadArchetype) -> Binding<Double> {
        Binding(
            get: { wizardState.archetypeWeights?[archetype.id] ?? archetype.weight },
            set: { newValue in
                state.updateProject { project in
                    if project.wizardState == nil { project.wizardState = WizardState() }
                    var weights = project.wizardState?.archetypeWeights ?? [:]
                    weights[archetype.id] = newValue
                    project.wizardState?.archetypeWeights = weights
                }
            }
        )
    }

    private func thumbnail(for archetype: SpreadArchetype) -> NSImage {
        if let cached = thumbnailCache[archetype.id] {
            return cached
        }
        let image = WireframeRenderer.renderSpread(archetype: archetype, size: CGSize(width: 148, height: 92))
        DispatchQueue.main.async {
            thumbnailCache[archetype.id] = image
        }
        return image
    }

    private var noWorkhorseEnabled: Bool {
        !SpreadArchetype.defaults.contains { enabledIds.contains($0.id) && $0.role == .workhorse }
    }

    private var archetypeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("预置对开骨架（\(SpreadArchetype.defaults.count)）")
                .font(.system(size: 11, weight: .semibold))

            if noWorkhorseEnabled {
                Text("⚠️ 没有启用任何正文骨架，正文将无处安放")
                    .font(.system(size: 10))
                    .foregroundColor(.red)
            }

            ForEach(SpreadArchetype.defaults, id: \.id) { archetype in
                archetypeCard(archetype)
            }
        }
    }

    private func archetypeCard(_ archetype: SpreadArchetype) -> some View {
        let isEnabled = enabledIds.contains(archetype.id)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Image(nsImage: thumbnail(for: archetype))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 74, height: 46)
                    .cornerRadius(3)
                    .opacity(isEnabled ? 1.0 : 0.35)

                VStack(alignment: .leading, spacing: 2) {
                    Toggle(isOn: enabledBinding(for: archetype.id)) {
                        Text(archetype.displayName)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                    }
                    .toggleStyle(.checkbox)
                    .controlSize(.small)

                    HStack(spacing: 4) {
                        Text("权重")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Slider(value: weightBinding(for: archetype), in: 0.2...2.0)
                            .controlSize(.mini)
                            .disabled(!isEnabled)
                        Text(String(format: "%.1f", wizardState.archetypeWeights?[archetype.id] ?? archetype.weight))
                            .font(.system(size: 9).monospacedDigit())
                            .foregroundColor(.secondary)
                            .frame(width: 20)
                    }
                }
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    // MARK: - 重新规划

    private var planSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                isPlanning = true
                onRunPlanner { archetypeIds in
                    isPlanning = false
                    if let ids = archetypeIds {
                        lastPlanResult = "已规划 \(ids.count) 个对开"
                    } else {
                        lastPlanResult = "规划失败"
                    }
                }
            } label: {
                HStack {
                    if isPlanning {
                        ProgressView().controlSize(.small)
                    }
                    Text(isPlanning ? "规划中…" : "重新规划全书")
                        .frame(maxWidth: .infinity)
                }
            }
            .disabled(isPlanning || noWorkhorseEnabled)

            if let result = lastPlanResult {
                Text(result)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            if let selections = wizardState.spreadSelections, !selections.isEmpty {
                Text("当前序列")
                    .font(.system(size: 10, weight: .semibold))
                ForEach(selections, id: \.spreadIndex) { selection in
                    HStack(spacing: 4) {
                        Text("对开 \(selection.spreadIndex + 1)")
                            .font(.system(size: 9).monospacedDigit())
                            .foregroundColor(.secondary)
                            .frame(width: 44, alignment: .leading)
                        Text(displayName(forArchetypeId: selection.archetypeId))
                            .font(.system(size: 9))
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private func displayName(forArchetypeId id: String) -> String {
        SpreadArchetype.defaults.first { $0.id == id }?.displayName ?? id
    }
}
