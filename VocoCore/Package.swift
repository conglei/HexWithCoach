// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VocoCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "VocoCore", targets: ["VocoCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Clipy/Sauce", branch: "master"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.11.0"),
        .package(url: "https://github.com/apple/swift-log", from: "1.9.1"),
    ],
    targets: [
	    .target(
	        name: "VocoCore",
	        dependencies: [
	            // Sauce is macOS-only (Carbon-based keyboard library). On iOS the
	            // in-module `Key` shim (Models/HexKeyCompat.swift) stands in for it.
	            .product(name: "Sauce", package: "Sauce", condition: .when(platforms: [.macOS])),
	            .product(name: "Dependencies", package: "swift-dependencies"),
	            .product(name: "DependenciesMacros", package: "swift-dependencies"),
	            .product(name: "Logging", package: "swift-log"),
	        ],
	        path: "Sources/VocoCore",
	        resources: [
	            // Bundled keyless teaching assets (CI-4): phoneme guide,
	            // fluency tips, L1→interference table. Loaded via Bundle.module.
	            .process("Coach/Resources"),
	        ],
	        linkerSettings: [
	            .linkedFramework("IOKit", .when(platforms: [.macOS])),
	        ]
	    ),
        .testTarget(
            name: "VocoCoreTests",
            dependencies: ["VocoCore"],
            path: "Tests/VocoCoreTests",
            resources: [
                .copy("Fixtures")
            ]
        ),
    ]
)
