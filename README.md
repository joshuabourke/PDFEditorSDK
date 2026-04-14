# PDFEditorSDK

`PDFEditorSDK` is a SwiftUI-first PDF and image editing SDK for iOS, built with native UIKit rendering, full Apple Pencil support, configurable Pencil gesture mapping, and a clean long-press toolbar designed for touch and stylus workflows.

---

## Install from GitHub

### In Xcode

1. Open your app project.
2. Go to `File` > `Add Package Dependencies...`
3. Paste your GitHub repo URL.
4. Choose a version rule — `Up to Next Major Version` is recommended.
5. Add the `PDFEditorSDK` library to your app target.

### In `Package.swift`

```swift
dependencies: [
    .package(url: "https://github.com/joshuabourke/PDFEditorSDK.git", from: "2.0.0")
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

---

## Project structure

```
Sources/PDFEditorSDK/
├── PDFEditorSDK.swift                    — public entry points (PDFEditorView, ImageEditorView)
├── Editor/
│   ├── PDFEditorView.swift               — SwiftUI shell and toolbar
│   ├── PDFFormViewModel.swift            — editing state, undo/redo, save/export logic
│   ├── DrawingPDFView.swift              — UIKit PDF canvas with gesture handling
│   ├── EditorModels.swift                — shared enums and data types
│   ├── EditorPreferences.swift           — UserDefaults persistence for tool settings
│   ├── EditorSettingsView.swift          — input mode settings popover
│   ├── ToolOptionsViews.swift            — per-tool settings popovers (draw, erase, text, shape)
│   ├── OverlayViews.swift                — TextBoxView, ImageBoxView, ShapeBoxView
│   └── PencilKitOverlayManager.swift     — standalone PencilKit canvas integration
├── ImageEditor/
│   ├── ImageEditorView.swift             — image editing pipeline (SwiftUI + UIKit)
│   └── ImageEditorViewModel.swift        — image editor state and undo/redo
└── Support/
    └── Styling/                          — shared view modifiers
```

---

## PDF Editor

### What it does

- Opens an existing PDF from a `URL`
- **Form filling** — text fields, checkboxes, radio buttons, and dropdowns; works with finger or Apple Pencil
- **Freehand drawing** — ink strokes with adjustable colour and line weight; dedicated standalone eraser tool
- **Text overlays** — drag-to-create text boxes with font size, bold, text colour, and background colour
- **Shape overlays** — circles, rectangles, and triangles as crisp vector shapes with stroke colour and weight; shapes can be drawn over existing annotations
- **Image overlays** — pick from Camera or Photo Library, then drag and pinch-resize; configurable border
- **Apple PencilKit mode** — native brush effects (watercolour, crayon, marker, fountain pen) captured as image overlays
- **Select mode** — tap to select any overlay, drag to move, orange handle to resize, delete from toolbar
- **Pencil-only annotation mode** — restrict all annotation tools (draw, erase, shape, text) to Apple Pencil; finger scrolls and zooms freely
- **Draw with Finger mode** — single finger draws ink strokes; two fingers scroll
- **Apple Pencil gesture mapping** — assign custom actions to double-tap (Pencil 2 and Pro) and squeeze gestures (Pencil Pro); see [Apple Pencil Gestures](#apple-pencil-gestures)
- **Tool settings persistence** — colour, line weight, shape type, font size, input mode, and gesture assignments are remembered between sessions
- **2-finger navigation** — scroll and pinch-to-zoom in every non-pencil-only annotation mode
- **Page management** — add blank pages or remove the current page, with full undo/redo
- Saves an editable PDF locally by embedding overlay metadata back into the document
- Exports a flattened PDF (annotations burned in) for off-device sharing
- Preserves PDF document metadata (title, author, keywords) during export
- Full undo / redo (up to 50 steps)
- Scribble and checkbox-toggle-with-pencil support

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

```swift
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
```

### Toolbar overview

The toolbar uses a **tap + long-press** interaction model:

- **Tap** a tool button to activate it (or deactivate it if already active, returning to Select mode).
- **Long-press** a tool button to open its settings popover without changing the active tool.

| Section | Tap | Long-press settings |
|---|---|---|
| **Select** | Activate select mode. Sub-tools expand inline when an object is selected. | — |
| **Form** | Activate form-fill mode. | — |
| **Draw** | Activate freehand drawing. | Colour picker, line weight (Fine / Medium / Thick) |
| **Erase** | Activate standalone eraser. | Eraser size (Sm / Md / Lg / XL / XXL) |
| **Text** | Activate text-box creation. Drag to draw a box; tap an existing box to edit. | Text colour, background colour, font size, bold |
| **Shape** | Draw the last-used shape type. Shape button icon updates to reflect the current type. | Shape picker (circle / rect / triangle), stroke colour, line weight |
| **Image** | Pick a photo from Camera or Photo Library (system crop tool included). | — |
| **Pencil** | Activate native Apple PencilKit mode. Tap **Done** to commit as an image overlay. | — |
| **Pages** | **Add** — insert a blank page after the current one. **Remove** — delete the current page (with confirmation). | — |
| **Settings** | Open the input-mode settings popover. | — |

#### Settings popover options

| Setting | Behaviour |
|---|---|
| **Pencil Only** | All annotation tools respond only to Apple Pencil. Finger touches scroll and zoom the document freely. |
| **Draw with Finger** | Single finger draws ink strokes. Two fingers scroll and zoom. Mutually exclusive with Pencil Only. |
| **Double Tap** | Action performed when the user double-taps the flat side of Apple Pencil 2 or Pro. Defaults to Toggle Eraser. |
| **Single Squeeze** | Action performed on a single squeeze of Apple Pencil Pro. Defaults to None. |
| **Double Squeeze** | Action performed on two quick squeezes of Apple Pencil Pro. Defaults to None. |

---

## Apple Pencil Gestures

Both the PDF Editor and Image Editor support configurable hardware gestures for compatible Apple Pencil models. Gesture assignments are shared between both editors and persisted to `UserDefaults` — users only need to configure them once.

### Supported hardware

| Gesture | Hardware |
|---|---|
| **Double Tap** | Apple Pencil 2, Apple Pencil Pro |
| **Single Squeeze** | Apple Pencil Pro |
| **Double Squeeze** | Apple Pencil Pro |

> Apple Pencil (1st generation) and Apple Pencil USB-C do not support any of these gestures. The settings remain visible in the UI so users can configure them in advance, but they will not fire on unsupported hardware.

### Assignable actions

Each gesture can be independently mapped to any of the following actions:

| Action | Description |
|---|---|
| **None** | The gesture does nothing. Multiple gestures may all be set to None. |
| **Toggle Eraser** | Switches between the Eraser tool and the Draw tool. Tap again to return. This mirrors the classic Apple Pencil double-tap convention. |
| **Select Tool** | Activates the Select tool. |
| **Draw Tool** | Activates the Draw (ink) tool. |
| **Eraser Tool** | Activates the Eraser tool directly, without toggling. |
| **Text Tool** | Activates the Text overlay tool. |
| **Shape Tool** | Activates the Shape tool using the last-used shape type. |
| **Switch to Last Tool** | Returns to whichever tool was active before the most recent tool change — useful for quickly flipping between two tools without gesture cycling. |
| **Undo** | Undoes the most recent action, equivalent to the toolbar Undo button. |
| **Redo** | Redoes the most recently undone action. |

### Conflict prevention

Each action (except None) can only be assigned to one gesture at a time. If you assign an action that is already claimed by another gesture, the previous assignment is automatically cleared. Actions already in use by another gesture are marked **(in use)** in the picker so you can see the conflict before committing.

### Configuring gestures

Open the **Settings** popover from the toolbar (gear icon) and scroll to the **Pencil Gestures** section. Each gesture has its own menu picker. Changes take effect immediately and are saved automatically.

### How double squeeze works

Apple's API does not expose a native double-squeeze event. The SDK implements it with a short timing window: if a second squeeze ends within 400 ms of the first, it is treated as a double squeeze and the single-squeeze action is suppressed. Squeezes separated by more than 400 ms each fire as independent single squeezes.

---

### Controlling which form fields are highlighted

By default the editor highlights every interactive form field. Fields are automatically skipped if either standard PDF flag is set:

- **`/Ff` bit 0 — ReadOnly**
- **`/F` bit 8 — Annotation Locked**

#### Custom highlight logic

```swift
PDFEditorView(
    url: documentURL,
    shouldHighlightFormField: { field in
        if field.isReadOnly || field.isAnnotationLocked { return false }
        return true
    }
)
```

Target specific fields by name:

```swift
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
| `fieldName` | `String?` | The field's internal name (`/T` key). |
| `isReadOnly` | `Bool` | `true` when `/Ff` bit 0 is set. |
| `isAnnotationLocked` | `Bool` | `true` when `/F` bit 8 is set. |

---

## Image Editor

### What it does

- Accepts any `UIImage` or raw `Data` as the canvas background
- **Freehand drawing** — Apple Pencil or finger, with adjustable colour and line weight
- **Standalone eraser** — dedicated tool with configurable size; no longer nested under the Draw tool
- **Text overlays** — drag-to-create text boxes with font size, bold, text colour, and background colour
- **Shape overlays** — circles, rectangles, and triangles; can be drawn over existing annotations
- **Image overlays** — pick from Camera or Photo Library, then drag and pinch-resize; configurable border
- **Apple PencilKit mode** — native PencilKit brushes captured as image overlays
- **Select mode** — tap to select any overlay, drag to move, resize, delete; configure image borders inline
- **Pencil-only annotation mode** — all annotation tools respond only to Apple Pencil; finger navigates freely
- **Draw with Finger mode** — single finger draws; two fingers scroll
- **Apple Pencil gesture mapping** — same configurable double-tap and squeeze actions as the PDF editor; shared settings apply to both
- **Tool settings persistence** — all settings are remembered between sessions
- All drawing and overlays are constrained to the image content area
- Full undo / redo (up to 50 steps)
- Export flattens everything into a single `UIImage`

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

```swift
ImageEditorView(
    image: photo,
    onSave: { savedImage in
        // Called when the user taps Save.
        // savedImage is a flattened UIImage with all annotations burned in.
        UIImageWriteToSavedPhotosAlbum(savedImage, nil, nil, nil)
    },
    onExport: { exportedImage in
        // Called when the user taps Share.
        // The share sheet is shown automatically.
        print("Exported: \(exportedImage.size)")
    }
)
```

Both callbacks are optional. Omitting `onSave` saves to `Documents/ImageEdits/`; omitting `onExport` still shows the share sheet.

### Initialising from `Data`

```swift
ImageEditorView(imageData: imageData) { exportedImage in
    // handle export
}
```

### Toolbar overview

| Section | Tap | Long-press settings |
|---|---|---|
| **Select** | Activate select mode. Sub-tools expand inline when an object is selected. | — |
| **Draw** | Activate freehand drawing. | Colour picker, line weight |
| **Erase** | Activate standalone eraser. | Eraser size |
| **Text** | Drag on the image to draw a text box. | Text colour, background colour, font size, bold |
| **Shape** | Draw the last-used shape type. | Shape picker, stroke colour, line weight |
| **Image** | Add a photo from Camera or Photo Library. | — |
| **Pencil** | Activate native PencilKit mode. | — |
| **Settings** | Open the input-mode and Pencil Gestures settings popover. | — |

---

## Changelog

### v2.1.0

- **Apple Pencil gesture mapping** — users can now assign custom actions to Apple Pencil hardware gestures directly from the Settings popover in both the PDF Editor and Image Editor. Three gestures are supported: **Double Tap** (Pencil 2 and Pro), **Single Squeeze** (Pencil Pro), and **Double Squeeze** (Pencil Pro). Each gesture can be independently mapped to Toggle Eraser, Switch to Last Tool, Select, Draw, Eraser, Text, Shape, Undo, Redo, or None.

- **Tool switching via gesture** — the new gesture actions include direct activation of Select, Draw, Eraser, Text, and Shape tools, plus a Switch to Last Tool action that returns to the previously active tool. Combined with Toggle Eraser this gives Pencil users fast one-handed tool swapping without touching the toolbar.

- **Conflict prevention** — each action (except None) can only be assigned to one gesture at a time. Assigning an action that is already used by another gesture automatically clears the previous assignment. Actions already in use are labelled **(in use)** in the picker.

- **Gesture settings persistence** — all three gesture assignments are saved to `UserDefaults` alongside existing tool preferences and restored automatically on next launch. Defaults: Double Tap → Toggle Eraser, Single Squeeze → None, Double Squeeze → None.

---

### v2.0.0

- **Standalone Eraser tool** — the eraser is now its own first-class tool (`EditorTool.erase`) in both editors. Tap **Erase** to activate; long-press to choose eraser size. It no longer lives inside the Draw tool's state, making it simpler and more predictable to activate.

- **Long-press toolbar popovers** — all tool buttons now use a tap-to-activate / long-press-to-configure interaction. Each tool's settings (colour, weight, shape type, font size, eraser size) open in a dedicated popover instead of an expanding inline row. This keeps the toolbar compact and always visible without horizontal scrolling through sub-tools.

- **Shape icon reflects current type** — the Shape button now shows the icon of the most recently used shape (circle, rectangle, or triangle) so you can re-draw the same shape without opening the popover.

- **Draw and Erase over existing annotations** — shapes and text boxes can now be created on top of existing overlay objects. Previously, starting a shape or text-box drag on top of an existing overlay was blocked.

- **Apple Pencil-only annotation mode** — a new **Settings** button in the toolbar opens an input-mode popover. Enabling **Pencil Only** restricts all annotation tools (draw, erase, shape, text) to Apple Pencil input. Finger touches scroll and zoom the document or image freely in all tool modes. This works correctly in text mode (pencil tap-to-edit, pencil drag-to-create; finger scrolls), shape mode (pencil draws, finger scrolls), and draw/erase mode.

- **Draw with Finger mode** — enabling **Draw with Finger** (mutually exclusive with Pencil Only) lets a single finger draw ink strokes while two fingers handle navigation.

- **Tool settings persistence** — all tool settings (ink colour, line weight, shape type, stroke colour, font size, eraser size, input mode) are persisted to `UserDefaults` and restored automatically the next time the editor is opened. Users no longer need to reconfigure their tools on each launch.

- **Select tool preserved** — the Select tool's inline sub-tool row (colour, weight, border controls) is unchanged. Contextual controls still expand horizontally when an overlay is selected.

---

### v1.x

- **Apple PencilKit mode** (PDF Editor) — native `PKCanvasView` overlay with the full PencilKit brush library. Tapping **Done** commits the drawing as a transparent PNG image overlay, integrated with undo/redo and flattened export.

- **2-finger navigation in all annotation modes** — scrolling and pinch-to-zoom with two fingers works consistently in draw, shape, text, select, and PencilKit modes.

- **Page management** (PDF Editor) — **Add** inserts a blank page after the current one; **Remove** deletes the current page with confirmation. Both are fully undoable.

- **Image borders** — image overlays in both editors support configurable border width and colour, burned into the flattened export.

- **Shape overlays** — circle, rectangle, and triangle shapes as vector overlays in both the PDF and Image editors, with stroke colour and line weight controls and full undo/redo.

- **White background for text boxes** — the background-colour picker for text boxes includes a White option.

- **Text mode tap behaviour** — tapping an existing text box immediately opens it for editing; tapping outside deselects and readies the canvas for a new box.

- **PDF metadata preservation** — document title, author, and keyword metadata are retained through save and export operations.
