// swift-tools-version: 6.0

import CompilerPluginSupport
import PackageDescription

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
        .library(name: "AgentKittenInferenceSupport", targets: [
            "AgentKittenInferenceSupport",
        ]),
        .library(name: "AgentKittenAnthropicInference", targets: [
            "AgentKittenAnthropicInference",
        ]),
        .library(name: "AgentKittenAppleInference", targets: [
            "AgentKittenAppleInference",
        ]),
        .library(name: "AgentKittenOpenAIInference", targets: [
            "AgentKittenOpenAIInference",
        ]),
        .library(name: "AgentKittenInferenceTestSupport", targets: [
            "AgentKittenInferenceTestSupport",
        ]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-log", from: "1.6.0"),
        .package(url: "https://github.com/swiftlang/swift-syntax", from: "600.0.0"),
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "AgentKittenCore",
            dependencies: ["AgentKittenMacros", .product(name: "Logging", package: "swift-log")],
        ),
        .target(
            name: "AgentKitten",
            dependencies: [
                "AgentKittenCore",
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy"),
            ],
        ),
        .target(
            name: "AgentKittenInferenceSupport",
            dependencies: ["AgentKittenCore"],
        ),
        .target(
            name: "AgentKittenAnthropicInference",
            dependencies: ["AgentKittenCore", "AgentKittenInferenceSupport"],
        ),
        .target(
            name: "AgentKittenAppleInference",
            dependencies: ["AgentKittenCore", "AgentKittenInferenceSupport"],
        ),
        .target(
            name: "AgentKittenOpenAIInference",
            dependencies: ["AgentKittenCore", "AgentKittenInferenceSupport"],
        ),
        .target(
            name: "AgentKittenInferenceTestSupport",
            dependencies: ["AgentKittenCore", .product(name: "Logging", package: "swift-log")],
        ),
        .macro(
            name: "AgentKittenMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ],
        ),
        .executableTarget(
            name: "Playground",
            dependencies: [
                "AgentKitten",
                "AgentKittenAnthropicInference",
                "AgentKittenAppleInference",
                "AgentKittenOpenAIInference",
                "AgentKittenInferenceTestSupport",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            resources: [
                .process("Fixtures"),
            ],
        ),
        .testTarget(
            name: "AgentKittenInferenceSupportTests",
            dependencies: ["AgentKittenInferenceSupport"],
        ),
        .testTarget(
            name: "AgentKittenAnthropicInferenceTests",
            dependencies: [
                "AgentKittenAnthropicInference",
                "AgentKittenInferenceSupport",
                "AgentKittenInferenceTestSupport",
            ],
        ),
        .testTarget(
            name: "AgentKittenAppleInferenceTests",
            dependencies: [
                "AgentKittenAppleInference",
                "AgentKittenInferenceTestSupport",
            ],
        ),
        .testTarget(
            name: "AgentKittenOpenAIInferenceTests",
            dependencies: [
                "AgentKittenOpenAIInference",
                "AgentKittenInferenceSupport",
                "AgentKittenInferenceTestSupport",
            ],
        ),
        .testTarget(
            name: "AgentKittenInferenceTestSupportTests",
            dependencies: [
                "AgentKittenInferenceTestSupport",
                "AgentKittenCore",
            ],
        ),
        .testTarget(
            name: "AgentKittenCoreTests",
            dependencies: [
                "AgentKittenCore",
                "AgentKittenInferenceTestSupport",
            ],
        ),
        .testTarget(
            name: "AgentKittenTests",
            dependencies: [
                "AgentKitten",
                "AgentKittenInferenceTestSupport",
            ],
        ),
        .testTarget(
            name: "PlaygroundTests",
            dependencies: [
                .target(name: "Playground", condition: .when(platforms: [.macOS, .linux])),
            ],
        ),
    ],
    swiftLanguageModes: [.v6],
)
