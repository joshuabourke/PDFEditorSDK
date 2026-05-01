//
//  File.swift
//  PDFEditorSDK
//
//  Created by Josh Bourke on 9/4/2026.
//

import SwiftUI
// MARK: - View Model

@MainActor
@Observable
class ImageEditorViewModel {
    private var preferences: EditorPreferences
    
    let sourceImage: UIImage
    var activeTool: EditorTool = .draw
    
    var inkColor: UIColor {
        didSet { preferences.inkColor = RGBAColor(inkColor); preferences.save()}
    }
    var inkLineWidth: CGFloat {
        didSet { preferences.inkLineWidth = inkLineWidth; preferences.save()}
    }
    var isEraserMode: Bool { activeTool == .erase }
    var eraserRadius: CGFloat {
        didSet { preferences.eraserRadius = eraserRadius; preferences.save()}
    }
    var textBoxBackgroundColor: UIColor {
        didSet { preferences.textBoxBackgroundColor = RGBAColor(textBoxBackgroundColor); preferences.save()}
    }
    var textBoxFontSize: CGFloat {
        didSet { preferences.textBoxFontSize = textBoxFontSize; preferences.save()}
    }
    var textBoxIsBold: Bool {
        didSet { preferences.textBoxIsBold = textBoxIsBold; preferences.save()}
    }
    var textBoxTextColor: UIColor {
        didSet { preferences.textBoxTextColor = RGBAColor(textBoxTextColor); preferences.save()}
    }
    var textBoxTextAlignment: NSTextAlignment {
        didSet { preferences.textBoxTextAlignment = textBoxTextAlignment.rawValue; preferences.save()}
    }
    var textBoxVerticalAlignment: TextVerticalAlignment {
        didSet { preferences.textBoxVerticalAlignment = textBoxVerticalAlignment.rawValue; preferences.save()}
    }
    var textBoxAutoResize: Bool {
        didSet { preferences.textBoxAutoResize = textBoxAutoResize; preferences.save() }
    }
    var textBoxBorderWidth: CGFloat {
        didSet { preferences.textBoxBorderWidth = textBoxBorderWidth; preferences.save() }
    }
    var textBoxBorderColor: UIColor {
        didSet { preferences.textBoxBorderColor = RGBAColor(textBoxBorderColor); preferences.save() }
    }
    var selectedTextBoxAutoResize: Bool = false
    var selectedTextBoxBorderWidth: CGFloat = 0
    var selectedTextBoxBorderColor: UIColor = .black
    var activeShapeKind: OverlayShapeKind {
        didSet { preferences.activeShapeKind = activeShapeKind; preferences.save()}
    }
    var shapeStrokeColor: UIColor {
        didSet { preferences.shapeStrokeColor = RGBAColor(shapeStrokeColor); preferences.save()}
    }
    var shapeLineWidth: CGFloat {
        didSet { preferences.shapeLineWidth = shapeLineWidth; preferences.save()}
    }
    var imageBorderWidth: CGFloat {
        didSet { preferences.imageBorderWidth = imageBorderWidth; preferences.save()}
    }
    var imageBorderColor: UIColor {
        didSet { preferences.imageBorderColor = RGBAColor(imageBorderColor); preferences.save()}
    }
    var drawWithFinger: Bool {
        didSet { preferences.drawWithFinger = drawWithFinger; preferences.save() }
    }
    var pencilOnlyAnnotations: Bool {
        didSet { preferences.pencilOnlyAnnotations = pencilOnlyAnnotations; preferences.save() }
    }
    var pencilDoubleTapAction: PencilGestureAction {
        didSet { preferences.pencilDoubleTapAction = pencilDoubleTapAction; preferences.save() }
    }
    var pencilSqueezeAction: PencilGestureAction {
        didSet { preferences.pencilSqueezeAction = pencilSqueezeAction; preferences.save() }
    }
    var pencilDoubleSqueezeAction: PencilGestureAction {
        didSet { preferences.pencilDoubleSqueezeAction = pencilDoubleSqueezeAction; preferences.save() }
    }
    var toolbarCompact: Bool {
        didSet { preferences.toolbarCompact = toolbarCompact; preferences.save() }
    }
    var lineWidthInputStyle: LineWidthInputStyle {
        didSet { preferences.lineWidthInputStyle = lineWidthInputStyle; preferences.save() }
    }
    var lineWidthStep: CGFloat {
        didSet {
            var p = preferences
            p.lineWidthStep = lineWidthStep
            p.normalizeLineWidthControlFields()
            if p.lineWidthStep != lineWidthStep {
                lineWidthStep = p.lineWidthStep
                return
            }
            preferences.lineWidthStep = p.lineWidthStep
            preferences.save()
        }
    }
    var lineWidthMax: CGFloat {
        didSet {
            var p = preferences
            p.lineWidthMax = lineWidthMax
            p.normalizeLineWidthControlFields()
            if p.lineWidthMax != lineWidthMax {
                lineWidthMax = p.lineWidthMax
                return
            }
            preferences.lineWidthMax = p.lineWidthMax
            preferences.save()
        }
    }
    var previousTool: EditorTool? = nil

    var hasSelectedOverlayObject: Bool = false
    var showImageSourceDialog: Bool = false
    var saveStatus: String?
    var hasUnsavedChanges: Bool = false
    var undoStack: [ImageUndoAction] = []
    var redoStack: [ImageUndoAction] = []
    weak var canvasView: DrawingImageView?
    private let onSave: ((UIImage) -> Void)?
    private let onExport: ((UIImage) -> Void)?
    private let maxUndoActions = 50
    
    var selectedOverlayKind: SelectedOverlayKind?

    var isDrawingMode: Bool { activeTool == .draw }
    var isTextMode: Bool { activeTool == .text }
    var isSelectMode: Bool { activeTool == .select }
    var isShapeMode: Bool { activeTool == .shape }
    var isPencilKitMode: Bool { activeTool == .pencilKit }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    init(sourceImage: UIImage, onSave: ((UIImage) -> Void)? = nil, onExport: ((UIImage) -> Void)? = nil) {
        self.sourceImage = sourceImage
        self.onSave = onSave
        self.onExport = onExport
        
        let prefs = EditorPreferences.load()
        self.preferences = prefs
        
        self.inkColor = prefs.inkColor.uiColor
        self.inkLineWidth = prefs.inkLineWidth
        
        self.eraserRadius = prefs.eraserRadius
        
        self.textBoxBackgroundColor = prefs.textBoxBackgroundColor.uiColor
        self.textBoxIsBold = prefs.textBoxIsBold
        self.textBoxTextColor = prefs.textBoxTextColor.uiColor
        self.textBoxFontSize = prefs.textBoxFontSize
        self.textBoxTextAlignment = NSTextAlignment(rawValue: prefs.textBoxTextAlignment) ?? .left
        self.textBoxVerticalAlignment = TextVerticalAlignment(rawValue: prefs.textBoxVerticalAlignment) ?? .top
        self.textBoxAutoResize = prefs.textBoxAutoResize
        self.textBoxBorderWidth = prefs.textBoxBorderWidth
        self.textBoxBorderColor = prefs.textBoxBorderColor.uiColor

        self.activeShapeKind = prefs.activeShapeKind
        self.shapeLineWidth = prefs.shapeLineWidth
        self.shapeStrokeColor = prefs.shapeStrokeColor.uiColor
        
        self.imageBorderWidth = prefs.imageBorderWidth
        self.imageBorderColor = prefs.imageBorderColor.uiColor

        self.drawWithFinger = prefs.drawWithFinger
        self.pencilOnlyAnnotations = prefs.pencilOnlyAnnotations
        self.pencilDoubleTapAction     = prefs.pencilDoubleTapAction
        self.pencilSqueezeAction       = prefs.pencilSqueezeAction
        self.pencilDoubleSqueezeAction = prefs.pencilDoubleSqueezeAction
        self.toolbarCompact = prefs.toolbarCompact

        self.lineWidthInputStyle = prefs.lineWidthInputStyle
        self.lineWidthStep = prefs.lineWidthStep
        self.lineWidthMax = prefs.lineWidthMax
    }

    func setTool(_ tool: EditorTool) {
        // Tapping an already-active tool returns to select mode
        if activeTool == tool, tool != .select {
            previousTool = activeTool
            activeTool = .select
            canvasView?.endTextEditing()
            return
        }
        if tool == .shape {
            previousTool = activeTool
            activeTool = .shape
            canvasView?.endTextEditing()
            canvasView?.deselectAll()
            return
        }
        if tool == .pencilKit {
            previousTool = activeTool
            activeTool = .pencilKit
            canvasView?.endTextEditing()
            canvasView?.deselectAll()
            return
        }
        if tool != .text {
            canvasView?.endTextEditing()
        }
        previousTool = activeTool
        activeTool = tool
        if tool != .select {
            canvasView?.deselectAll()
        }
    }

    func applyShapeStyleToSelected() {
        canvasView?.applyShapeStyleToSelected(kind: activeShapeKind, strokeColor: shapeStrokeColor, lineWidth: shapeLineWidth)
    }

    func applyImageBorderToSelected() {
        canvasView?.applyImageBorderToSelected(borderWidth: imageBorderWidth, borderColor: imageBorderColor)
    }

    func applyTextBorderToSelected() {
        canvasView?.applyTextBorderToSelected(borderWidth: selectedTextBoxBorderWidth, borderColor: selectedTextBoxBorderColor)
    }

    func commitSelectedTextBoxBorderWidth(_ width: CGFloat) {
        selectedTextBoxBorderWidth = width
        applyTextBorderToSelected()
    }

    func commitSelectedTextBoxBorderColor(_ color: UIColor) {
        selectedTextBoxBorderColor = color
        applyTextBorderToSelected()
    }

    func toggleSelectedTextBoxAutoResize() {
        selectedTextBoxAutoResize.toggle()
        applyAutoResizeToSelectedTextBox()
    }

    func applyAutoResizeToSelectedTextBox() {
        canvasView?.setSelectedTextBoxAutoResize(selectedTextBoxAutoResize)
    }

    func commitImageBorderWidth(_ width: CGFloat) {
        imageBorderWidth = width
        applyImageBorderToSelected()
    }

    func commitImageBorderColor(_ color: UIColor) {
        imageBorderColor = color
        applyImageBorderToSelected()
    }

    func addOverlayImage(_ image: UIImage) {
        canvasView?.addOverlayImage(image)
    }

    func deleteSelectedObject() {
        canvasView?.deleteSelected()
    }

    func applyTextStyleToSelected() {
        canvasView?.applyTextStyle(
            fontSize: textBoxFontSize,
            isBold: textBoxIsBold,
            textColor: textBoxTextColor,
            backgroundColor: textBoxBackgroundColor,
            textAlignment: textBoxTextAlignment,
            verticalAlignment: textBoxVerticalAlignment
        )
    }

    func saveImage() {
        guard let image = canvasView?.renderToImage() else {
            saveStatus = "Failed to render image"
            return
        }

        if let onSave {
            onSave(image)
            saveStatus = "Image saved"
            hasUnsavedChanges = false
            return
        }

        // Default: save as JPEG to Documents/ImageEdits/
        guard let data = image.jpegData(compressionQuality: 0.92) else {
            saveStatus = "Failed to encode image"
            return
        }

        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = documents.appendingPathComponent("ImageEdits", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let fileName = "Image-\(Int(Date().timeIntervalSince1970)).jpg"
            let destination = folder.appendingPathComponent(fileName)
            try data.write(to: destination)
            saveStatus = "Saved to: \(fileName)"
            hasUnsavedChanges = false
        } catch {
            saveStatus = "Failed to save image"
        }
    }

    @discardableResult
    func exportImage() -> UIImage? {
        guard let image = canvasView?.renderToImage() else { return nil }
        onExport?(image)
        return image
    }

    func didMakeChange(_ action: ImageUndoAction) {
        let resolved = resolveActionIfNeeded(action)
        undoStack.append(resolved)
        if undoStack.count > maxUndoActions {
            undoStack.removeFirst(undoStack.count - maxUndoActions)
        }
        redoStack.removeAll()
        hasUnsavedChanges = true
    }

    func undo() {
        guard let action = undoStack.popLast() else { return }
        let resolved = resolveActionIfNeeded(action)
        redoStack.append(resolved)
        performUndo(resolved)
    }

    func redo() {
        guard let action = redoStack.popLast() else { return }
        undoStack.append(action)
        performRedo(action)
    }

    private func resolveActionIfNeeded(_ action: ImageUndoAction) -> ImageUndoAction {
        switch action {
        case .textBox(let add, let remove):
            if let add, let current = canvasView?.textBoxState(id: add.id) {
                return .textBox(add: current, remove: remove)
            }
            return action
        case .imageBox(let add, let remove):
            if let add, let current = canvasView?.imageBoxState(id: add.id) {
                return .imageBox(add: current, remove: remove)
            }
            return action
        case .imageShape(let add, let remove):
            if let add, let current = canvasView?.shapeBoxState(id: add.id) {
                return .imageShape(add: current, remove: remove)
            }
            return action
        case .textBoxUpdate(let before, let after):
            if let current = canvasView?.textBoxState(id: after.id) {
                return .textBoxUpdate(before: before, after: current)
            }
            return action
        default:
            return action
        }
    }

    private func performUndo(_ action: ImageUndoAction) {
        switch action {
        case .stroke(let add, let remove):
            if let add {
                canvasView?.removeStroke(id: add.id)
            }
            if let remove {
                canvasView?.addStroke(remove)
            }
        case .eraseSession(let old, let new):
            canvasView?.replaceStrokes(remove: new, add: old)
        case .textBox(let add, let remove):
            if let add {
                canvasView?.removeTextBox(id: add.id)
            }
            if let remove {
                canvasView?.addTextBox(from: remove, beginEditing: false)
            }
        case .textBoxUpdate(let before, _):
            canvasView?.updateTextBox(from: before)
        case .imageBox(let add, let remove):
            if let add {
                canvasView?.removeImageBox(id: add.id)
            }
            if let remove {
                canvasView?.addImageBox(from: remove)
            }
        case .imageBoxUpdate(let before, _):
            canvasView?.updateImageBox(from: before)
        case .imageShape(let add, let remove):
            if let add { canvasView?.removeShapeBox(id: add.id) }
            if let remove { canvasView?.addShapeBox(from: remove) }
        case .imageShapeUpdate(let before, _):
            canvasView?.updateShapeBox(from: before)
        }
    }

    private func performRedo(_ action: ImageUndoAction) {
        switch action {
        case .stroke(let add, let remove):
            if let add {
                canvasView?.addStroke(add)
            }
            if let remove {
                canvasView?.removeStroke(id: remove.id)
            }
        case .eraseSession(let old, let new):
            canvasView?.replaceStrokes(remove: old, add: new)
        case .textBox(let add, let remove):
            if let add {
                canvasView?.addTextBox(from: add, beginEditing: false)
            }
            if let remove {
                canvasView?.removeTextBox(id: remove.id)
            }
        case .textBoxUpdate(_, let after):
            canvasView?.updateTextBox(from: after)
        case .imageBox(let add, let remove):
            if let add {
                canvasView?.addImageBox(from: add)
            }
            if let remove {
                canvasView?.removeImageBox(id: remove.id)
            }
        case .imageBoxUpdate(_, let after):
            canvasView?.updateImageBox(from: after)
        case .imageShape(let add, let remove):
            if let add { canvasView?.addShapeBox(from: add) }
            if let remove { canvasView?.removeShapeBox(id: remove.id) }
        case .imageShapeUpdate(_, let after):
            canvasView?.updateShapeBox(from: after)
        }
    }
}

// MARK: - PencilGestureHandler Conformance
extension ImageEditorViewModel: PencilGestureHandler {}

// MARK: - ImageUndoAction

enum ImageUndoAction {
    case stroke(add: InkStroke?, remove: InkStroke?)
    case eraseSession(old: [InkStroke], new: [InkStroke])
    case textBox(add: OverlayTextBoxState?, remove: OverlayTextBoxState?)
    case textBoxUpdate(before: OverlayTextBoxState, after: OverlayTextBoxState)
    case imageBox(add: OverlayImageState?, remove: OverlayImageState?)
    case imageBoxUpdate(before: OverlayImageState, after: OverlayImageState)
    case imageShape(add: OverlayShapeState?, remove: OverlayShapeState?)
    case imageShapeUpdate(before: OverlayShapeState, after: OverlayShapeState)
}
