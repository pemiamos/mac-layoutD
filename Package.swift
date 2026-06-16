// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "layoutD",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "layoutD", targets: ["LayoutDApp"]),
        .library(name: "LayoutDCore", targets: ["LayoutDCore"]),
        .library(name: "LayoutDEngine", targets: ["LayoutDEngine"]),
        .library(name: "LayoutDDesignAI", targets: ["LayoutDDesignAI"]),
        .library(name: "LayoutDImport", targets: ["LayoutDImport"]),
        .library(name: "LayoutDCheck", targets: ["LayoutDCheck"]),
        .library(name: "LayoutDExport", targets: ["LayoutDExport"])
    ],
    targets: [
        .target(name: "LayoutDCore"),
        .target(
            name: "LayoutDEngine",
            dependencies: ["LayoutDCore"]
        ),
        .target(
            name: "LayoutDDesignAI",
            dependencies: ["LayoutDCore"]
        ),
        .target(
            name: "LayoutDImport",
            dependencies: ["LayoutDCore"]
        ),
        .target(
            name: "LayoutDCheck",
            dependencies: ["LayoutDCore"]
        ),
        .target(
            name: "LayoutDExport",
            dependencies: ["LayoutDCore", "LayoutDEngine"]
        ),
        .executableTarget(
            name: "LayoutDApp",
            dependencies: [
                "LayoutDCore",
                "LayoutDEngine",
                "LayoutDDesignAI",
                "LayoutDImport",
                "LayoutDCheck",
                "LayoutDExport"
            ]
        ),
        .testTarget(
            name: "LayoutDCoreTests",
            dependencies: ["LayoutDCore", "LayoutDEngine", "LayoutDDesignAI"]
        ),
        .testTarget(
            name: "LayoutDImportTests",
            dependencies: ["LayoutDCore", "LayoutDImport"]
        ),
        .testTarget(
            name: "LayoutDExportTests",
            dependencies: ["LayoutDCore", "LayoutDEngine", "LayoutDExport"]
        ),
        .testTarget(
            name: "LayoutDCheckTests",
            dependencies: ["LayoutDCore", "LayoutDCheck"]
        ),
        .testTarget(
            name: "LayoutDAppTests",
            dependencies: ["LayoutDApp"]
        )
    ]
)
