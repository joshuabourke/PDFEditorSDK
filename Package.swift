// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PDFEditorSDK",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "PDFEditorSDK",
            targets: ["PDFEditorSDK"]
        )
    ],
    targets: [
        .target(
            name: "PDFEditorSDK",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
