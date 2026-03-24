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
            path: "PDFEditorSDKDemo",
            sources: [
                "SDK/Public",
                "SDK/Editor",
                "SDK/Support"
            ]
        )
    ]
)
