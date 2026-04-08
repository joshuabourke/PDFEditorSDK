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
├── PDFEditorSDK.swift                    — public entry points (PDFEditorView, ImageEditorView)
├── Editor/
│   ├── PDFEditorView.swift               — SwiftUI shell and toolbar
│   ├── PDFFormViewModel.swift            — editing state, undo/redo, save/export logic
│   ├── DrawingPDFView.swift              — UIKit PDF canvas with gesture handling
│   ├── EditorModels.swift                — shared enums and data types
│   ├── OverlayViews.swift                — TextBoxView, ImageBoxView, ShapeBoxView
│   └── PencilKitOverlayManager.swift     — standalone PencilKit canvas integration
├── ImageEditor/
│   └── ImageEditorView.swift             — image editing pipeline
└── Support/
    └── Styling/                          — shared view modifiers
```

---

## PDF Editor

### What it does

- Opens an existing PDF from a `URL`
- Supports form filling, text highlights, freehand drawing (pencil + finger), text overlays, image overlays, shape overlays, and page management
- **Apple PencilKit** integration — native brush effects (watercolor, crayon, marker, pencil) via a dedicated PencilKit mode that captures drawings as image overlays
- **2-finger navigation** — scroll and pinch-to-zoom with two fingers in every annotation mode (draw, shape, text, select, and PencilKit), keeping single-finger gestures reserved for drawing
- **Page management** — add blank pages or remove the current page, both with full undo/redo support
- **Image borders** — configurable border width (none / thin / medium / thick) and border colour on image overlays, burned into the export
- Saves an editable PDF locally by embedding overlay metadata back into the document
- Exports a flattened PDF (annotations burned in) for sharing off-device
- Preserves PDF document metadata (title, author, keywords, etc.) during export
- Full undo / redo (up to 50 steps)
- Apple Pencil, Scribble, and checkbox-toggle-with-pencil support

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

### Toolbar overview

| Section | Controls |
|---|---|
| **Form** | Fill in interactive PDF form fields (text, checkboxes, radio buttons, dropdowns). Works with both finger and Apple Pencil. |
| **Draw** | Freehand ink drawing. Sub-tools: line weight (Fine / Medium / Thick — default Medium), colour picker, eraser toggle, eraser size. Use 2 fingers to scroll while drawing. |
| **Text** | Single-finger tap to create a text box (drag to set size). Tap an existing box to edit it; tap anywhere else to dismiss the keyboard. Sub-tools: text colour, background colour (including white), font size, bold. |
| **Shape** | Draw circles, rectangles, or triangles as vector overlay shapes. Sub-tools: shape picker, stroke colour, line weight. Use 2 fingers to scroll while placing shapes. |
| **Select** | Tap any overlay (text box, image, shape) to select it. Drag to move, drag the orange handle to resize, tap **Delete** to remove. When an image overlay is selected, configure its border width and colour from the toolbar. |
| **Pencil** | Native Apple PencilKit canvas — draw with watercolour, crayon, marker, fountain pen, and more. Tap **Done** to commit the drawing as an image overlay. Use 2 fingers to scroll the page while drawing. |
| **Pages** | **Add** inserts a blank page after the current page. **Remove** deletes the current page (requires confirmation; disabled on single-page documents). Both actions are fully undoable. |

---

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
- Drag-to-create text boxes with configurable font size, bold, text colour, and background colour (including white)
- Overlay cropped images from Camera or Photo Library — tap **Image** to pick, use the built-in system crop tool, then drag and pinch-resize the result on the canvas
- **Configurable image borders** — choose border width (none / thin / medium / thick) and border colour for any image overlay, burned into the export
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
| **Draw** | Activate freehand drawing. Sub-tools: line weight (Fine / Medium / Thick — default Medium), colour picker, eraser toggle, eraser size |
| **Text** | Drag on the image to draw a text box. Sub-tools: text colour, background colour (including white), font size, bold |
| **Select** | Tap any text box or image overlay to select it. Drag to move, drag the orange handle to resize, tap **Delete** in the toolbar to remove. When an image is selected, configure its border width and colour from the toolbar. |
| **Image** | Add a photo from Camera or Photo Library with built-in crop. After placing, switch to Select to reposition, resize, or add a border |

---

## Changelog

### Recent improvements

- **Apple PencilKit mode** (PDF Editor) — a new **Pencil** tool overlays a native `PKCanvasView` on the current PDF page, giving access to PencilKit's full brush library (watercolour, crayon, marker, fountain pen, and more). Tapping **Done** commits the drawing as a transparent PNG image overlay, fully integrated with undo/redo and flattened export. 2-finger scrolling works while PencilKit is active.

- **2-finger navigation in all annotation modes** — scrolling and pinch-to-zoom with two fingers now works consistently whether you are drawing, placing shapes, editing text boxes, or in PencilKit mode. Single-finger gestures are reserved for annotation so the two actions never conflict.

- **Page management** (PDF Editor) — the toolbar now includes **Add** (inserts a blank page after the current one) and **Remove** (deletes the current page with a confirmation alert). Both actions are reversible via undo/redo. Remove is disabled and greyed out on single-page documents.

- **Image borders** — image overlays in both the PDF and Image editors now support a configurable border. Select an image overlay to access border-width (none / thin / medium / thick) and border-colour controls in the toolbar. The border is burned into the flattened export.

- **White background for text boxes** — the background-colour menu for text boxes now includes a **White** option, useful when placing text over dark content.

- **Text mode tap behaviour** — in Text mode, tapping an existing text box immediately opens it for editing. Tapping anywhere outside a text box closes the keyboard and deselects the current box, ready for you to draw a new one.

- **Default pen weight aligned** — the default ink line weight is now **Medium (3 pt)**, matching the visible Medium option in the weight picker.
