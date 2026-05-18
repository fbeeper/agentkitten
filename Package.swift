// swift-tools-version: 6.2

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "AgentKitten",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .tvOS(.v18),
        .watchOS(.v11),
        .visionOS(.v2),
        .macCatalyst(.v18),
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
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/swiftlang/swift-syntax", from: "600.0.0"),
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "AgentKittenCore",
            dependencies: ["AgentKittenMacros"],
            resources: [
                .process("Resources"),
            ]
        ),
        .target(
            name: "AgentKitten",
            dependencies: [
                "AgentKittenCore",
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy"),
            ]
        ),
        .target(
            name: "AgentKittenInference",
            dependencies: ["AgentKittenCore"],
            resources: [
                .process("Resources"),
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
            ]
        ),
        .testTarget(
            name: "AgentKittenInferenceTests",
            dependencies: ["AgentKittenInference"],
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "AgentKittenCoreTests",
            dependencies: [
                "AgentKittenCore",
            ],
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "AgentKittenTests",
            dependencies: [
                "AgentKitten",
            ]
        ),
        .testTarget(
            name: "PlaygroundTests",
            dependencies: ["Playground"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
