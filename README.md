# PDFEditorSDK

`PDFEditorSDK` is a SwiftUI-first PDF and image editing SDK for iOS.

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
    .package(url: "https://github.com/joshuabourke/PDFEditorSDK.git", from: "1.0.0")
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

```
Sources/PDFEditorSDK/
├── PDFEditorSDK.swift          — public entry points (PDFEditorView, ImageEditorView)
├── Editor/
│   └── PDFEditorView.swift     — PDF editing pipeline
├── ImageEditor/
│   └── ImageEditorView.swift   — image editing pipeline
└── Support/
    └── Styling/                — shared view modifiers
```

---

## PDF Editor

### What it does

- Opens an existing PDF from a `URL`
- Supports form filling, text highlights, freehand drawing (pencil + finger), text overlays, image overlays, and blank page insertion
- Saves an editable PDF locally by embedding overlay metadata back into the document
- Exports a flattened PDF (annotations burned in) for sharing off-device
- Preserves PDF document metadata (title, author, keywords, etc.) during export
- Full undo / redo (up to 50 steps)
- Apple Pencil and Scribble support

### Basic usage

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

### Custom save destinations

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

### Controlling which form fields are highlighted

By default, the editor highlights every interactive form field with a blue overlay to show the user what can be edited. Fields are automatically skipped if either of the following PDF flags are detected:

- **`/Ff` bit 0 — ReadOnly**: the standard PDF field flag that marks a field as non-editable.
- **`/F` bit 8 — Annotation Locked**: used by some PDF authoring tools to prevent a field from being repositioned or modified. PDFs built with this flag on a field typically intend that field to be filled programmatically rather than by the user.

No configuration is needed for either of these cases — the SDK detects them automatically.

#### Custom highlight logic

If your PDF uses a different convention, pass a `shouldHighlightFormField` closure to take full control. The closure receives a `PDFFormFieldInfo` value for each form field and returns `true` to show the highlight or `false` to hide it.

```swift
PDFEditorView(
    url: documentURL,
    shouldHighlightFormField: { field in
        // Suppress the highlight for any field explicitly flagged read-only or locked.
        if field.isReadOnly || field.isAnnotationLocked { return false }
        return true
    }
)
```

You can also target specific fields by name if your app knows which fields should not be user-editable:

```swift
// Internal field names come from the /T key in the PDF's AcroForm dictionary.
// You can inspect them with a tool like PDF Squeezer or by reading the PDF spec's /AcroForm tree.
let readOnlyFields: Set<String> = ["InvoiceNumber", "ContractDate", "ClientID"]

PDFEditorView(
    url: documentURL,
    shouldHighlightFormField: { field in
        guard let name = field.fieldName else { return true }
        return !readOnlyFields.contains(name)
    }
)
```

#### `PDFFormFieldInfo` reference

| Property | Type | Description |
|---|---|---|
| `fieldName` | `String?` | The field's internal name (`/T` key). May be `nil` for unnamed annotations. |
| `isReadOnly` | `Bool` | `true` when `/Ff` bit 0 is set — standard PDF read-only flag. |
| `isAnnotationLocked` | `Bool` | `true` when `/F` bit 8 is set — annotation locked flag used by some authoring tools. |

---

## Image Editor

### What it does

- Accepts any `UIImage` (or raw `Data`) as the canvas background
- Freehand drawing with Apple Pencil or finger — adjustable colour, line weight, and eraser
- Drag-to-create text boxes with configurable font size, bold, text colour, and background colour
- Overlay cropped images from Camera or Photo Library — tap **Image** to pick, use the built-in system crop tool, then drag and pinch-resize the result on the canvas
- All drawing and overlays are constrained to the image content area — no annotations outside the image
- Select tool to move, resize, or delete any text box or image overlay
- Full undo / redo (up to 50 steps)
- Export flattens everything (drawing + text boxes + image overlays) into a single `UIImage` with selection handles automatically hidden

### Basic usage

```swift
import PDFEditorSDK
import SwiftUI

struct MyImageEditorScreen: View {
    let photo: UIImage

    var body: some View {
        NavigationStack {
            ImageEditorView(image: photo)
        }
    }
}
```

### Save and export

The editor has two distinct actions:

- **Save** (`square.and.arrow.down`) — saves the annotated image locally and shows a confirmation alert. If no `onSave` handler is provided, the image is saved as a JPEG to `Documents/ImageEdits/` inside the app sandbox.
- **Export** (`square.and.arrow.up`) — renders the image and opens the system share sheet so the user can AirDrop, send, or save to Photos.

```swift
import PDFEditorSDK
import SwiftUI

struct MyImageEditorScreen: View {
    let photo: UIImage

    var body: some View {
        NavigationStack {
            ImageEditorView(
                image: photo,
                onSave: { savedImage in
                    // Called when the user taps the save button.
                    // savedImage is a flattened UIImage with all annotations burned in
                    // and selection handles automatically hidden.
                    UIImageWriteToSavedPhotosAlbum(savedImage, nil, nil, nil)
                },
                onExport: { exportedImage in
                    // Called when the user taps the share button.
                    // The share sheet is shown automatically — use this callback
                    // if you also need a copy of the result in your own code.
                    print("Exported: \(exportedImage.size)")
                }
            )
        }
    }
}
```

Both callbacks are optional. Omitting `onSave` saves to `Documents/ImageEdits/`; omitting `onExport` still shows the share sheet but skips the callback.

### Initialising from `Data`

If you have image data rather than a `UIImage` (e.g. from a network response or document picker), use the `Data` initialiser:

```swift
ImageEditorView(imageData: imageData) { exportedImage in
    // handle export
}
```

### Toolbar overview

| Section | Controls |
|---|---|
| **Draw** | Activate freehand drawing. Sub-tools: line weight (Fine / Medium / Thick), colour picker, eraser toggle, eraser size |
| **Text** | Drag on the image to draw a text box. Sub-tools: text colour, background colour, font size, bold |
| **Select** | Tap any text box or image overlay to select it. Drag to move, drag the orange handle to resize, tap **Delete** in the toolbar to remove |
| **Image** | Add a photo from Camera or Photo Library with built-in crop. After placing, switch to Select to reposition or resize |
