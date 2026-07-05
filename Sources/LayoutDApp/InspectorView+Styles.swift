import SwiftUI
import LayoutDCore

extension InspectorView {
    // Sub-view: Style Edit Row
    func styleRow(index: Int) -> some View {
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

    func compositeFontEditor(
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
