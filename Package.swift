// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CYK-Parser",
    platforms: [
        .macOS(.v11),
        .iOS(.v14),
    ],
    products: [
        .library(
            name: "CYK-Parser", targets: ["CYK-Parser"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.6.2"),
        .package(url: "https://github.com/JohnSundell/ShellOut.git", from: "2.0.0"),
        .package(url: "https://github.com/hakkabon/Grammar.git", branch: "main"),
        .package(url: "https://github.com/hakkabon/GrammarTokenizer.git", branch: "main"),
        .package(url: "https://github.com/hakkabon/GrammarDiagram.git", branch: "main"),
        .package(url: "https://github.com/hakkabon/TerminalColors.git", from: "0.0.1"),
    ],
    targets: [
        .target(
            name: "CYK-Parser",
            dependencies: [
                .product(name: "Grammar", package: "Grammar"),
                .product(name: "Tokenizer", package: "GrammarTokenizer"),
                .product(name: "GrammarDiagram", package: "GrammarDiagram"),
                .product(name: "TerminalColors", package: "TerminalColors"),
            ],
            path: "Sources/CYK-Parser",
        ),
        .testTarget(
            name: "CYK-ParserTests",
            dependencies: [
                "CYK-Parser",
                .product(name: "Grammar", package: "Grammar"),
            ]
        ),
        // Move executable target to its destination (grammar toolbox) when library confirmed working.
        .executableTarget(
            name: "gtool",
            dependencies: [
                "CYK-Parser",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "ShellOut", package: "shellout"),
                .product(name: "Grammar", package: "Grammar"),
                .product(name: "GrammarDiagram", package: "GrammarDiagram"),
            ]
        ),
    ]
)
