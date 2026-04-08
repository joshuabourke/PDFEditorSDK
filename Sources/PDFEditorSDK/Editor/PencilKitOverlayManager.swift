//
//  PencilKitOverlayManager.swift
//  PDFEditorSDK
//
//  Standalone PencilKit integration — overlay a PKCanvasView on the current
//  PDF page, capture the drawing as a raster image on deactivate.
//  Easy to remove: delete this file + a handful of enum/toolbar references.
//

import UIKit
import PDFKit
import PencilKit

/// Manages a transparent `PKCanvasView` overlay on top of a `DrawingPDFView`
/// (or any `PDFView` subclass). When deactivated the drawing is captured as a
/// `UIImage` ready to be stored as an `OverlayImageState`.
@MainActor
final class PencilKitOverlayManager: NSObject {

    // MARK: - State

    private(set) var isActive = false
    private var canvasView: PKCanvasView?
    private var toolPicker: PKToolPicker?
    private var doneButton: UIButton?
    private weak var pdfView: DrawingPDFView?

    /// Called when the manager captures a finished drawing.
    /// Parameters: PNG image data and the drawing frame in view coordinates.
    /// The caller is responsible for coordinate conversion to document space.
    var onDrawingCaptured: ((_ imageData: Data, _ frameInView: CGRect) -> Void)?

    /// Called when the user taps the floating Done button.
    /// The caller should switch the active tool back to select.
    var onDoneTapped: (() -> Void)?

    // MARK: - Activate / Deactivate

    /// Show the PencilKit canvas over the current visible PDF page.
    func activate(over pdfView: DrawingPDFView) {
        guard !isActive else { return }
        self.pdfView = pdfView
        isActive = true

        // MARK: Canvas
        let canvas = PKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .anyInput
        canvas.overrideUserInterfaceStyle = .light

        // Position over the current page
        if let page = pdfView.currentPage {
            let pageRect = page.bounds(for: .mediaBox)
            let viewRect = pdfView.convert(pageRect, from: page)
            canvas.frame = viewRect
        } else {
            canvas.frame = pdfView.bounds
        }

        // Restrict the canvas's built-in scroll gesture to 1 finger so that
        // 2-finger touches can pass through to fingerPanGesture for page scrolling.
        canvas.panGestureRecognizer.maximumNumberOfTouches = 1

        pdfView.addSubview(canvas)

        let picker = PKToolPicker()
        picker.setVisible(true, forFirstResponder: canvas)
        picker.addObserver(canvas)
        canvas.becomeFirstResponder()

        self.canvasView = canvas
        self.toolPicker = picker

        // MARK: Done button
        let btn = UIButton(type: .system)
        btn.setTitle("Done", for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        btn.setTitleColor(.white, for: .normal)
        btn.backgroundColor = .systemBlue
        btn.layer.cornerRadius = 10
        btn.layer.shadowColor = UIColor.black.cgColor
        btn.layer.shadowOpacity = 0.18
        btn.layer.shadowOffset = CGSize(width: 0, height: 2)
        btn.layer.shadowRadius = 4
        btn.contentEdgeInsets = UIEdgeInsets(top: 8, left: 18, bottom: 8, right: 18)
        btn.addTarget(self, action: #selector(handleDoneTapped), for: .touchUpInside)
        btn.sizeToFit()

        // Position at the top-right of the pdf view with some padding
        let btnSize = btn.bounds.size
        let padding: CGFloat = 16
        btn.frame = CGRect(
            x: pdfView.bounds.maxX - btnSize.width - padding,
            y: pdfView.bounds.minY + padding,
            width: btnSize.width,
            height: btnSize.height
        )
        btn.autoresizingMask = [.flexibleLeftMargin, .flexibleBottomMargin]
        pdfView.addSubview(btn)
        pdfView.bringSubviewToFront(btn)
        self.doneButton = btn

        // Watch for page changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pageChanged),
            name: Notification.Name.PDFViewPageChanged,
            object: pdfView
        )
    }

    /// Hide the canvas. If there is any drawing, capture it and return `true`.
    @discardableResult
    func deactivate() -> Bool {
        guard isActive else { return false }
        NotificationCenter.default.removeObserver(self, name: Notification.Name.PDFViewPageChanged, object: pdfView)

        let didCapture = captureCurrentDrawing()
        cleanup()
        isActive = false
        return didCapture
    }

    // MARK: - Done button

    @objc private func handleDoneTapped() {
        onDoneTapped?()
    }

    // MARK: - Capture

    /// Render the current PKDrawing to a PNG and deliver via `onDrawingCaptured`.
    /// Crops to the actual drawn strokes (not the whole canvas) and uses PNG
    /// so transparent areas remain clear — no black-fill artefact.
    /// Returns `true` if a non-empty drawing was captured.
    @discardableResult
    private func captureCurrentDrawing() -> Bool {
        guard let canvas = canvasView,
              pdfView != nil else { return false }

        let drawing = canvas.drawing
        guard !drawing.bounds.isEmpty else { return false }

        // Crop to the actual drawn area within the canvas coordinate space
        let strokeBounds = drawing.bounds
        let scale = UIScreen.main.scale
        let image = drawing.image(from: strokeBounds, scale: scale)

        // PNG preserves the transparent background — JPEG would turn it black
        guard let data = image.pngData() else { return false }

        // Map the stroke bounds from canvas-local space into pdfView space
        let frameInView = CGRect(
            x: canvas.frame.origin.x + strokeBounds.origin.x,
            y: canvas.frame.origin.y + strokeBounds.origin.y,
            width: strokeBounds.width,
            height: strokeBounds.height
        )

        onDrawingCaptured?(data, frameInView)
        return true
    }

    // MARK: - Page Change

    @objc private func pageChanged() {
        guard isActive, let pdfView = pdfView else { return }
        // Capture current drawing before repositioning
        captureCurrentDrawing()
        canvasView?.drawing = PKDrawing()

        // Reposition canvas to new page
        if let page = pdfView.currentPage {
            let pageRect = page.bounds(for: .mediaBox)
            let viewRect = pdfView.convert(pageRect, from: page)
            canvasView?.frame = viewRect
        }
    }

    // MARK: - Cleanup

    private func cleanup() {
        if let canvas = canvasView {
            toolPicker?.setVisible(false, forFirstResponder: canvas)
            toolPicker?.removeObserver(canvas)
            canvas.resignFirstResponder()
            canvas.removeFromSuperview()
        }
        doneButton?.removeFromSuperview()
        canvasView = nil
        toolPicker = nil
        doneButton = nil
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
