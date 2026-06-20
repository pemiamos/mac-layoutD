import LayoutDExport
import Foundation
import XCTest

/// 阶段 E0 spike 的自动验证：只保证「能产出结构完整、可解包的 IDML 容器」。
/// 「能否在 InDesign 中文版干净打开」必须人工验收——见 PROJECT_CONTEXT / development-plan。
final class IDMLSpikeExporterTests: XCTestCase {
    func testWritesUnzippableIDMLContainer() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("layoutd-idml-spike-test-\(UUID().uuidString)")
            .appendingPathExtension("idml")
        defer { try? FileManager.default.removeItem(at: url) }

        try IDMLSpikeExporter().export(to: url, imagePath: nil)

        // 1. 文件存在且非空。
        let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        XCTAssertGreaterThan(size, 1024)

        // 2. 解包后关键部件齐全。
        let entries = try zipEntryList(url)
        for required in [
            "mimetype",
            "designmap.xml",
            "META-INF/container.xml",
            "Resources/Graphic.xml",
            "Resources/Styles.xml",
            "Spreads/Spread_uSpread1.xml",
            "Stories/Story_uStoryH.xml",
            "Stories/Story_uStoryV.xml"
        ] {
            XCTAssertTrue(entries.contains(required), "IDML 缺少部件：\(required)")
        }

        // 3. mimetype 必须是 ZIP 的第一个条目（IDML 包约定）。
        XCTAssertEqual(entries.first, "mimetype", "mimetype 必须是包内第一个条目")

        // ZIP local header: first entry must be stored (method 0), named mimetype, with exact data.
        let archive = try Data(contentsOf: url)
        XCTAssertEqual(readUInt32LE(archive, at: 0), 0x0403_4b50)
        XCTAssertEqual(readUInt16LE(archive, at: 8), 0)
        let nameLength = Int(readUInt16LE(archive, at: 26))
        let extraLength = Int(readUInt16LE(archive, at: 28))
        let name = String(data: archive.subdata(in: 30..<(30 + nameLength)), encoding: .utf8)
        XCTAssertEqual(name, "mimetype")
        let payloadStart = 30 + nameLength + extraLength
        let payloadSize = Int(readUInt32LE(archive, at: 18))
        let payload = String(data: archive.subdata(in: payloadStart..<(payloadStart + payloadSize)), encoding: .utf8)
        XCTAssertEqual(payload, "application/vnd.adobe.indesign-idml-package")

        // 4. 竖排 story 确实带上了 Vertical 取向（这是整条路线要证伪的关键点）。
        let verticalStory = try unzipEntry(url, entry: "Stories/Story_uStoryV.xml")
        XCTAssertTrue(verticalStory.contains("StoryOrientation=\"Vertical\""))

        // 5. CMYK Swatch 在场。
        let graphic = try unzipEntry(url, entry: "Resources/Graphic.xml")
        XCTAssertTrue(graphic.contains("LayoutD Accent"))
        XCTAssertTrue(graphic.contains("Space=\"CMYK\""))
    }

    // MARK: - zip 读取辅助（unzip -l / -p）

    private func zipEntryList(_ url: URL) throws -> [String] {
        let out = try run("/usr/bin/unzip", ["-Z1", url.path])
        return out.split(separator: "\n").map(String.init)
    }

    private func unzipEntry(_ url: URL, entry: String) throws -> String {
        try run("/usr/bin/unzip", ["-p", url.path, entry])
    }

    private func run(_ launchPath: String, _ args: [String]) throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launchPath)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        // 在读完管道前不要 waitUntilExit，避免大输出阻塞；这里输出很小，先 run 再读。
        try proc.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func readUInt16LE(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private func readUInt32LE(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}
