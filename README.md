# PDFEditorSDK

`PDFEditorSDK` is a SwiftUI-first PDF editing component for iOS.

## Install from GitHub

### In Xcode

1. Open your app project.
2. Go to `File` > `Add Package Dependencies...`
3. Paste your GitHub repo URL.
4. Choose a version rule, ideally `Up to Next Major Version`.
5. Add the `PDFEditorSDK` library to your app target.

### In `Package.swift`

```swift
dependencies: [
    .package(url: "https://github.com/your-org/PDFEditorSDK.git", from: "1.0.0")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "PDFEditorSDK", package: "PDFEditorSDK")
        ]
    )
]
```

To make that work for other developers, the repository needs:

- the root `Package.swift`
- a pushed Git tag such as `1.0.0`
- a public GitHub repo, or a private repo they have access to
- a license if you want to open source it

## Project structure

- `PDFEditorSDKDemo/App`: example host app for trying the SDK locally
- `PDFEditorSDKDemo/SDK/Public`: public API surface such as `PDFEditorView`
- `PDFEditorSDKDemo/SDK/Editor`: editor implementation and PDF editing pipeline
- `PDFEditorSDKDemo/SDK/Support`: shared styling and helper UI pieces
- `PDFEditorSDKDemo/Resources`: sample PDF and app resources for the demo target

## What it does

- Opens an existing PDF from a `URL`
- Supports form filling, highlights, drawing, text overlays, image overlays, and page insertion
- Saves an editable PDF locally by embedding editor metadata back into the PDF
- Exports a flattened PDF for sharing off-device
- Preserves common PDF document metadata during flattened export

## Basic usage

```swift
import PDFEditorSDK
import SwiftUI

struct MyEditorScreen: View {
    let documentURL: URL

    var body: some View {
        PDFEditorView(url: documentURL)
    }
}
```

## Custom save destinations

Use the optional callbacks if your app wants to control where editable or flattened files end up.

```swift
import PDFEditorSDK
import SwiftUI

struct MyEditorScreen: View {
    let documentURL: URL

    var body: some View {
        PDFEditorView(
            url: documentURL,
            onSaveEditable: { request in
                let destination = FileManager.default
                    .urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("Editable")
                    .appendingPathComponent(request.suggestedFileName)

                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )

                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }

                try FileManager.default.copyItem(at: request.temporaryURL, to: destination)
                return destination
            },
            onExportFlattened: { request in
                let exportsFolder = FileManager.default
                    .urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("Exports")

                try FileManager.default.createDirectory(
                    at: exportsFolder,
                    withIntermediateDirectories: true
                )

                let destination = exportsFolder.appendingPathComponent(request.suggestedFileName)
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }

                try FileManager.default.copyItem(at: request.temporaryURL, to: destination)
                return destination
            }
        )
    }
}
```
