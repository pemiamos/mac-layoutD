import LayoutDCore
import LayoutDEngine
import LayoutDExport
import XCTest

final class PDFExporterTests: XCTestCase {
    func testExportsNonEmptyPDF() throws {
        let project = BookProject.sample
        let document = LayoutEngine().layout(project: project)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("layoutd-export-test-\(UUID().uuidString)")
            .appendingPathExtension("pdf")

        defer {
            try? FileManager.default.removeItem(at: url)
        }

        try PDFExporter().export(document: document, project: project, to: url)

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attributes[.size] as? NSNumber
        XCTAssertNotNil(fileSize)
        XCTAssertGreaterThan(fileSize?.intValue ?? 0, 1024)
    }
}
