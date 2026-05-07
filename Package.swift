// swift-tools-version: 6.0

import PackageDescription
import CompilerPluginSupport

let swiftSettings: [SwiftSetting] = [
    .unsafeFlags(["-warnings-as-errors"]),
]

let package = Package(
    name: "AgentKitten",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15),
        .iOS(.v17),
        .tvOS(.v17),
        .watchOS(.v10),
        .visionOS(.v1),
        .macCatalyst(.v17),
    ],
    products: [
        .library(name: "AgentKitten", targets: [
            "AgentKitten",
        ]),
        .library(name: "AgentKittenCore", targets: [
            "AgentKittenCore",
        ]),
        .library(name: "AgentKittenInference", targets: [
            "AgentKittenInference",
        ]),
    ],
    dependencies: [
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", from: "0.62.2"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/swiftlang/swift-syntax", from: "600.0.0"),
    ],
    targets: [
        .target(
            name: "AgentKittenCore",
            dependencies: ["AgentKittenMacros"],
            resources: [
                .process("Resources"),
            ],
            swiftSettings: swiftSettings,
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins"),
            ]
        ),
        .target(
            name: "AgentKitten",
            dependencies: [
                "AgentKittenCore",
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy"),
            ],
            swiftSettings: swiftSettings,
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins"),
            ]
        ),
        .target(
            name: "AgentKittenInference",
            dependencies: ["AgentKittenCore"],
            resources: [
                .process("Resources"),
            ],
            swiftSettings: swiftSettings,
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins"),
            ]
        ),
        .macro(
            name: "AgentKittenMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        .executableTarget(
            name: "Playground",
            dependencies: [
                "AgentKitten",
                "AgentKittenInference",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            resources: [
                .process("Fixtures"),
            ],
            swiftSettings: swiftSettings,
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins"),
            ]
        ),
        .testTarget(
            name: "AgentKittenInferenceTests",
            dependencies: ["AgentKittenInference"],
            resources: [
                .process("Resources"),
            ],
            swiftSettings: swiftSettings,
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins"),
            ]
        ),
        .testTarget(
            name: "AgentKittenCoreTests",
            dependencies: [
                "AgentKittenCore",
            ],
            resources: [
                .process("Resources"),
            ],
            swiftSettings: swiftSettings,
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins"),
            ]
        ),
        .testTarget(
            name: "AgentKittenTests",
            dependencies: [
                "AgentKitten",
            ],
            swiftSettings: swiftSettings,
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins"),
            ]
        ),
        .testTarget(
            name: "PlaygroundTests",
            dependencies: ["Playground"],
            swiftSettings: swiftSettings,
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins"),
            ]
        ),
    ]
)
