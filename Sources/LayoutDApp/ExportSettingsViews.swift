import SwiftUI
import LayoutDCore
import LayoutDExport

class PDFExportSettingsState: ObservableObject {
    @Published var pageRange: String = ""
    @Published var drawCropMarks: Bool = false
    @Published var drawGridGuides: Bool = false
    @Published var pdfxVersion: PDFXVersion = .none
}

struct PDFExportSettingsView: View {
    @ObservedObject var state: PDFExportSettingsState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PDF 导出选项")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("页码范围:")
                        .frame(width: 80, alignment: .leading)
                    TextField("例如: 1-5, 8, 11-13 (留空导出全部)", text: $state.pageRange)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                }
                Text("可选格式: 单个页码(如 3)、范围(如 2-5)、多段用逗号分隔")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.leading, 85)
            }
            
            Toggle("包含裁切与出血指示标记 (Crop & Bleed Marks)", isOn: $state.drawCropMarks)
                .toggleStyle(.checkbox)
            
            Toggle("包含版心、栏与基线参考线 (仅用于校对排版)", isOn: $state.drawGridGuides)
                .toggleStyle(.checkbox)
            
            HStack {
                Text("PDF 标准/意图:")
                    .frame(width: 100, alignment: .leading)
                Picker("", selection: $state.pdfxVersion) {
                    Text("普通 RGB (无意图标记)").tag(PDFXVersion.none)
                    Text("PDF/X-1a (CMYK Web SWOP 模拟)").tag(PDFXVersion.pdfx1a)
                    Text("PDF/X-3 (ISO Coated FOGRA39 模拟)").tag(PDFXVersion.pdfx3)
                }
                .pickerStyle(.segmented)
                .frame(width: 320)
            }
        }
        .padding()
    }
}

class PNGExportSettingsState: ObservableObject {
    @Published var pageRange: String = ""
    @Published var scale: Double = 2.0
}

final class IDMLExportSettingsState: ObservableObject {
    @Published var requireExportReady: Bool = false
    @Published var facingPages: Bool = false
    @Published var cmykColors: Bool = false
}

struct IDMLExportSettingsView: View {
    @ObservedObject var state: IDMLExportSettingsState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("IDML 导出选项")
                .font(.headline)
            
            Toggle("仅在预检完全通过 (Export Ready) 时允许导出", isOn: $state.requireExportReady)
                .toggleStyle(.checkbox)
            
            Toggle("启用对开跨页 (Facing Pages) 版式设计", isOn: $state.facingPages)
                .toggleStyle(.checkbox)

            Toggle("导出 CMYK 印刷色板 (默认 RGB 屏幕色板)", isOn: $state.cmykColors)
                .toggleStyle(.checkbox)
            
            Text("说明：导出的 IDML 将拷贝相关链接图片至 Links 目录下，并在 InDesign 中保持完美的相对图链链接。")
                .font(.caption)
                .foregroundColor(.gray)
                .frame(width: 360, alignment: .leading)
        }
        .padding()
    }
}

struct PNGExportSettingsView: View {
    @ObservedObject var state: PNGExportSettingsState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PNG 预览图导出选项")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("页码范围:")
                        .frame(width: 80, alignment: .leading)
                    TextField("例如: 1-5, 8 (留空导出全部)", text: $state.pageRange)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                }
            }
            
            HStack {
                Text("导出缩放倍率 (Scale):")
                Slider(value: $state.scale, in: 1.0...4.0, step: 0.5) {
                    Text("")
                }
                Text(String(format: "%.1f x", state.scale))
                    .frame(width: 40)
            }
            .frame(width: 320)
        }
        .padding()
    }
}
