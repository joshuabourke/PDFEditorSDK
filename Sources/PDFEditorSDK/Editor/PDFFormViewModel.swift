//
//  PDFFormViewModel.swift
//  PDFEditorSDK
//
//  Extracted from PDFEditorView.swift
//

import SwiftUI
import PDFKit
import UIKit
import CoreText

// MARK: - View Model
@MainActor
@Observable
class PDFFormViewModel {
    private var preferences: EditorPreferences
    
    var pdfDocument: PDFDocument?
    var activeTool: EditorTool = .form
    var undoStack: [UndoAction] = []
    var redoStack: [UndoAction] = []
    var pageScrollLocked: Bool = false
    var hasTextSelection: Bool = false
    var hasSelectedInkAnnotation: Bool = false
    var hasSelectedOverlayObject: Bool = false
    weak var pdfView: DrawingPDFView?
    var inkColor: UIColor {
        didSet { preferences.inkColor = RGBAColor(inkColor); preferences.save()}
    }
    var inkLineWidth: CGFloat {
        didSet { preferences.inkLineWidth = inkLineWidth; preferences.save()}
    }
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
    var previousTool: EditorTool? = nil
    var isThumbnailOverlayVisible: Bool = true
    var saveStatus: String?
    var exportStatus: String?
    var openStatus: String?
    var currentDocumentURL: URL?
    var lastSavedURL: URL?
    private let maxUndoActions = 50
    private var didLoadOverlayMetadata = false
    var needsOverlayRestore = false
    var currentPageIndex: Int = 0
    var pageCount: Int = 0
    
    /// When true, the image picker result is placed into the tapped PDF form widget instead of a free overlay.
    var imagePickIsForFormWidget = false
    var showFormWidgetImageSourceDialog = false
    private var pendingFormWidgetPageIndex: Int?
    private var pendingFormWidgetAnnotation: PDFAnnotation?
    private let editableSaveHandler: PDFEditorFileHandler?
    private let flattenedExportHandler: PDFEditorFileHandler?
    let shouldHighlightFormField: ((PDFFormFieldInfo) -> Bool)?

    init(
        documentURL: URL,
        editableSaveHandler: PDFEditorFileHandler? = nil,
        flattenedExportHandler: PDFEditorFileHandler? = nil,
        shouldHighlightFormField: ((PDFFormFieldInfo) -> Bool)? = nil
    ) {
        self.editableSaveHandler = editableSaveHandler
        self.flattenedExportHandler = flattenedExportHandler
        self.shouldHighlightFormField = shouldHighlightFormField
        
        let prefs = EditorPreferences.load()
        self.preferences = prefs
        
        self.inkColor = prefs.inkColor.uiColor
        self.inkLineWidth = prefs.inkLineWidth
        
        self.eraserRadius = prefs.eraserRadius
        
        self.textBoxBackgroundColor = prefs.textBoxBackgroundColor.uiColor
        self.textBoxFontSize = prefs.textBoxFontSize
        self.textBoxIsBold = prefs.textBoxIsBold
        self.textBoxTextColor = prefs.textBoxTextColor.uiColor
        self.textBoxTextAlignment = NSTextAlignment(rawValue: prefs.textBoxTextAlignment) ?? .left
        self.textBoxVerticalAlignment = TextVerticalAlignment(rawValue: prefs.textBoxVerticalAlignment) ?? .top
        self.textBoxAutoResize = prefs.textBoxAutoResize

        self.activeShapeKind = prefs.activeShapeKind
        self.shapeStrokeColor = prefs.shapeStrokeColor.uiColor
        self.shapeLineWidth = prefs.shapeLineWidth
        
        self.imageBorderWidth = prefs.imageBorderWidth
        self.imageBorderColor = prefs.imageBorderColor.uiColor

        self.drawWithFinger = prefs.drawWithFinger
        self.pencilOnlyAnnotations = prefs.pencilOnlyAnnotations
        self.pencilDoubleTapAction = prefs.pencilDoubleTapAction
        self.pencilSqueezeAction = prefs.pencilSqueezeAction
        self.pencilDoubleSqueezeAction = prefs.pencilDoubleSqueezeAction

        _ = loadPDF(from: documentURL)
        
    }
    
    var selectedOverlayKind: SelectedOverlayKind?
    /// Persisted default applied to every newly drawn text box.
    var textBoxAutoResize: Bool {
        didSet { preferences.textBoxAutoResize = textBoxAutoResize; preferences.save() }
    }
    /// Reflects the auto-resize state of the currently selected text box (not persisted).
    var selectedTextBoxAutoResize: Bool = false

    var isDrawingMode: Bool { activeTool == .draw }
    var isEraserMode: Bool { activeTool == .erase }
    var isTextMode: Bool { activeTool == .text }
    var isSelectMode: Bool { activeTool == .select }
    var isShapeMode: Bool { activeTool == .shape }
    var isPencilKitMode: Bool { activeTool == .pencilKit }
    
    @discardableResult
    func loadPDF(from url: URL) -> Bool {
        currentDocumentURL = url
        pdfDocument = PDFDocument(url: url)
        guard pdfDocument != nil else {
            openStatus = "Failed to open PDF"
            return false
        }
        didLoadOverlayMetadata = false
        needsOverlayRestore = true
        updatePageMetrics()
        return true
    }
    
    func setTool(_ tool: EditorTool) {
        // Tapping an already-active tool returns to select mode
        if activeTool == tool, tool != .select {
            previousTool = activeTool
            activeTool = .select
            pdfView?.endOverlayTextEditing()

            return
        }
        if tool == .shape {
            previousTool = activeTool
            activeTool = .shape
            pdfView?.endOverlayTextEditing()
            hasSelectedInkAnnotation = false
            pdfView?.deselectInkAnnotation()
            pdfView?.deselectOverlaySelection()
            return
        }
        if tool == .pencilKit {
            previousTool = activeTool
            activeTool = .pencilKit
            pdfView?.endOverlayTextEditing()
            hasSelectedInkAnnotation = false
            pdfView?.deselectInkAnnotation()
            pdfView?.deselectOverlaySelection()
            return
        }
        if tool != .text {
            pdfView?.endOverlayTextEditing()
        }
        previousTool = activeTool
        activeTool = tool
        if tool != .select {
            hasSelectedInkAnnotation = false
            pdfView?.deselectInkAnnotation()
            pdfView?.deselectOverlaySelection()
        }
    }

    func applyShapeStyleToSelected() {
        pdfView?.applyShapeStyleToSelected(strokeColor: shapeStrokeColor, lineWidth: shapeLineWidth)
    }

    func applyImageBorderToSelected() {
        pdfView?.applyImageBorderToSelected(borderWidth: imageBorderWidth, borderColor: imageBorderColor)
    }
    
    func toggleScrollLock() {
        pageScrollLocked.toggle()
    }
    
    func highlightSelectedText() {
        pdfView?.highlightCurrentSelection()
    }
    
    func addAnnotation(_ annotation: PDFAnnotation) {
        didMakeChange(.annotation(annotation))
    }
    
    func recordFormFieldChange(annotation: PDFAnnotation, previousValue: String?, newValue: String?) {
        didMakeChange(.formFieldChange(annotation: annotation, previousValue: previousValue, newValue: newValue))
    }
    
    func addImage(_ image: UIImage) {
        pdfView?.addOverlayImage(image)
    }
    
    func presentFormWidgetImageSourceChoice(pageIndex: Int, annotation: PDFAnnotation) {
        pendingFormWidgetPageIndex = pageIndex
        pendingFormWidgetAnnotation = annotation
        showFormWidgetImageSourceDialog = true
    }
    
    func cancelPendingFormWidgetImagePick() {
        pendingFormWidgetPageIndex = nil
        pendingFormWidgetAnnotation = nil
        imagePickIsForFormWidget = false
    }
    
    func beginFormWidgetImagePickFromCamera() {
        imagePickIsForFormWidget = true
        showFormWidgetImageSourceDialog = false
    }
    
    func beginFormWidgetImagePickFromLibrary() {
        imagePickIsForFormWidget = true
        showFormWidgetImageSourceDialog = false
    }
    
    func handleImagePickedFromSheet(_ image: UIImage?) {
        if imagePickIsForFormWidget {
            let pageIndex = pendingFormWidgetPageIndex
            let annotation = pendingFormWidgetAnnotation
            imagePickIsForFormWidget = false
            pendingFormWidgetPageIndex = nil
            pendingFormWidgetAnnotation = nil
            guard let image,
                  let pageIndex,
                  let annotation,
                  let page = pdfDocument?.page(at: pageIndex) else { return }
            pdfView?.addOverlayImage(image, forFormWidget: annotation, on: page)
            return
        }
        if let image {
            addImage(image)
        }
    }
    
    func applyTextStyleToSelectedTextBox() {
        pdfView?.applyTextStyleToSelectedTextBox(
            fontSize: textBoxFontSize,
            isBold: textBoxIsBold,
            textColor: textBoxTextColor,
            backgroundColor: textBoxBackgroundColor,
            textAlignment: textBoxTextAlignment,
            verticalAlignment: textBoxVerticalAlignment
        )
    }

    func applyAutoResizeToSelectedTextBox() {
        pdfView?.setSelectedTextBoxAutoResize(selectedTextBoxAutoResize)
    }
    
    func updatePageMetrics() {
        pageCount = pdfDocument?.pageCount ?? 0
        if let page = pdfView?.currentPage, let document = pdfDocument {
            currentPageIndex = document.index(for: page)
        } else {
            currentPageIndex = 0
        }
    }
    
    func goToPage(index: Int) {
        guard let document = pdfDocument, index >= 0, index < document.pageCount else { return }
        if let page = document.page(at: index) {
            pdfView?.go(to: page)
            currentPageIndex = index
        }
    }
    
    func goToNextPage() {
        goToPage(index: currentPageIndex + 1)
    }
    
    func goToPreviousPage() {
        goToPage(index: currentPageIndex - 1)
    }
    
    func removeCurrentPage() {
        guard let document = pdfDocument, document.pageCount > 1 else { return }
        let index = currentPageIndex
        guard let page = document.page(at: index) else { return }
        document.removePage(at: index)
        updatePageMetrics()
        goToPage(index: max(0, index - 1))
        didMakeChange(.removePage(page: page, at: index))
    }

    func addBlankPage(at insertIndex: Int) {
        guard let document = pdfDocument else { return }
        let pageSize = pdfView?.currentPage?.bounds(for: .mediaBox).size ?? CGSize(width: 612, height: 792)
        let renderer = UIGraphicsImageRenderer(size: pageSize)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: pageSize))
        }
        guard let page = PDFPage(image: image) else { return }
        let safeInsertIndex = max(0, min(insertIndex, document.pageCount))
        document.insert(page, at: safeInsertIndex)
        updatePageMetrics()
        goToPage(index: safeInsertIndex)
        didMakeChange(.addPage(page: page, at: safeInsertIndex))
    }
    
    func restoreOverlaysIfNeeded() {
        guard !didLoadOverlayMetadata else { return }
        pdfView?.readOverlayMetadata()
        didLoadOverlayMetadata = true
    }
    
    func undo() {
        guard let action = undoStack.popLast() else { return }
        let resolved = resolveOverlayStateIfNeeded(action)
        redoStack.append(resolved)
        performUndoAction(resolved)
    }
    
    func redo() {
            guard let action = redoStack.popLast() else { return }
            undoStack.append(action)
            
            performRedoAction(action)
        }

    private func resolveOverlayStateIfNeeded(_ action: UndoAction) -> UndoAction {
        switch action {
        case .overlayTextBox(let add, let remove):
            if let add, let current = pdfView?.overlayTextBoxState(id: add.id) {
                return .overlayTextBox(add: current, remove: remove)
            }
            return action
        case .overlayImage(let add, let remove):
            if let add, let current = pdfView?.overlayImageState(id: add.id) {
                return .overlayImage(add: current, remove: remove)
            }
            return action
        case .overlayShape(let add, let remove):
            if let add, let current = pdfView?.overlayShapeState(id: add.id) {
                return .overlayShape(add: current, remove: remove)
            }
            return action
        default:
            return action
        }
    }
    
    private func performUndoAction(_ action: UndoAction) {
            switch action {
            case .annotation(let ann):
                ann.page?.removeAnnotation(ann)
            case .formFieldChange(let ann, let prev, _):
                ann.widgetStringValue = prev
            case .drawingSession(let page, let old, let new):
                if let sel = pdfView?.selectedInkAnnotation, new.contains(where: { $0 === sel }) {
                    pdfView?.deselectInkAnnotation()
                }
                new.forEach { page.removeAnnotation($0) }
                old.forEach { page.addAnnotation($0) }
            case .overlayTextBox(let add, let remove):
                if let add {
                    pdfView?.removeOverlayTextBox(id: add.id)
                }
                if let remove {
                    pdfView?.addOverlayTextBox(from: remove)
                }
            case .moveAnnotation(let ann, let from, _):
                pdfView?.suppressGoTo = true
                ann.bounds = from
                pdfView?.suppressGoTo = false
                if pdfView?.selectedInkAnnotation === ann {
                    pdfView?.deselectInkAnnotation()
                }
            case .overlayImage(let add, let remove):
                if let add {
                    pdfView?.removeOverlayImage(id: add.id)
                }
                if let remove {
                    pdfView?.addOverlayImage(from: remove)
                }
            case .overlayImageUpdate(let before, _):
                pdfView?.updateOverlayImage(from: before)
            case .deleteInkAnnotation(let ann, let page):
                page.addAnnotation(ann)
            case .overlayShape(let add, let remove):
                if let add { pdfView?.removeOverlayShape(id: add.id) }
                if let remove { pdfView?.addOverlayShape(from: remove) }
            case .overlayShapeUpdate(let before, _):
                pdfView?.updateOverlayShape(from: before)
            case .addPage(_, let at):
                guard let document = pdfDocument else { return }
                document.removePage(at: at)
                updatePageMetrics()
                goToPage(index: max(0, at - 1))
            case .removePage(let page, let at):
                guard let document = pdfDocument else { return }
                let safeIndex = max(0, min(at, document.pageCount))
                document.insert(page, at: safeIndex)
                updatePageMetrics()
                goToPage(index: safeIndex)
            }
        }

    private func performRedoAction(_ action: UndoAction) {
            switch action {
            case .annotation(let ann):
                ann.page?.addAnnotation(ann)
            case .formFieldChange(let ann, _, let newValue):
                ann.widgetStringValue = newValue
            case .drawingSession(let page, let old, let new):
                old.forEach { page.removeAnnotation($0) }
                new.forEach { page.addAnnotation($0) }
            case .overlayTextBox(let add, let remove):
                if let add {
                    pdfView?.addOverlayTextBox(from: add)
                }
                if let remove {
                    pdfView?.removeOverlayTextBox(id: remove.id)
                }
            case .moveAnnotation(let ann, _, let to):
                pdfView?.suppressGoTo = true
                ann.bounds = to
                pdfView?.suppressGoTo = false
                if pdfView?.selectedInkAnnotation === ann {
                    pdfView?.deselectInkAnnotation()
                }
            case .overlayImage(let add, let remove):
                if let add {
                    pdfView?.addOverlayImage(from: add)
                }
                if let remove {
                    pdfView?.removeOverlayImage(id: remove.id)
                }
            case .overlayImageUpdate(_, let after):
                pdfView?.updateOverlayImage(from: after)
            case .deleteInkAnnotation(let ann, let page):
                page.removeAnnotation(ann)
                if pdfView?.selectedInkAnnotation === ann {
                    pdfView?.deselectInkAnnotation()
                }
            case .overlayShape(let add, let remove):
                if let add { pdfView?.addOverlayShape(from: add) }
                if let remove { pdfView?.removeOverlayShape(id: remove.id) }
            case .overlayShapeUpdate(_, let after):
                pdfView?.updateOverlayShape(from: after)
            case .addPage(let page, let at):
                guard let document = pdfDocument else { return }
                let safeIndex = max(0, min(at, document.pageCount))
                document.insert(page, at: safeIndex)
                updatePageMetrics()
                goToPage(index: safeIndex)
            case .removePage(_, let at):
                guard let document = pdfDocument else { return }
                guard at < document.pageCount else { return }
                document.removePage(at: at)
                updatePageMetrics()
                goToPage(index: max(0, at - 1))
            }
        }
    
    
    // Call this whenever a fresh change is made to clear the redo stack
    func didMakeChange(_ action: UndoAction) {
        undoStack.append(action)
        if undoStack.count > maxUndoActions {
            undoStack.removeFirst(undoStack.count - maxUndoActions)
        }
        redoStack.removeAll()
    }
    
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    
    func deleteSelectedSelection() {
        if hasSelectedInkAnnotation {
            deleteSelectedInkAnnotation()
        } else {
            pdfView?.deleteSelectedOverlayObject()
        }
    }
    
    func deleteSelectedInkAnnotation() {
        guard let pdfView, let annotation = pdfView.selectedInkAnnotation,
              let page = annotation.page else { return }
        page.removeAnnotation(annotation) 
        pdfView.deselectInkAnnotation()
        didMakeChange(.deleteInkAnnotation(annotation: annotation, page: page))
    }
    
    @discardableResult
    func savePDF() -> URL? {
        guard let document = pdfDocument else { return nil }
        
        pdfView?.writeOverlayMetadata()

        let fileName = defaultFileName(for: .editable)
        let stagingURL = stagingURL(fileName: fileName)
        try? FileManager.default.createDirectory(
            at: stagingURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )

        guard document.write(to: stagingURL) else {
            saveStatus = "Failed to save PDF"
            return nil
        }

        do {
            let finalURL = try finalizeGeneratedFile(
                at: stagingURL,
                request: PDFEditorFileRequest(
                    kind: .editable,
                    sourceURL: currentDocumentURL,
                    temporaryURL: stagingURL,
                    suggestedFileName: fileName
                ),
                handler: editableSaveHandler
            )
            currentDocumentURL = finalURL
            lastSavedURL = finalURL
            saveStatus = "Saved to: \(finalURL.lastPathComponent)"
            return finalURL
        } catch {
            saveStatus = "Failed to save PDF"
            return nil
        }
    }
    
    func exportFlattenedPDF() -> URL? {
        guard let document = pdfDocument else {
            exportStatus = "No overlays to export"
            return nil
        }
        guard let metadata = pdfView?.overlayMetadataSnapshot() else {
            exportStatus = "No overlays to export"
            return nil
        }

        let fileName = defaultFileName(for: .flattened)
        let stagingURL = stagingURL(fileName: fileName)
        try? FileManager.default.createDirectory(
            at: stagingURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )

        guard renderFlattenedPDF(document: document, metadata: metadata, destinationURL: stagingURL) else {
            exportStatus = "Failed to export PDF"
            return nil
        }

        do {
            let finalURL = try finalizeGeneratedFile(
                at: stagingURL,
                request: PDFEditorFileRequest(
                    kind: .flattened,
                    sourceURL: currentDocumentURL,
                    temporaryURL: stagingURL,
                    suggestedFileName: fileName
                ),
                handler: flattenedExportHandler
            )
            exportStatus = "Exported to: \(finalURL.lastPathComponent)"
            return finalURL
        } catch {
            exportStatus = "Failed to export PDF"
            return nil
        }
    }
    
    private func renderFlattenedPDF(
        document: PDFDocument,
        metadata: OverlayDocumentMetadata,
        destinationURL: URL
    ) -> Bool {
        guard document.pageCount > 0 else { return false }
        let firstBounds = document.page(at: 0)?.bounds(for: .mediaBox) ?? CGRect(x: 0, y: 0, width: 612, height: 792)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfDocumentInfo(from: document)
        let renderer = UIGraphicsPDFRenderer(bounds: firstBounds, format: format)
        
        do {
            try renderer.writePDF(to: destinationURL) { context in
                for pageIndex in 0..<document.pageCount {
                    guard let page = document.page(at: pageIndex) else { continue }
                    let bounds = page.bounds(for: .mediaBox)
                    context.beginPage(withBounds: bounds, pageInfo: [:])
                    
                    let cg = context.cgContext
                    cg.saveGState()
                    cg.translateBy(x: 0, y: bounds.height)
                    cg.scaleBy(x: 1, y: -1)
                    
                    let removedWidgetAnnotations = removeWidgetAnnotations(from: page)
                    page.draw(with: .mediaBox, to: cg)
                    restoreWidgetAnnotations(removedWidgetAnnotations, to: page)
                    
                    let textItems = metadata.textBoxes.filter { $0.pageIndex == pageIndex }
                    for item in textItems {
                        let rect = item.rect.cgRect
                        let textCornerRadius: CGFloat = 6
                        let textPadding = UIEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
                        let roundedTextRect = UIBezierPath(roundedRect: rect, cornerRadius: textCornerRadius)
                        cg.saveGState()
                        cg.addPath(roundedTextRect.cgPath)
                        cg.setFillColor(item.background.uiColor.cgColor)
                        cg.fillPath()
                        cg.restoreGState()
                        
                        drawText(
                            item.text,
                            in: rect.inset(by: textPadding),
                            fontSize: item.fontSize ?? 14,
                            isBold: item.isBold ?? false,
                            textColor: (item.textColor?.uiColor) ?? .label,
                            textAlignment: NSTextAlignment(rawValue: item.textAlignment ?? 0) ?? .left,
                            verticalAlignment: TextVerticalAlignment(rawValue: item.verticalAlignment ?? "") ?? .top,
                            context: cg
                        )
                    }
                    
                    let imageItems = metadata.images.filter { $0.pageIndex == pageIndex }
                    for item in imageItems {
                        if let data = Data(base64Encoded: item.imageBase64),
                           let image = UIImage(data: data)?.cgImage {
                            let rect = item.rect.cgRect
                            let imageCornerRadius: CGFloat = 6
                            let roundedImageRect = UIBezierPath(roundedRect: rect, cornerRadius: imageCornerRadius)
                            cg.saveGState()
                            cg.addPath(roundedImageRect.cgPath)
                            cg.clip()
                            let fittedRect = aspectFitRect(for: image, in: rect)
                            cg.draw(image, in: fittedRect)
                            cg.restoreGState()

                            // Draw configurable border
                            if let bw = item.borderWidth, bw > 0 {
                                let bc = item.borderColor?.uiColor ?? UIColor.black
                                cg.saveGState()
                                cg.setStrokeColor(bc.cgColor)
                                cg.setLineWidth(bw)
                                let borderPath = UIBezierPath(roundedRect: rect.insetBy(dx: bw / 2, dy: bw / 2), cornerRadius: imageCornerRadius)
                                cg.addPath(borderPath.cgPath)
                                cg.strokePath()
                                cg.restoreGState()
                            }
                        }
                    }

                    let shapeItems = metadata.shapes.filter { $0.pageIndex == pageIndex }
                    for item in shapeItems {
                        guard let kind = OverlayShapeKind(rawValue: item.kindRaw) else { continue }
                        let rect = item.rect.cgRect
                        let insetRect = rect.insetBy(dx: item.lineWidth / 2, dy: item.lineWidth / 2)
                        cg.saveGState()
                        cg.setStrokeColor(item.strokeColor.uiColor.cgColor)
                        cg.setLineWidth(item.lineWidth)
                        cg.setLineCap(.round)
                        cg.setLineJoin(.round)
                        switch kind {
                        case .circle:
                            cg.addEllipse(in: insetRect)
                        case .rectangle:
                            let path = UIBezierPath(roundedRect: insetRect, cornerRadius: 4)
                            cg.addPath(path.cgPath)
                        case .triangle:
                            cg.move(to: CGPoint(x: insetRect.midX, y: insetRect.minY))
                            cg.addLine(to: CGPoint(x: insetRect.maxX, y: insetRect.maxY))
                            cg.addLine(to: CGPoint(x: insetRect.minX, y: insetRect.maxY))
                            cg.closePath()
                        }
                        cg.strokePath()
                        cg.restoreGState()
                    }

                    cg.restoreGState()
                }
            }
            return true
        } catch {
            return false
        }
    }
    
    private func drawText(_ text: String, in rect: CGRect, fontSize: CGFloat, isBold: Bool, textColor: UIColor, textAlignment: NSTextAlignment = .left, verticalAlignment: TextVerticalAlignment = .top, context: CGContext) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = textAlignment
        paragraph.lineBreakMode = .byWordWrapping
        let font = isBold ? UIFont.boldSystemFont(ofSize: fontSize) : UIFont.systemFont(ofSize: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraph
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)

        // Offset the draw rect for middle/bottom vertical alignment.
        var drawRect = rect
        if verticalAlignment != .top {
            let constraints = CGSize(width: rect.width, height: .greatestFiniteMagnitude)
            let suggested = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRangeMake(0, 0), nil, constraints, nil)
            let textHeight = min(suggested.height, rect.height)
            switch verticalAlignment {
            case .top: break
            case .middle:
                let offset = max(0, (rect.height - textHeight) / 2)
                drawRect = CGRect(x: rect.minX, y: rect.minY + offset, width: rect.width, height: rect.height - offset)
            case .bottom:
                let offset = max(0, rect.height - textHeight)
                drawRect = CGRect(x: rect.minX, y: rect.minY + offset, width: rect.width, height: rect.height - offset)
            }
        }

        context.saveGState()
        let path = CGPath(rect: drawRect, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, attributed.length), path, nil)
        CTFrameDraw(frame, context)
        context.restoreGState()
    }

    private func aspectFitRect(for image: CGImage, in rect: CGRect) -> CGRect {
        let imageSize = CGSize(width: image.width, height: image.height)
        guard imageSize.width > 0, imageSize.height > 0 else { return rect }
        let scale = min(rect.width / imageSize.width, rect.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2
        )
        return CGRect(origin: origin, size: size)
    }

    private func removeWidgetAnnotations(from page: PDFPage) -> [PDFAnnotation] {
        let widgets = page.annotations.filter {
            $0.type == PDFAnnotationSubtype.widget.rawValue || !$0.widgetFieldType.rawValue.isEmpty
        }
        for annotation in widgets {
            page.removeAnnotation(annotation)
        }
        return widgets
    }
    
    private func restoreWidgetAnnotations(_ widgets: [PDFAnnotation], to page: PDFPage) {
        for annotation in widgets {
            page.addAnnotation(annotation)
        }
    }

    private func defaultFileName(for kind: PDFEditorDocumentKind) -> String {
        let baseName = currentDocumentURL?.deletingPathExtension().lastPathComponent ?? "Document"
        switch kind {
        case .editable:
            return "\(baseName)-Editable.pdf"
        case .flattened:
            return "\(baseName)-Flattened.pdf"
        }
    }

    private func stagingURL(fileName: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(fileName)
    }

    private func finalizeGeneratedFile(
        at generatedURL: URL,
        request: PDFEditorFileRequest,
        handler: PDFEditorFileHandler?
    ) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: generatedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )

        if let handler {
            let finalURL = try handler(request)
            if finalURL != generatedURL, fileManager.fileExists(atPath: generatedURL.path) {
                try? fileManager.removeItem(at: generatedURL)
            }
            return finalURL
        }

        let folderURL = defaultFolderURL(for: request.kind)
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)
        let destinationURL = uniqueDestinationURL(
            for: request.suggestedFileName,
            in: folderURL
        )
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: generatedURL, to: destinationURL)
        return destinationURL
    }

    private func defaultFolderURL(for kind: PDFEditorDocumentKind) -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        switch kind {
        case .editable:
            return documentsPath.appendingPathComponent("PDFEdits", isDirectory: true)
        case .flattened:
            return documentsPath.appendingPathComponent("PDFExports", isDirectory: true)
        }
    }

    private func uniqueDestinationURL(for fileName: String, in folderURL: URL) -> URL {
        let baseName = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        let ext = URL(fileURLWithPath: fileName).pathExtension.isEmpty ? "pdf" : URL(fileURLWithPath: fileName).pathExtension
        var candidate = folderURL.appendingPathComponent("\(baseName).\(ext)")
        var counter = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folderURL.appendingPathComponent("\(baseName)-\(counter).\(ext)")
            counter += 1
        }
        return candidate
    }

    private func pdfDocumentInfo(from document: PDFDocument) -> [String: Any] {
        guard let attributes = document.documentAttributes else { return [:] }
        var info: [String: Any] = [:]

        if let title = attributes[PDFDocumentAttribute.titleAttribute] as? String, !title.isEmpty {
            info[kCGPDFContextTitle as String] = title
        }
        if let author = attributes[PDFDocumentAttribute.authorAttribute] as? String, !author.isEmpty {
            info[kCGPDFContextAuthor as String] = author
        }
        if let subject = attributes[PDFDocumentAttribute.subjectAttribute] as? String, !subject.isEmpty {
            info[kCGPDFContextSubject as String] = subject
        }
        if let creator = attributes[PDFDocumentAttribute.creatorAttribute] as? String, !creator.isEmpty {
            info[kCGPDFContextCreator as String] = creator
        }
        if let keywords = attributes[PDFDocumentAttribute.keywordsAttribute] {
            if let keywordString = keywords as? String, !keywordString.isEmpty {
                info[kCGPDFContextKeywords as String] = keywordString
            } else if let keywordList = keywords as? [String], !keywordList.isEmpty {
                info[kCGPDFContextKeywords as String] = keywordList
            }
        }

        return info
    }
}

// MARK: - PencilGestureHandler Conformance
extension PDFFormViewModel: PencilGestureHandler {}
