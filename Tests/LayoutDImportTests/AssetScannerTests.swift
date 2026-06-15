import Foundation
import LayoutDCore
import LayoutDImport
import XCTest

final class AssetScannerTests: XCTestCase {
    func testScannerMergesManifestMetadata() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("layoutd-asset-scanner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let imageURL = directory.appendingPathComponent("cell.png")
        try samplePNGData.write(to: imageURL)
        let manifest = """
        file,caption,role,credit
        cell.png,细胞结构示意,diagram,layoutD
        """
        try manifest.write(to: directory.appendingPathComponent("manifest.csv"), atomically: true, encoding: .utf8)

        let assets = try AssetScanner().scan(directory: directory)

        XCTAssertEqual(assets.count, 1)
        XCTAssertEqual(assets[0].fileName, "cell.png")
        XCTAssertEqual(assets[0].caption, "细胞结构示意")
        XCTAssertEqual(assets[0].role, .diagram)
        XCTAssertEqual(assets[0].credit, "layoutD")
        XCTAssertGreaterThan(assets[0].pixelWidth, 0)
        XCTAssertGreaterThan(assets[0].pixelHeight, 0)
    }

    func testManifestWidePlacementActsAsHeroRole() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("layoutd-asset-scanner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try samplePNGData.write(to: directory.appendingPathComponent("opening.png"))
        let manifest = """
        file,caption,span,source
        opening.png,开场跨栏图,wide,layoutD
        """
        try manifest.write(to: directory.appendingPathComponent("assets.csv"), atomically: true, encoding: .utf8)

        let assets = try AssetScanner().scan(directory: directory)

        XCTAssertEqual(assets[0].role, .hero)
        XCTAssertEqual(assets[0].caption, "开场跨栏图")
        XCTAssertEqual(assets[0].credit, "layoutD")
    }
}

private let samplePNGData = Data(base64Encoded: """
iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=
""")!
