//
//  DrawingPDFView.swift
//  PDFEditorSDK
//
//  Extracted from PDFEditorView.swift
//

import SwiftUI
import PDFKit
import UIKit

// MARK: - Pencil Drawing Gesture Recognizer

protocol PencilDrawingGestureDelegate: AnyObject {
    func pencilTouchBegan(_ touch: UITouch, with event: UIEvent?)
    func pencilTouchMoved(_ touch: UITouch, with event: UIEvent?)
    func pencilTouchEnded(_ touch: UITouch, with event: UIEvent?)
    func pencilTouchCancelled(with event: UIEvent?)
}

class PencilDrawingGestureRecognizer: UIGestureRecognizer {
    weak var drawingDelegate: PencilDrawingGestureDelegate?

    /// When `true`, single-finger touches are also accepted for drawing in
    /// addition to Apple Pencil. Updating this property also updates
    /// `allowedTouchTypes` so UIKit routes the right events.
    var includesFingerInput: Bool = false {
        didSet {
            allowedTouchTypes = includesFingerInput
                ? [NSNumber(value: UITouch.TouchType.pencil.rawValue),
                   NSNumber(value: UITouch.TouchType.direct.rawValue)]
                : [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        }
    }

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
    }

    private func isValidTouch(_ touch: UITouch) -> Bool {
        touch.type == .pencil || (includesFingerInput && touch.type == .direct)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first, isValidTouch(touch) else {
            for touch in touches { ignore(touch, for: event) }
            return
        }
        state = .began
        drawingDelegate?.pencilTouchBegan(touch, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first, isValidTouch(touch) else { return }
        state = .changed
        drawingDelegate?.pencilTouchMoved(touch, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first, isValidTouch(touch) else { return }
        state = .ended
        drawingDelegate?.pencilTouchEnded(touch, with: event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .cancelled
        drawingDelegate?.pencilTouchCancelled(with: event)
    }
}

// MARK: - Drawing PDF View
class DrawingPDFView: PDFView, UIIndirectScribbleInteractionDelegate, PencilDrawingGestureDelegate {
    
    // MARK: - Properties
    weak var formViewModel: PDFFormViewModel?
    
    var isDrawingMode = false {
        didSet {
            if isDrawingMode || isTextMode {
                disableTextSelection()
            } else {
                enableTextSelection()
            }
            syncScribbleInteraction()

            if !isDrawingMode {
                hideEraserCircle()
            } else {
                deselectInkAnnotation()
            }
            // Pencil gesture must also stay active when the standalone erase tool is on.
            pencilDrawingGesture?.isEnabled = isDrawingMode || isEraserMode
            updateNavigationGestureState()
            if isFormMode { syncFormWidgetTextEditingState() }
        }
    }

    var isTextMode = false {
        didSet {
            textBoxPanGesture?.isEnabled = isTextMode
            syncScribbleInteraction()

            if isDrawingMode || isTextMode {
                disableTextSelection()
            } else {
                enableTextSelection()
            }

            if isTextMode {
                hideEraserCircle()
            } else {
                textBoxLayer.isHidden = true
            }
            updateNavigationGestureState()
            updatePencilTextTapGesture()
            if isFormMode { syncFormWidgetTextEditingState() }
        }
    }

    var isSelectMode = false {
        didSet {
            guard oldValue != isSelectMode else { return }
            textBoxViews.values.forEach { $0.setSelectMode(isSelectMode) }
            imageBoxViews.values.forEach { $0.setSelectMode(isSelectMode) }
            shapeBoxViews.values.forEach { $0.setSelectMode(isSelectMode) }
            inkSelectTapGesture?.isEnabled = isSelectMode
            if !isSelectMode {
                deselectInkAnnotation()
                deselectOverlaySelection()
            }
            syncScribbleInteraction()
            updateNavigationGestureState()
        }
    }
    
    var suppressGoTo = false

    /// True when any annotation tool is active and needs touch isolation + 2-finger navigation.
    private var isAnnotationToolActive: Bool {
        isDrawingMode || isEraserMode || isShapeMode || isTextMode || isSelectMode || isPencilKitMode
    }

    /// True when touches to PDFKit's internals should be fully suppressed.
    /// Select mode excluded so overlay subviews (ImageBoxView, ShapeBoxView)
    /// receive taps for drag-to-relocate. Text mode now included so single-finger
    /// drags always draw a new text box instead of scrolling the page.
    ///
    /// In pencil-only mode we never intercept — instead we restrict PDFKit's
    /// scroll view pan to finger-only touches so our pencil annotation gestures
    /// win for pencil input while finger input reaches PDFKit naturally.
    private var shouldInterceptAllTouches: Bool {
        if pencilOnlyAnnotations { return false }
        return isDrawingMode || isEraserMode || isShapeMode || isTextMode
    }

    var isFormMode = false {
        didSet {
            textBoxOverlayView.isUserInteractionEnabled = !isFormMode
            if isFormMode {
                enableTextSelection()
                // Logs: PDFKit double-tap zoom must stay off for all of Form mode so it never
                // competes with `PDFTextWidgetTextView` word selection / body text gestures.
                setDoubleTapZoomEnabled(false)
                syncFormWidgetTextEditingState()
            } else if !isDrawingMode && !isTextMode {
                enableTextSelection()
            }
            formPencilTapGesture?.isEnabled = isFormMode
            updateFormFieldHighlights()
            if !isFormMode {
                syncFormWidgetTextEditingState()
            }
            syncScribbleInteraction()
        }
    }

    /// True while a PDF-hosted UITextField/UITextView (form widget) is first responder.
    /// Drives double-tap zoom off and PDF inner-scroll tuning (`delaysContentTouches`, two-finger pan)
    /// so the embedded `UITextView` receives long-press and single-finger drags for selection.
    private var isFormFieldTextActive = false
    private var formWidgetTextSyncScheduled = false
    /// Saved `PDFView` inner scroll settings while a widget text control is first responder.
    private var savedPDFScrollDelaysContentTouches: Bool?
    /// Most recent keyboard end-frame in window coordinates; cleared when keyboard hides.
    private var lastKnownKeyboardFrame: CGRect = .zero
    /// True while a finger touch is in progress. Cleared in touchesEnded/Cancelled so that
    /// handleTextSelectionChanged can tell whether a selection change is user-driven.
    private var isDirectTouchInProgress = false
    /// True while the user is actively selecting baked-in PDF text with a finger gesture.
    private var isTextSelectionInProgress = false
    /// KVO token that pins the scroll view's contentOffset during text selection.
    /// PDFKit scrolls via its own internal gesture recognisers (not scrollView.panGestureRecognizer),
    /// so isScrollEnabled = false is insufficient — KVO catches every write regardless of source.
    private var textSelectionScrollObserver: NSKeyValueObservation?
    /// The content offset captured when text selection began; held constant until the touch ends.
    private var textSelectionLockedOffset: CGPoint?

    func setFormFieldEntryEnabled(_ enabled: Bool) {
        let selector = NSSelectorFromString("setAllowsFormFieldEntry:")
        if responds(to: selector) {
            setValue(enabled, forKey: "allowsFormFieldEntry")
        }
    }
    
    // PDFView's internal scroll view
    private var scrollView: UIScrollView? {
        return subviews.compactMap { $0 as? UIScrollView }.first
    }

    private func disableTextSelection() {
        // Only touch PDFKit's built-in gesture recognisers — skip the ones we own
        // and manage explicitly through mode properties (inkSelectTapGesture, etc.).
        gestureRecognizers?.forEach { gesture in
            guard gesture !== inkSelectTapGesture,
                  gesture !== pencilTextTapGesture,
                  gesture !== formPencilTapGesture else { return }
            if let longPress = gesture as? UILongPressGestureRecognizer {
                longPress.isEnabled = false
            }
            if let tap = gesture as? UITapGestureRecognizer {
                tap.isEnabled = false
            }
        }

        // Also disable on the scroll view's subviews where text selection happens
        disableSelectionGestures(in: self)
    }

    private func enableTextSelection() {
        // Only touch PDFKit's built-in gesture recognisers — skip the ones we own
        // and manage explicitly through mode properties (inkSelectTapGesture, etc.).
        gestureRecognizers?.forEach { gesture in
            guard gesture !== inkSelectTapGesture,
                  gesture !== pencilTextTapGesture,
                  gesture !== formPencilTapGesture else { return }
            if let longPress = gesture as? UILongPressGestureRecognizer {
                longPress.isEnabled = true
            }
            if let tap = gesture as? UITapGestureRecognizer {
                tap.isEnabled = true
            }
        }

        enableSelectionGestures(in: self)
    }

    private func disableSelectionGestures(in view: UIView) {
        view.gestureRecognizers?.forEach { gesture in
            if gesture is UILongPressGestureRecognizer {
                gesture.isEnabled = false
            }
        }
        view.subviews.forEach { disableSelectionGestures(in: $0) }
    }

    private func enableSelectionGestures(in view: UIView) {
        view.gestureRecognizers?.forEach { gesture in
            if gesture is UILongPressGestureRecognizer {
                gesture.isEnabled = true
            }
        }
        view.subviews.forEach { enableSelectionGestures(in: $0) }
    }

    /// While a PDF widget text view is first responder:
    /// - Keep single-finger scroll active so the user can scroll normally while editing a form field.
    /// - Set `delaysContentTouches = false` so long-press / loupe / caret placement are not held behind
    ///   the scroll pan (avoids “System gesture gate timed out” and broken long-press seeking).
    private func updatePDFScrollInteractionForEmbeddedWidgetTextEditing(_ widgetFocused: Bool) {
        guard let sv = scrollView else { return }
        if widgetFocused {
            if savedPDFScrollDelaysContentTouches == nil {
                savedPDFScrollDelaysContentTouches = sv.delaysContentTouches
                sv.delaysContentTouches = false
            }
        } else {
            if let savedDelays = savedPDFScrollDelaysContentTouches {
                sv.delaysContentTouches = savedDelays
                savedPDFScrollDelaysContentTouches = nil
            }
        }
    }
    
    var currentInkColor: UIColor = .systemBlue
    var currentLineWidth: CGFloat = 3.0
    var isEraserMode: Bool = false {
        didSet {
            // Eraser is now a standalone tool. When it becomes active enable the pencil
            // gesture (same gesture that handles drawing); when it's deactivated only keep
            // the gesture if draw mode is still on, and hide the eraser circle.
            pencilDrawingGesture?.isEnabled = isDrawingMode || isEraserMode
            if !isEraserMode { hideEraserCircle() }
            syncScribbleInteraction()
            updateNavigationGestureState()
        }
    }
    var eraserRadius: CGFloat = 9 {
        didSet { updateEraserCircle() }
    }
    var textBoxBackgroundColor: UIColor = UIColor.systemYellow
    var textBoxFontSize: CGFloat = 14
    var textBoxIsBold: Bool = false
    var textBoxTextColor: UIColor = .label
    var textBoxTextAlignment: NSTextAlignment = .left
    var textBoxVerticalAlignment: TextVerticalAlignment = .top
    var textBoxAutoResize: Bool = false
    var textBoxBorderWidth: CGFloat = 0
    var textBoxBorderColor: UIColor = .black

    /// When `true`, only Apple Pencil triggers annotations. Finger touches are
    /// passed through to PDFKit so the user can pan and zoom normally with one finger.
    var pencilOnlyAnnotations: Bool = false {
        didSet {
            updateNavigationGestureState()
            updateAnnotationGestureTouchTypes()
        }
    }

    /// When `true`, single-finger touch input is also accepted for drawing in
    /// addition to Apple Pencil. Two-finger gestures continue to navigate.
    var drawWithFinger: Bool = false {
        didSet { pencilDrawingGesture?.includesFingerInput = drawWithFinger }
    }

    /// Re-evaluates whether the two-finger navigation gestures should be active
    /// and whether PDFKit's internal scroll pan should be restricted to finger-only.
    /// Called whenever a tool mode or an input-mode setting changes.
    private func updateNavigationGestureState() {
        let enabled = isAnnotationToolActive && !pencilOnlyAnnotations
        fingerPanGesture?.isEnabled = enabled
        fingerPinchGesture?.isEnabled = enabled
        updateScrollPanAllowedTouchTypes()
    }

    /// When pencil-only mode is active and an annotation tool is in use, restrict
    /// PDFKit's internal scroll pan to finger-only. This guarantees that pencil
    /// drags are exclusively claimed by the annotation gesture recognisers
    /// (shapePanGesture, textBoxPanGesture, pencilDrawingGesture) and never race
    /// against PDFKit's scroll recogniser for the same pencil touch.
    private func updateScrollPanAllowedTouchTypes() {
        guard let sv = scrollView else { return }
        let restrictToFinger = pencilOnlyAnnotations && (isDrawingMode || isEraserMode || isShapeMode || isTextMode)
        sv.panGestureRecognizer.allowedTouchTypes = restrictToFinger
            ? [NSNumber(value: UITouch.TouchType.direct.rawValue)]
            : [NSNumber(value: UITouch.TouchType.direct.rawValue),
               NSNumber(value: UITouch.TouchType.pencil.rawValue)]
    }

    /// Restricts shape and text-box creation gestures to Apple Pencil only when
    /// `pencilOnlyAnnotations` is on, or restores them to accept finger input again.
    private func updateAnnotationGestureTouchTypes() {
        let types: [NSNumber] = pencilOnlyAnnotations
            ? [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
            : [NSNumber(value: UITouch.TouchType.direct.rawValue),
               NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        shapePanGesture?.allowedTouchTypes = types
        textBoxPanGesture?.allowedTouchTypes = types
        updatePencilTextTapGesture()
    }

    /// Enables the pencil-only tap gesture used for tap-to-edit in text mode when
    /// pencil-only annotations are active. In that configuration `shouldInterceptAllTouches`
    /// returns false, so the normal touch-override tap tracker is bypassed.
    private func updatePencilTextTapGesture() {
        pencilTextTapGesture?.isEnabled = isTextMode && pencilOnlyAnnotations
    }
    
    private var pencilDrawingGesture: PencilDrawingGestureRecognizer?
    private var pencilTextTapGesture: UITapGestureRecognizer?
    private var fingerPanGesture: UIPanGestureRecognizer?
    private var fingerPinchGesture: UIPinchGestureRecognizer?
    private var inkDragPanGesture: UIPanGestureRecognizer?
    private var pinchInitialScale: CGFloat = 1.0
    private var currentStrokePoints: [CGPoint] = []
    private var currentAnnotation: PDFAnnotation?
    var currentPDFPage: PDFPage?
    
    private var scribbleInteraction: UIIndirectScribbleInteraction<DrawingPDFView>?
    private var textBoxPanGesture: UIPanGestureRecognizer?
    private let eraserLayer = CAShapeLayer()
    private var eraserLocation: CGPoint?
    private var eraserRootByAnnotationID: [ObjectIdentifier: ObjectIdentifier] = [:]
    private var eraserRootAnnotations: [ObjectIdentifier: PDFAnnotation] = [:]
    private var eraserCurrentAnnotations: [ObjectIdentifier: PDFAnnotation] = [:]
    private let textBoxLayer = CAShapeLayer()
    private var textBoxStartPoint: CGPoint?
    private var textModeTouchStart: CGPoint?
    /// Short finger tap on the PDF while a text overlay is focused (`shouldInterceptAllTouches`); avoids clearing focus on every draw stroke.
    private var fingerDismissOverlayTouchStart: CGPoint?
    private let textBoxOverlayView = UIView()
    /// Sits above PDF page tiles (below `textBoxOverlayView`). The tint for the field that is
    /// actively being edited is omitted; other editable fields stay highlighted.
    private let formFieldHighlightHostView = UIView()
    private let formFieldHighlightLayer = CAShapeLayer()
    var formFieldHighlightFilter: ((PDFFormFieldInfo) -> Bool)?
    private var textBoxViews: [UUID: TextBoxView] = [:]
    private var imageBoxViews: [UUID: ImageBoxView] = [:]
    private var shapeBoxViews: [UUID: ShapeBoxView] = [:]
    private var selectedTextBoxID: UUID?
    private var selectedImageBoxID: UUID?
    private var selectedShapeID: UUID?
    private var shapePanGesture: UIPanGestureRecognizer?
    private var shapeStartPoint: CGPoint?
    private let shapePreviewLayer = CAShapeLayer()
    var currentShapeKind: OverlayShapeKind = .rectangle
    var shapeStrokeColor: UIColor = .systemRed
    var shapeLineWidth: CGFloat = 2.0
    var isShapeMode = false {
        didSet {
            shapePanGesture?.isEnabled = isShapeMode
            if !isShapeMode { shapePreviewLayer.isHidden = true }
            syncScribbleInteraction()
            updateNavigationGestureState()
        }
    }
    // MARK: - PencilKit
    private let pencilKitManager = PencilKitOverlayManager()
    var isPencilKitMode = false {
        didSet {
            guard oldValue != isPencilKitMode else { return }
            if isPencilKitMode {
                pencilKitManager.activate(over: self)
            } else {
                pencilKitManager.deactivate()
            }
            syncScribbleInteraction()
        }
    }

    private var movingInkAnnotation: PDFAnnotation?
    private var movingInkStartBounds: CGRect?
    private var movingInkOffset: CGPoint?
    private var lockedInkDragContentOffset: CGPoint?
    
    private(set) var selectedInkAnnotation: PDFAnnotation?
    private var selectedInkPage: PDFPage?
    private let inkSelectionOverlayView = UIView()
    private let inkSelectionBorderLayer = CAShapeLayer()
    private var inkSelectTapGesture: UITapGestureRecognizer?
    private var overlaySelectTapGesture: UITapGestureRecognizer?
    private var formPencilTapGesture: UITapGestureRecognizer?
    private var textBoxPanStartedOnExistingBox = false
    
    private let overlayMetadataPrefix = "OVERLAY_META_V1:"
    private let overlayMetadataPartPrefix = "OVERLAY_META_V1_PART:"
    
    // Form field tracking
    private var formFieldStates: [String: String?] = [:]
    private var activeFormFieldAnnotation: PDFAnnotation?
    private var activeFormFieldName: String?
    private var activeFormFieldInitialValue: String?
    private var isApplyingFormUndoRedo = false
    private var fullFormWidgetRefreshScheduled = false

    // Keyboard offset preservation for text box editing
    private var savedTextBoxContentOffset: CGPoint?
    
    // MARK: - Init
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        if let docView = documentView, textBoxOverlayView.superview == nil {
            textBoxOverlayView.backgroundColor = .clear
            textBoxOverlayView.frame = docView.bounds
            textBoxOverlayView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            textBoxOverlayView.isUserInteractionEnabled = !isFormMode
            docView.addSubview(textBoxOverlayView)
            docView.bringSubviewToFront(textBoxOverlayView)
            // Deselect overlay when the user taps empty canvas space in select mode
            let overlayTap = UITapGestureRecognizer(target: self, action: #selector(handleOverlaySelectTap(_:)))
            overlayTap.cancelsTouchesInView = false
            overlayTap.isEnabled = false
            textBoxOverlayView.addGestureRecognizer(overlayTap)
            overlaySelectTapGesture = overlayTap
            if inkSelectionOverlayView.superview != nil {
                docView.bringSubviewToFront(inkSelectionOverlayView)
            }
        } else if let docView = documentView {
            docView.bringSubviewToFront(textBoxOverlayView)
            // Re-sync on every layout pass in case PDFKit rebuilds its internal hierarchy.
            textBoxOverlayView.isUserInteractionEnabled = !isFormMode
            if inkSelectionOverlayView.superview != nil {
                docView.bringSubviewToFront(inkSelectionOverlayView)
            }
        }
        
        if let docView = documentView {
            if formFieldHighlightHostView.superview == nil {
                formFieldHighlightHostView.backgroundColor = .clear
                formFieldHighlightHostView.isUserInteractionEnabled = false
                formFieldHighlightHostView.frame = docView.bounds
                formFieldHighlightHostView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                docView.addSubview(formFieldHighlightHostView)
            } else {
                formFieldHighlightHostView.frame = docView.bounds
            }
            docView.insertSubview(formFieldHighlightHostView, belowSubview: textBoxOverlayView)
        }
        
        updateFormFieldHighlights()
        // PDFKit can install the inner scroll view after the first `syncFormWidgetTextEditingState`;
        // re-apply two-finger-only scroll when a widget is already first responder.
        if isFormMode, formTextInputIsFirstResponder(in: self) {
            updatePDFScrollInteractionForEmbeddedWidgetTextEditing(true)
        }
        
        if let docView = documentView, inkSelectionOverlayView.superview == nil {
            inkSelectionOverlayView.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.08)
            inkSelectionOverlayView.isUserInteractionEnabled = true
            inkSelectionOverlayView.isHidden = true
            inkSelectionOverlayView.layer.cornerRadius = 4
            inkSelectionBorderLayer.strokeColor = UIColor.systemBlue.cgColor
            inkSelectionBorderLayer.fillColor = UIColor.clear.cgColor
            inkSelectionBorderLayer.lineWidth = 2
            inkSelectionBorderLayer.lineDashPattern = [6, 4]
            inkSelectionOverlayView.layer.addSublayer(inkSelectionBorderLayer)
            let dragPan = UIPanGestureRecognizer(target: self, action: #selector(handleInkDragPan(_:)))
            dragPan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
            dragPan.delegate = self
            inkSelectionOverlayView.addGestureRecognizer(dragPan)
            inkDragPanGesture = dragPan
            docView.addSubview(inkSelectionOverlayView)
        }

        if suppressGoTo, let lockedInkDragContentOffset, let scrollView {
            scrollView.setContentOffset(lockedInkDragContentOffset, animated: false)
        }
    }
    
    private func setup() {
        isInMarkupMode = false
        setupFormFieldTracking()
        setupTextSelectionObserver()
        setupPageChangeObserver()
        setupFormFieldHighlights()
        setupAnnotationHitObserver()
        setupScribbleInteraction()
        setupTextBoxGesture()
        setupEraserLayer()
        setupTextBoxLayer()
        setupPencilDrawingGesture()
        setupFingerNavigationGestures()
        setupInkSelectTapGesture()
        setupShapePreviewLayer()
        setupShapePanGesture()
        setupFormPencilTapGesture()
        setupPencilTextTapGesture()
        setupPencilKitManager()
        syncScribbleInteraction()
        setupPencilInteraction()
    }

    // MARK: - UIPencilInteraction Setup

    private var pencilInteraction: UIPencilInteraction?

    /// Task used to delay firing a single-squeeze action while waiting to see
    /// if a second squeeze arrives (making it a double-squeeze).
    private var singleSqueezePendingTask: Task<Void, Never>?

    private func setupPencilInteraction() {
        let interaction = UIPencilInteraction()
        interaction.delegate = self
        addInteraction(interaction)
        pencilInteraction = interaction
    }

    private func setupPencilKitManager() {
        pencilKitManager.onDrawingCaptured = { [weak self] imageData, frameInView in
            guard let self else { return }
            // Convert frame (view coords) → document coords via the current page
            if let page = self.currentPage {
                let pageRect = self.convert(frameInView, to: page)
                let docFrame = self.docRect(fromPageRect: pageRect, on: page)
                let state = OverlayImageState(id: UUID(), frame: docFrame, imageData: imageData)
                self.addOverlayImage(from: state)
                self.formViewModel?.didMakeChange(.overlayImage(add: state, remove: nil))
            }
        }

        pencilKitManager.onDoneTapped = { [weak self] in
            // Switching to select commits the drawing via isPencilKitMode → deactivate()
            self?.formViewModel?.setTool(.select)
        }
    }

    private func setupShapePreviewLayer() {
        shapePreviewLayer.strokeColor = UIColor.systemOrange.withAlphaComponent(0.9).cgColor
        shapePreviewLayer.fillColor = UIColor.clear.cgColor
        shapePreviewLayer.lineWidth = 1.5
        shapePreviewLayer.lineDashPattern = [6, 4]
        shapePreviewLayer.isHidden = true
        layer.addSublayer(shapePreviewLayer)
    }

    private func setupShapePanGesture() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleShapePan(_:)))
        pan.cancelsTouchesInView = true
        pan.maximumNumberOfTouches = 1
        pan.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue),
            NSNumber(value: UITouch.TouchType.pencil.rawValue)
        ]
        pan.delegate = self
        pan.isEnabled = false
        addGestureRecognizer(pan)
        shapePanGesture = pan
    }

    private func setupFormPencilTapGesture() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleFormPencilTap(_:)))
        tap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        tap.cancelsTouchesInView = false
        tap.isEnabled = false
        addGestureRecognizer(tap)
        formPencilTapGesture = tap
    }

    @objc private func handleFormPencilTap(_ gesture: UITapGestureRecognizer) {
        guard isFormMode else { return }
        let viewPoint = gesture.location(in: self)
        guard let page = self.page(for: viewPoint, nearest: true) else { return }
        let pagePoint = self.convert(viewPoint, to: page)
        for annotation in page.annotations {
            guard annotation.type == PDFAnnotationSubtype.widget.rawValue else { continue }
            guard annotation.bounds.contains(pagePoint) else { continue }
            let wt = annotation.widgetFieldType
            if wt == .button {
                // Toggle checkbox state
                let currentValue = annotation.widgetStringValue ?? "Off"
                if currentValue == "Off" || currentValue.isEmpty {
                    annotation.setValue("Yes", forAnnotationKey: .widgetValue)
                } else {
                    annotation.setValue("Off", forAnnotationKey: .widgetValue)
                }
                // Force redraw
                annotation.page?.annotations.forEach { _ in }
                setNeedsDisplay()
                return
            }
        }
    }

    private func setupPencilTextTapGesture() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handlePencilTextTap(_:)))
        tap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        tap.cancelsTouchesInView = false
        tap.isEnabled = false
        tap.delegate = self
        addGestureRecognizer(tap)
        pencilTextTapGesture = tap
    }

    @objc private func handlePencilTextTap(_ gesture: UITapGestureRecognizer) {
        guard isTextMode, pencilOnlyAnnotations else { return }
        let point = gesture.location(in: self)
        handleTextModeTap(at: point)
    }

    private func setupPencilDrawingGesture() {
        let gesture = PencilDrawingGestureRecognizer(target: nil, action: nil)
        gesture.drawingDelegate = self
        gesture.cancelsTouchesInView = true
        gesture.delaysTouchesBegan = true
        gesture.isEnabled = false
        gesture.delegate = self
        addGestureRecognizer(gesture)
        pencilDrawingGesture = gesture
    }
    
    private func setupFingerNavigationGestures() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleFingerPan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        pan.delegate = self
        pan.isEnabled = false
        addGestureRecognizer(pan)
        fingerPanGesture = pan
        
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handleFingerPinch(_:)))
        pinch.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        pinch.delegate = self
        pinch.isEnabled = false
        addGestureRecognizer(pinch)
        fingerPinchGesture = pinch
    }
    
    private func setupInkSelectTapGesture() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleInkSelectTap(_:)))
        tap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        tap.cancelsTouchesInView = false
        tap.isEnabled = false
        addGestureRecognizer(tap)
        inkSelectTapGesture = tap
    }
    
    @objc private func handleFingerPan(_ gesture: UIPanGestureRecognizer) {
        guard isAnnotationToolActive, let sv = scrollView else { return }
        let translation = gesture.translation(in: sv)
        var offset = sv.contentOffset
        offset.x -= translation.x
        offset.y -= translation.y
        let maxX = max(0, sv.contentSize.width - sv.bounds.width)
        let maxY = max(0, sv.contentSize.height - sv.bounds.height)
        offset.x = max(0, min(offset.x, maxX))
        offset.y = max(0, min(offset.y, maxY))
        sv.setContentOffset(offset, animated: false)
        gesture.setTranslation(.zero, in: sv)
    }
    
    @objc private func handleFingerPinch(_ gesture: UIPinchGestureRecognizer) {
        guard isAnnotationToolActive else { return }
        switch gesture.state {
        case .began:
            pinchInitialScale = scaleFactor
        case .changed:
            let newScale = pinchInitialScale * gesture.scale
            let clamped = max(minScaleFactor, min(newScale, maxScaleFactor))
            scaleFactor = clamped
        default:
            break
        }
    }
    
    // MARK: - Ink Selection
    
    @objc private func handleInkSelectTap(_ gesture: UITapGestureRecognizer) {
        guard isSelectMode else { return }
        let viewPoint = gesture.location(in: self)
        guard let page = self.page(for: viewPoint, nearest: true) else {
            deselectInkAnnotation()
            return
        }
        let pagePoint = self.convert(viewPoint, to: page)
        
        if let hit = page.annotation(at: pagePoint), hit.type == "Ink" {
            deselectOverlaySelection()
            selectedInkAnnotation = hit
            selectedInkPage = page
            formViewModel?.hasSelectedInkAnnotation = true
            updateInkSelectionOverlay()
        } else {
            deselectInkAnnotation()
            deselectOverlaySelection()
        }
    }

    @objc private func handleOverlaySelectTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: textBoxOverlayView)
        let hitView = textBoxOverlayView.hitTest(point, with: nil)
        // Only act when the tap lands on empty canvas (not on any overlay box)
        guard hitView === textBoxOverlayView else { return }

        if isSelectMode {
            deselectInkAnnotation()
            deselectOverlaySelection()
        } else if isTextMode || selectedTextBoxID != nil || textBoxViews.values.contains(where: { $0.isTextInputFirstResponder }) {
            // Dismiss keyboard and deselect the active text box so the user
            // can draw a new one on the next drag (text tool), or clear focus after editing while
            // another tool is active (draw/erase/shape/PencilKit).
            endOverlayTextEditing()
            deselectOverlaySelection()
        }
    }

    private func updateInkSelectionOverlay() {
        guard let annotation = selectedInkAnnotation,
              let page = selectedInkPage else {
            inkSelectionOverlayView.isHidden = true
            return
        }
        
        let rectInView = convert(annotation.bounds, from: page)
        guard let docView = documentView else {
            inkSelectionOverlayView.isHidden = true
            return
        }
        let rectInDoc = docView.convert(rectInView, from: self)
        let padding: CGFloat = 6
        let paddedRect = rectInDoc.insetBy(dx: -padding, dy: -padding)
        
        inkSelectionOverlayView.frame = paddedRect
        inkSelectionOverlayView.isHidden = false
        
        let borderPath = UIBezierPath(roundedRect: inkSelectionOverlayView.bounds, cornerRadius: 4)
        inkSelectionBorderLayer.path = borderPath.cgPath
        inkSelectionBorderLayer.frame = inkSelectionOverlayView.bounds
    }
    
    @objc private func handleInkDragPan(_ gesture: UIPanGestureRecognizer) {
        guard let annotation = selectedInkAnnotation, let page = selectedInkPage else { return }
        
        switch gesture.state {
        case .began:
            scrollView?.isScrollEnabled = false
            suppressGoTo = true
            lockedInkDragContentOffset = scrollView?.contentOffset
            movingInkAnnotation = annotation
            movingInkStartBounds = annotation.bounds
            let viewPoint = gesture.location(in: self)
            let pagePoint = self.convert(viewPoint, to: page)
            movingInkOffset = CGPoint(
                x: pagePoint.x - annotation.bounds.origin.x,
                y: pagePoint.y - annotation.bounds.origin.y
            )
        case .changed:
            guard let moving = movingInkAnnotation, let offset = movingInkOffset else { return }
            let viewPoint = gesture.location(in: self)
            let pagePoint = self.convert(viewPoint, to: page)
            var newBounds = moving.bounds
            newBounds.origin = CGPoint(
                x: pagePoint.x - offset.x,
                y: pagePoint.y - offset.y
            )
            moving.bounds = newBounds
            if let lockedInkDragContentOffset, let scrollView {
                scrollView.setContentOffset(lockedInkDragContentOffset, animated: false)
            }
            updateInkSelectionOverlay()
        case .ended:
            if let moving = movingInkAnnotation, let startBounds = movingInkStartBounds {
                let endBounds = moving.bounds
                if startBounds != endBounds {
                    formViewModel?.didMakeChange(.moveAnnotation(annotation: moving, from: startBounds, to: endBounds))
                }
            }
            movingInkAnnotation = nil
            movingInkStartBounds = nil
            movingInkOffset = nil
            lockedInkDragContentOffset = nil
            updateInkSelectionOverlay()
            DispatchQueue.main.async { [weak self] in
                self?.suppressGoTo = false
            }
            scrollView?.isScrollEnabled = true
        case .cancelled, .failed:
            if let moving = movingInkAnnotation, let startBounds = movingInkStartBounds {
                moving.bounds = startBounds
            }
            movingInkAnnotation = nil
            movingInkStartBounds = nil
            movingInkOffset = nil
            lockedInkDragContentOffset = nil
            updateInkSelectionOverlay()
            DispatchQueue.main.async { [weak self] in
                self?.suppressGoTo = false
            }
            scrollView?.isScrollEnabled = true
        default:
            break
        }
    }
    
    func deselectInkAnnotation() {
        selectedInkAnnotation = nil
        selectedInkPage = nil
        inkSelectionOverlayView.isHidden = true
        formViewModel?.hasSelectedInkAnnotation = false
    }
    
    private func setupAnnotationHitObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePDFAnnotationHit(_:)),
            name: .PDFViewAnnotationHit,
            object: self
        )
    }
    
    @objc private func handlePDFAnnotationHit(_ notification: Notification) {
        guard isFormMode, let annotation = pdfAnnotation(fromAnnotationHit: notification) else { return }
        guard annotation.type == PDFAnnotationSubtype.widget.rawValue else { return }
        let wt = annotation.widgetFieldType
        if wt == .text || wt == .choice {
            if let fieldName = annotation.fieldName, formFieldStates[fieldName] == nil {
                formFieldStates[fieldName] = annotation.widgetStringValue
            }
            // PDFKit often focuses the widget after this notification; disable double-tap
            // zoom immediately so it does not beat UITextField word-selection gestures.
            setDoubleTapZoomEnabled(false)
            scheduleFormWidgetTextSync()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.syncFormWidgetTextEditingState()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.syncFormWidgetTextEditingState()
            }
            return
        }
        guard wt == .button || wt == .signature else { return }
        guard let page = pdfPage(fromAnnotationHit: notification, annotation: annotation),
              let document,
              let formViewModel else { return }
        let pageIndex = document.index(for: page)
        guard pageIndex >= 0, pageIndex < document.pageCount else { return }
        formViewModel.presentFormWidgetImageSourceChoice(pageIndex: pageIndex, annotation: annotation)
    }
    
    private func pdfAnnotation(fromAnnotationHit notification: Notification) -> PDFAnnotation? {
        guard let info = notification.userInfo else { return nil }
        for (_, value) in info {
            if let ann = value as? PDFAnnotation { return ann }
        }
        return nil
    }
    
    private func pdfPage(fromAnnotationHit notification: Notification, annotation: PDFAnnotation) -> PDFPage? {
        guard let info = notification.userInfo else { return page(containing: annotation) }
        for (_, value) in info {
            if let page = value as? PDFPage { return page }
        }
        return page(containing: annotation)
    }
    
    private func page(containing annotation: PDFAnnotation) -> PDFPage? {
        guard let document else { return nil }
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }
            if page.annotations.contains(where: { $0 === annotation }) { return page }
        }
        return nil
    }

    private func setupEraserLayer() {
        eraserLayer.strokeColor = UIColor.systemBlue.withAlphaComponent(0.8).cgColor
        eraserLayer.fillColor = UIColor.systemBlue.withAlphaComponent(0.08).cgColor
        eraserLayer.lineWidth = 1.5
        eraserLayer.isHidden = true
        layer.addSublayer(eraserLayer)
    }
    
    private func setupTextBoxLayer() {
        textBoxLayer.strokeColor = UIColor.systemBlue.withAlphaComponent(0.8).cgColor
        textBoxLayer.fillColor = UIColor.clear.cgColor
        textBoxLayer.lineWidth = 1.5
        textBoxLayer.lineDashPattern = [6, 4]
        textBoxLayer.isHidden = true
        layer.addSublayer(textBoxLayer)
    }

    private func setupFormFieldHighlights() {
        formFieldHighlightLayer.fillColor = UIColor.systemBlue.withAlphaComponent(0.18).cgColor
        formFieldHighlightLayer.strokeColor = UIColor.clear.cgColor
        formFieldHighlightLayer.lineWidth = 0
        formFieldHighlightLayer.isHidden = true
        formFieldHighlightLayer.removeFromSuperlayer()
        formFieldHighlightHostView.layer.addSublayer(formFieldHighlightLayer)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePageOrScaleChange),
            name: .PDFViewPageChanged,
            object: self
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePageOrScaleChange),
            name: .PDFViewScaleChanged,
            object: self
        )
    }

    @objc private func handlePageOrScaleChange() {
        updateFormFieldHighlights()
    }

    /// Resolves the `PDFAnnotation` for the widget whose `UITextField` / `UITextView` is `focused`, using a hit at the control’s center.
    private func formWidgetAnnotationOwningFirstResponderIfKnown(_ focused: UIView? = nil) -> PDFAnnotation? {
        guard let focused = focused ?? pdfHostedTextInputWithFocus(in: self) else { return nil }
        guard focused is UITextField || focused is UITextView else { return nil }
        let center = CGPoint(x: focused.bounds.midX, y: focused.bounds.midY)
        let pointInView = convert(center, from: focused)
        guard let page = page(for: pointInView, nearest: true) else { return nil }
        let pointInPage = convert(pointInView, to: page)
        guard let ann = page.annotation(at: pointInPage) else { return nil }
        let widgetSubtype = PDFAnnotationSubtype.widget.rawValue
        let looksLikeWidget = ann.type == widgetSubtype
            || ann.fieldName != nil
            || !ann.widgetFieldType.rawValue.isEmpty
        return looksLikeWidget ? ann : nil
    }

    private func updateFormFieldHighlights() {
        guard isFormMode, let document, documentView != nil else {
            formFieldHighlightLayer.isHidden = true
            formFieldHighlightHostView.isHidden = true
            return
        }

        formFieldHighlightHostView.isHidden = false
        formFieldHighlightLayer.isHidden = false
        formFieldHighlightLayer.frame = formFieldHighlightHostView.bounds

        let focusedInput = pdfHostedTextInputWithFocus(in: self)
        let excludedAnnotation = formWidgetAnnotationOwningFirstResponderIfKnown(focusedInput)
        let exclusionRectFallback: CGRect?
        if focusedInput != nil, excludedAnnotation == nil, let f = focusedInput {
            exclusionRectFallback = formFieldHighlightHostView.convert(f.bounds, from: f).insetBy(dx: -6, dy: -6)
        } else {
            exclusionRectFallback = nil
        }

        let path = UIBezierPath()
        var didFindWidgets = false
        let widgetSubtype = PDFAnnotationSubtype.widget.rawValue
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            for annotation in page.annotations {
                guard annotation.type != "Ink" else { continue }
                let isWidgetSubtype = annotation.type == widgetSubtype
                let hasFieldName = annotation.fieldName != nil
                let hasWidgetFieldKind = !annotation.widgetFieldType.rawValue.isEmpty
                guard isWidgetSubtype || hasFieldName || hasWidgetFieldKind else { continue }
                guard annotation.bounds.width > 0, annotation.bounds.height > 0 else { continue }
                let ffFlags = (annotation.value(forAnnotationKey: PDFAnnotationKey(rawValue: "/Ff")) as? NSNumber)?.intValue ?? 0
                let fFlags  = (annotation.value(forAnnotationKey: PDFAnnotationKey(rawValue: "/F"))  as? NSNumber)?.intValue ?? 0
                let isReadOnly       = (ffFlags & 1)   != 0  // /Ff bit 0
                let isAnnotationLocked = (fFlags & 128) != 0  // /F  bit 8
                let shouldHighlight: Bool
                if let filter = formFieldHighlightFilter {
                    let info = PDFFormFieldInfo(
                        fieldName: annotation.fieldName,
                        isReadOnly: isReadOnly,
                        isAnnotationLocked: isAnnotationLocked
                    )
                    shouldHighlight = filter(info)
                } else {
                    // Default: skip fields that are read-only or annotation-locked.
                    shouldHighlight = !isReadOnly && !isAnnotationLocked
                }
                guard shouldHighlight else { continue }
                if let ex = excludedAnnotation, annotation === ex { continue }
                let rectInView = convert(annotation.bounds, from: page)
                let rectInHost = formFieldHighlightHostView.convert(rectInView, from: self)
                if let exRect = exclusionRectFallback {
                    let inter = rectInHost.intersection(exRect)
                    let annArea = max(rectInHost.width * rectInHost.height, 1)
                    let overlapRatio = (inter.width * inter.height) / annArea
                    if overlapRatio > 0.3 {
                        continue
                    }
                }
                didFindWidgets = true
                let rounded = UIBezierPath(roundedRect: rectInHost, cornerRadius: 3)
                path.append(rounded)
            }
        }
        formFieldHighlightLayer.path = path.cgPath
        formFieldHighlightLayer.isHidden = !didFindWidgets
    }
    
    // MARK: - Drawing Gesture
    
    private func setupTextBoxGesture() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleTextBoxPan(_:)))
        pan.cancelsTouchesInView = true
        pan.maximumNumberOfTouches = 1
        pan.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue),
            NSNumber(value: UITouch.TouchType.pencil.rawValue)
        ]
        pan.delegate = self
        addGestureRecognizer(pan)
        textBoxPanGesture = pan
        textBoxPanGesture?.isEnabled = false
    }

    private func handleTextModeTap(at point: CGPoint) {
        if let textBox = textBoxViewAtPoint(point) {
            // Tap landed on an existing text box — select and begin editing.
            selectTextBox(id: textBox.id)
            textBox.beginEditing()
        } else if textBoxViews.values.contains(where: { $0.isTextInputFirstResponder }) {
            // A text box is currently being edited — outside tap dismisses it.
            endOverlayTextEditing()
            deselectOverlaySelection()
        } else {
            // Nothing active, empty canvas — create a new auto-sizing text box here.
            createTapTextBox(at: point)
        }
    }

    /// Hit-tests `textBoxOverlayView` at `pointInSelf` and walks up the view
    /// hierarchy to find the enclosing `TextBoxView`, if any.
    private func textBoxViewAtPoint(_ point: CGPoint) -> TextBoxView? {
        let pointInOverlay = textBoxOverlayView.convert(point, from: self)
        var view = textBoxOverlayView.hitTest(pointInOverlay, with: nil)
        while let v = view {
            if let box = v as? TextBoxView { return box }
            if v === textBoxOverlayView { break }
            view = v.superview
        }
        return nil
    }

    // MARK: - Pencil Touch Handlers (called by PencilDrawingGestureRecognizer)
    
    func pencilTouchBegan(_ touch: UITouch, with event: UIEvent?) {
        guard isDrawingMode || isEraserMode else { return }
        let viewPoint = touch.location(in: self)
        guard let page = self.page(for: viewPoint, nearest: true) else { return }
        let pagePoint = self.convert(viewPoint, to: page)
        currentPDFPage = page
        currentStrokePoints = [pagePoint]
        
        if isEraserMode {
            eraserRootByAnnotationID.removeAll()
            eraserRootAnnotations.removeAll()
            eraserCurrentAnnotations.removeAll()
            showEraserCircle(at: viewPoint)
            eraseAnnotation(at: pagePoint, on: page)
        } else {
            let dot = buildInkAnnotation(from: [pagePoint], color: currentInkColor, lineWidth: currentLineWidth)
            page.addAnnotation(dot)
            currentAnnotation = dot
        }
    }
    
    func pencilTouchMoved(_ touch: UITouch, with event: UIEvent?) {
        guard isDrawingMode || isEraserMode,
              let page = currentPDFPage else { return }
        
        let coalescedTouches = event?.coalescedTouches(for: touch) ?? [touch]
        for coalescedTouch in coalescedTouches {
            let pagePoint = self.convert(coalescedTouch.location(in: self), to: page)
            if isEraserMode {
                showEraserCircle(at: coalescedTouch.location(in: self))
                eraseAnnotation(at: pagePoint, on: page)
            } else {
                currentStrokePoints.append(pagePoint)
            }
        }
        
        if !isEraserMode {
            updateLiveAnnotation(on: page)
        }
    }
    
    func pencilTouchEnded(_ touch: UITouch, with event: UIEvent?) {
        guard isDrawingMode || isEraserMode,
              let page = currentPDFPage else { return }
        
        if !isEraserMode {
            let pagePoint = self.convert(touch.location(in: self), to: page)
            currentStrokePoints.append(pagePoint)
            commitStroke(on: page)
        } else {
            let oldAnnotations = Array(eraserRootAnnotations.values)
            let newAnnotations = Array(eraserCurrentAnnotations.values)
            if !oldAnnotations.isEmpty || !newAnnotations.isEmpty {
                formViewModel?.didMakeChange(.drawingSession(
                    page: page,
                    oldAnnotations: oldAnnotations,
                    newAnnotations: newAnnotations
                ))
            }
            hideEraserCircle()
        }
        
        currentStrokePoints = []
        currentPDFPage = nil
    }
    
    func pencilTouchCancelled(with event: UIEvent?) {
        guard isDrawingMode else { return }
        
        if let page = currentPDFPage, !currentStrokePoints.isEmpty {
            commitStroke(on: page)
        }
        
        if isEraserMode, let page = currentPDFPage {
            let oldAnnotations = Array(eraserRootAnnotations.values)
            let newAnnotations = Array(eraserCurrentAnnotations.values)
            if !oldAnnotations.isEmpty || !newAnnotations.isEmpty {
                formViewModel?.didMakeChange(.drawingSession(
                    page: page,
                    oldAnnotations: oldAnnotations,
                    newAnnotations: newAnnotations
                ))
            }
        }
        
        hideEraserCircle()
        currentStrokePoints = []
        currentPDFPage = nil
    }
    
    // MARK: - Live Stroke (updates annotation as user draws)
    
    private func updateLiveAnnotation(on page: PDFPage) {
        guard currentStrokePoints.count >= 2 else { return }
        
        if let existing = currentAnnotation {
            page.removeAnnotation(existing)
        }
        
        let annotation = buildInkAnnotation(
            from: currentStrokePoints,
            color: currentInkColor,
            lineWidth: currentLineWidth
        )
        
        page.addAnnotation(annotation)
        currentAnnotation = annotation
    }
    
    // MARK: - Commit Stroke
    
    private func commitStroke(on page: PDFPage) {
        guard currentStrokePoints.count >= 2 else {
            currentStrokePoints = []
            currentAnnotation = nil
            currentPDFPage = nil
            return
        }
        
        // Remove live annotation
        if let existing = currentAnnotation {
            page.removeAnnotation(existing)
        }
        
        // Create final annotation
        let annotation = buildInkAnnotation(
            from: currentStrokePoints,
            color: currentInkColor,
            lineWidth: currentLineWidth
        )
        
        page.addAnnotation(annotation)
        
        // Record for undo
        formViewModel?.didMakeChange(.drawingSession(
            page: page,
            oldAnnotations: [],
            newAnnotations: [annotation]
        ))
        
        print("✅ Committed stroke with \(currentStrokePoints.count) points")
        
        // Reset
        currentStrokePoints = []
        currentAnnotation = nil
        currentPDFPage = nil
    }
    
    // MARK: - Build Annotation
    
    /// Reduces high-frequency jitter in raw touch input using a weighted moving average
    /// (weights 1:2:1). Endpoints are preserved. Multiple iterations give stronger smoothing.
    private func denoisedPoints(_ points: [CGPoint], iterations: Int = 3) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var result = points
        for _ in 0..<iterations {
            var pass = [result[0]]
            for i in 1..<(result.count - 1) {
                pass.append(CGPoint(
                    x: (result[i - 1].x + result[i].x * 2 + result[i + 1].x) / 4,
                    y: (result[i - 1].y + result[i].y * 2 + result[i + 1].y) / 4
                ))
            }
            pass.append(result[result.count - 1])
            result = pass
        }
        return result
    }

    /// Builds a smooth UIBezierPath through the given points using Catmull-Rom splines
    /// (converted to cubic Bézier segments). For 2 points or fewer, falls back to a
    /// straight line so short taps still render correctly.
    private func smoothPath(through points: [CGPoint]) -> UIBezierPath {
        let path = UIBezierPath()
        guard points.count >= 2 else {
            if let p = points.first { path.move(to: p) }
            return path
        }

        path.move(to: points[0])

        guard points.count > 2 else {
            path.addLine(to: points[1])
            return path
        }

        // Catmull-Rom → cubic Bézier: for each segment i→i+1, the control points are:
        //   cp1 = points[i]     + (points[i+1] - points[i-1]) / 6
        //   cp2 = points[i+1]   - (points[i+2] - points[i])   / 6
        // Boundary: duplicate first/last point so every segment has four neighbours.
        let n = points.count
        for i in 0..<(n - 1) {
            let p0 = points[max(i - 1, 0)]
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = points[min(i + 2, n - 1)]

            let cp1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6,
                              y: p1.y + (p2.y - p0.y) / 6)
            let cp2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6,
                              y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, controlPoint1: cp1, controlPoint2: cp2)
        }
        return path
    }

    private func buildInkAnnotation(from points: [CGPoint], color: UIColor, lineWidth: CGFloat) -> PDFAnnotation {

        // Handle single point — draw a dot
        let resolvedPoints: [CGPoint]
        if points.count == 1 {
            let p = points[0]
            resolvedPoints = [p, CGPoint(x: p.x + 0.5, y: p.y + 0.5)]
        } else {
            resolvedPoints = points
        }

        let cleanPoints = denoisedPoints(resolvedPoints)
        let path = smoothPath(through: cleanPoints)
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        let bounds = path.bounds.insetBy(dx: -lineWidth * 2, dy: -lineWidth * 2)

        let annotation = PDFAnnotation(bounds: bounds, forType: .ink, withProperties: nil)
        annotation.color = color
        annotation.border = PDFBorder()
        annotation.border?.lineWidth = lineWidth
        annotation.shouldDisplay = true
        annotation.shouldPrint = true
        annotation.contents = "ink:\(lineWidth)"

        // Rebuild the path in annotation-local coordinates
        let offset = bounds.origin
        let shiftedPoints = cleanPoints.map { CGPoint(x: $0.x - offset.x, y: $0.y - offset.y) }
        let shifted = smoothPath(through: shiftedPoints)
        shifted.lineWidth = lineWidth
        shifted.lineCapStyle = .round
        shifted.lineJoinStyle = .round

        annotation.add(shifted)

        return annotation
    }
    
    private func showEraserCircle(at viewPoint: CGPoint) {
        eraserLocation = viewPoint
        updateEraserCircle()
        eraserLayer.isHidden = false
    }
    
    private func hideEraserCircle() {
        eraserLayer.isHidden = true
        eraserLocation = nil
    }
    
    private func updateEraserCircle() {
        guard let location = eraserLocation else { return }
        let diameter = eraserRadius * 2
        let rect = CGRect(
            x: location.x - eraserRadius,
            y: location.y - eraserRadius,
            width: diameter,
            height: diameter
        )
        eraserLayer.path = UIBezierPath(ovalIn: rect).cgPath
    }
    
    @objc private func handleTextBoxPan(_ gesture: UIPanGestureRecognizer) {
        guard isTextMode else { return }
        let viewPoint = gesture.location(in: self)

        switch gesture.state {
        case .began:
            textBoxStartPoint = viewPoint
            // Record whether the gesture started on an existing text box so we
            // can decide later whether to create a new box or edit the existing one.
            textBoxPanStartedOnExistingBox = (textBoxViewAtPoint(viewPoint) != nil)
            if !textBoxPanStartedOnExistingBox {
                updateTextBoxPreview(from: viewPoint, to: viewPoint)
                textBoxLayer.isHidden = false
            }
        case .changed:
            guard let start = textBoxStartPoint, !textBoxPanStartedOnExistingBox else { return }
            updateTextBoxPreview(from: start, to: viewPoint)
        case .ended, .cancelled:
            guard let start = textBoxStartPoint else { return }
            textBoxLayer.isHidden = true
            textBoxStartPoint = nil
            let startedOnBox = textBoxPanStartedOnExistingBox
            textBoxPanStartedOnExistingBox = false

            if startedOnBox {
                // Gesture started on an existing text box — treat as a tap to edit it.
                if let textBox = textBoxViewAtPoint(start) {
                    selectTextBox(id: textBox.id)
                    textBox.beginEditing()
                }
            } else {
                let rectInView = rectFrom(start, to: viewPoint).insetBy(dx: -2, dy: -2)
                if rectInView.width >= 20, rectInView.height >= 20 {
                    // Sufficient drag on empty space — create a new text box.
                    createOverlayTextBox(with: rectInView)
                } else {
                    // Short movement on empty space — same logic as a pure tap:
                    // dismiss if a box is editing, otherwise create a new one.
                    let anyBoxEditing = textBoxViews.values.contains { $0.isTextInputFirstResponder }
                    if anyBoxEditing {
                        endOverlayTextEditing()
                        deselectOverlaySelection()
                    } else {
                        createTapTextBox(at: start)
                    }
                }
            }
        default:
            break
        }
    }
    
    private func updateTextBoxPreview(from start: CGPoint, to end: CGPoint) {
        let rect = rectFrom(start, to: end)
        textBoxLayer.path = UIBezierPath(rect: rect).cgPath
    }

    // MARK: - Shape Pan Gesture

    @objc private func handleShapePan(_ gesture: UIPanGestureRecognizer) {
        guard isShapeMode else { return }
        let viewPoint = gesture.location(in: self)
        switch gesture.state {
        case .began:
            shapeStartPoint = viewPoint
            shapePreviewLayer.isHidden = false
            updateShapePreview(from: viewPoint, to: viewPoint)
        case .changed:
            guard let start = shapeStartPoint else { return }
            updateShapePreview(from: start, to: viewPoint)
        case .ended, .cancelled:
            guard let start = shapeStartPoint else { return }
            shapePreviewLayer.isHidden = true
            shapeStartPoint = nil
            let rectInView = rectFrom(start, to: viewPoint).insetBy(dx: -2, dy: -2)
            if rectInView.width >= 20, rectInView.height >= 20 {
                createOverlayShape(with: rectInView)
            }
        default:
            break
        }
    }

    private func updateShapePreview(from start: CGPoint, to end: CGPoint) {
        let rect = rectFrom(start, to: end)
        switch currentShapeKind {
        case .circle:
            shapePreviewLayer.path = UIBezierPath(ovalIn: rect).cgPath
        case .rectangle:
            shapePreviewLayer.path = UIBezierPath(roundedRect: rect, cornerRadius: 4).cgPath
        case .triangle:
            let path = UIBezierPath()
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.close()
            shapePreviewLayer.path = path.cgPath
        }
    }

    private func createOverlayShape(with rectInView: CGRect) {
        guard let docView = documentView else { return }
        let rectInDoc = convert(rectInView, to: docView)
        let normalised = CGRect(
            origin: rectInDoc.origin,
            size: CGSize(width: max(rectInDoc.width, 30), height: max(rectInDoc.height, 30))
        )
        let state = OverlayShapeState(
            id: UUID(),
            frame: normalised,
            kind: currentShapeKind,
            strokeColor: shapeStrokeColor,
            lineWidth: shapeLineWidth
        )
        addOverlayShape(from: state)
        formViewModel?.didMakeChange(.overlayShape(add: state, remove: nil))
    }

    // MARK: - Shape Overlay Management

    func addOverlayShape(from state: OverlayShapeState) {
        let box = ShapeBoxView(id: state.id, kind: state.kind, strokeColor: state.strokeColor, lineWidth: state.lineWidth)
        box.frame = state.frame
        box.setSelectMode(isSelectMode)
        box.onSelect = { [weak self] id in self?.selectShapeBox(id: id) }
        box.onEndChange = { [weak self] before, after in
            guard before.frame != after.frame else { return }
            self?.formViewModel?.didMakeChange(.overlayShapeUpdate(before: before, after: after))
        }
        textBoxOverlayView.addSubview(box)
        shapeBoxViews[state.id] = box
    }

    func removeOverlayShape(id: UUID) {
        shapeBoxViews[id]?.removeFromSuperview()
        shapeBoxViews[id] = nil
        if selectedShapeID == id {
            selectedShapeID = nil
            syncOverlaySelectionState()
        }
    }

    func overlayShapeState(id: UUID) -> OverlayShapeState? {
        guard let box = shapeBoxViews[id] else { return nil }
        return OverlayShapeState(id: id, frame: box.frame, kind: box.shapeKind, strokeColor: box.strokeColor, lineWidth: box.lineWidth)
    }

    func updateOverlayShape(from state: OverlayShapeState) {
        guard let box = shapeBoxViews[state.id] else { return }
        box.frame = state.frame
        box.applyStyle(kind: state.kind, strokeColor: state.strokeColor, lineWidth: state.lineWidth)
    }

    func applyImageBorderToSelected(borderWidth: CGFloat, borderColor: UIColor) {
        guard let id = selectedImageBoxID, let box = imageBoxViews[id] else { return }
        let before = OverlayImageState(id: id, frame: box.frame, imageData: box.imageData, borderWidth: box.imageBorderWidth, borderColor: box.imageBorderColor)
        if abs(before.borderWidth - borderWidth) < 0.001, before.borderColor.isEqual(borderColor) { return }
        box.updateBorder(width: borderWidth, color: borderColor)
        let after = OverlayImageState(id: id, frame: box.frame, imageData: box.imageData, borderWidth: borderWidth, borderColor: borderColor)
        if before.borderWidth != after.borderWidth || !before.borderColor.isEqual(after.borderColor) {
            formViewModel?.didMakeChange(.overlayImageUpdate(before: before, after: after))
        }
    }

    func applyTextBorderToSelected(borderWidth: CGFloat, borderColor: UIColor) {
        guard let id = selectedTextBoxID,
              let box = textBoxViews[id],
              let before = overlayTextBoxState(id: id) else { return }
        // Selection syncs these properties from the box; skip to avoid churn and feedback loops with .onChange.
        if abs(before.borderWidth - borderWidth) < 0.001, before.borderColor.isEqual(borderColor) { return }
        box.updateBorder(width: borderWidth, color: borderColor)
        let after = overlayTextBoxState(id: id)!
        if before.borderWidth != after.borderWidth || !before.borderColor.isEqual(after.borderColor) {
            formViewModel?.didMakeChange(.overlayTextBoxUpdate(before: before, after: after))
        }
    }

    func updateOverlayTextBox(from state: OverlayTextBoxState) {
        guard let box = textBoxViews[state.id] else { return }
        box.frame = state.frame
        box.setText(state.text)
        box.setBackground(state.backgroundColor)
        box.setFontSize(state.fontSize, isBold: state.isBold)
        box.setTextColor(state.textColor)
        box.setTextAlignment(state.textAlignment)
        box.setVerticalAlignment(state.verticalAlignment)
        box.setAutoResize(state.autoResizeEnabled)
        box.updateBorder(width: state.borderWidth, color: state.borderColor)
        if selectedTextBoxID == state.id {
            formViewModel?.selectedTextBoxAutoResize = state.autoResizeEnabled
            formViewModel?.selectedTextBoxBorderWidth = state.borderWidth
            formViewModel?.selectedTextBoxBorderColor = state.borderColor
        }
    }

    func applyShapeStyleToSelected(kind: OverlayShapeKind, strokeColor: UIColor, lineWidth: CGFloat) {
        guard let id = selectedShapeID, let box = shapeBoxViews[id] else { return }
        let before = OverlayShapeState(id: id, frame: box.frame, kind: box.shapeKind, strokeColor: box.strokeColor, lineWidth: box.lineWidth)
        box.applyStyle(kind: kind, strokeColor: strokeColor, lineWidth: lineWidth)
        let after = OverlayShapeState(id: id, frame: box.frame, kind: kind, strokeColor: strokeColor, lineWidth: lineWidth)
        if before.kind != after.kind || before.strokeColor != after.strokeColor || before.lineWidth != after.lineWidth {
            formViewModel?.didMakeChange(.overlayShapeUpdate(before: before, after: after))
        }
    }

    private func selectShapeBox(id: UUID) {
        selectedShapeID = id
        selectedTextBoxID = nil
        selectedImageBoxID = nil
        deselectInkAnnotation()
        formViewModel?.selectedOverlayKind = .shape
        if let box = shapeBoxViews[id] {
            formViewModel?.activeShapeKind = box.shapeKind
            formViewModel?.shapeStrokeColor = box.strokeColor
            formViewModel?.shapeLineWidth = box.lineWidth
        }
        updateOverlaySelectionUI()
        if let box = shapeBoxViews[id] {
            textBoxOverlayView.bringSubviewToFront(box)
        }
    }

    private func rectFrom(_ start: CGPoint, to end: CGPoint) -> CGRect {
        let origin = CGPoint(x: min(start.x, end.x), y: min(start.y, end.y))
        let size = CGSize(width: abs(end.x - start.x), height: abs(end.y - start.y))
        return CGRect(origin: origin, size: size)
    }
    
    private func createOverlayTextBox(with rectInView: CGRect) {
        guard let docView = documentView else { return }
        let rectInDoc = convert(rectInView, to: docView)
        let normalizedRect = CGRect(
            x: rectInDoc.origin.x,
            y: rectInDoc.origin.y,
            width: max(rectInDoc.width, 80),
            height: max(rectInDoc.height, 40)
        )

        let state = OverlayTextBoxState(
            id: UUID(),
            frame: normalizedRect,
            text: "",
            backgroundColor: textBoxBackgroundColor,
            fontSize: textBoxFontSize,
            isBold: textBoxIsBold,
            textColor: textBoxTextColor,
            textAlignment: textBoxTextAlignment,
            verticalAlignment: textBoxVerticalAlignment,
            autoResizeEnabled: textBoxAutoResize,
            borderWidth: textBoxBorderWidth,
            borderColor: textBoxBorderColor
        )
        addOverlayTextBox(from: state, beginEditing: true)
        formViewModel?.didMakeChange(.overlayTextBox(add: state, remove: nil))
    }

    /// Creates a minimal text box at a tap point that auto-expands horizontally as
    /// the user types, growing up to the right edge of the underlying PDF page, then
    /// wraps and expands vertically for new lines.
    private func createTapTextBox(at viewPoint: CGPoint) {
        guard let docView = documentView else { return }
        let pointInDoc = docView.convert(viewPoint, from: self)

        // Compute the right edge of the PDF page that was tapped, in document-view
        // coordinates. This becomes the horizontal cap for the auto-resize.
        let maxWidth: CGFloat
        if let page = self.page(for: viewPoint, nearest: true) {
            let pageBounds = page.bounds(for: .mediaBox)
            // Use the vertical midpoint of the page so the X conversion is stable.
            let pageRightInView = convert(
                CGPoint(x: pageBounds.maxX, y: pageBounds.midY), from: page
            )
            let pageRightInDoc = docView.convert(pageRightInView, from: self)
            maxWidth = max(80, pageRightInDoc.x - pointInDoc.x)
        } else {
            maxWidth = max(80, docView.bounds.width - pointInDoc.x)
        }

        // Start with a single-line-height frame. The box expands as the user types.
        let lineHeight = textBoxFontSize + 12   // 6 pt top + 6 pt bottom padding
        let initialFrame = CGRect(
            x: pointInDoc.x,
            y: pointInDoc.y,
            width: 40,
            height: max(30, lineHeight)
        )

        let state = OverlayTextBoxState(
            id: UUID(),
            frame: initialFrame,
            text: "",
            backgroundColor: textBoxBackgroundColor,
            fontSize: textBoxFontSize,
            isBold: textBoxIsBold,
            textColor: textBoxTextColor,
            textAlignment: textBoxTextAlignment,
            verticalAlignment: textBoxVerticalAlignment,
            autoResizeEnabled: textBoxAutoResize,
            borderWidth: textBoxBorderWidth,
            borderColor: textBoxBorderColor
        )
        addOverlayTextBox(from: state, beginEditing: true, tapCreateMaxWidth: maxWidth)
        formViewModel?.didMakeChange(.overlayTextBox(add: state, remove: nil))
    }
    
    func addOverlayTextBox(from state: OverlayTextBoxState, beginEditing: Bool = false, tapCreateMaxWidth: CGFloat? = nil) {
        let box = TextBoxView(id: state.id)
        box.frame = state.frame
        box.setText(state.text)
        box.setBackground(state.backgroundColor)
        box.setFontSize(state.fontSize, isBold: state.isBold)
        box.setTextColor(state.textColor)
        box.setTextAlignment(state.textAlignment)
        box.setVerticalAlignment(state.verticalAlignment)
        box.setAutoResize(state.autoResizeEnabled)
        box.updateBorder(width: state.borderWidth, color: state.borderColor)
        if let maxWidth = tapCreateMaxWidth {
            box.setTapCreateAutoResize(enabled: true, maxWidth: maxWidth)
        }
        box.onSelect = { [weak self] id in
            self?.selectTextBox(id: id)
        }
        box.onTextEditingFocusChange = { [weak self] in
            self?.syncOverlayCanvasDismissTap()
        }
        box.setSelectMode(isSelectMode)
        textBoxOverlayView.addSubview(box)
        textBoxOverlayView.bringSubviewToFront(box)
        textBoxViews[state.id] = box
        syncScribbleInteraction()
        if beginEditing {
            box.beginEditing()
        }
    }
    
    func removeOverlayTextBox(id: UUID) {
        if let box = textBoxViews[id] {
            box.removeFromSuperview()
            textBoxViews[id] = nil
        }
        if selectedTextBoxID == id {
            selectedTextBoxID = nil
            syncOverlaySelectionState()
        }
    }
    
    func overlayTextBoxState(id: UUID) -> OverlayTextBoxState? {
        guard let box = textBoxViews[id] else { return nil }
        return OverlayTextBoxState(
            id: id,
            frame: box.frame,
            text: box.currentText,
            backgroundColor: box.currentBackgroundColor,
            fontSize: box.currentFontSize,
            isBold: box.currentIsBold,
            textColor: box.currentTextColor,
            textAlignment: box.currentTextAlignment,
            verticalAlignment: box.currentVerticalAlignment,
            autoResizeEnabled: box.currentAutoResize,
            borderWidth: box.currentBorderWidth,
            borderColor: box.currentBorderColor
        )
    }

    func setSelectedTextBoxAutoResize(_ enabled: Bool) {
        guard let id = selectedTextBoxID, let box = textBoxViews[id] else { return }
        box.setAutoResize(enabled)
    }
    
    func applyTextStyleToSelectedTextBox(fontSize: CGFloat, isBold: Bool, textColor: UIColor, backgroundColor: UIColor, textAlignment: NSTextAlignment, verticalAlignment: TextVerticalAlignment) {
        guard let selectedTextBoxID,
              let box = textBoxViews[selectedTextBoxID] else { return }
        box.applyTextStyle(fontSize: fontSize, isBold: isBold, textColor: textColor)
        box.setBackground(backgroundColor)
        box.setTextAlignment(textAlignment)
        box.setVerticalAlignment(verticalAlignment)
    }
    
    func addOverlayImage(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        let state = overlayImageStateForNewImage(data: data)
        addOverlayImage(from: state)
        formViewModel?.didMakeChange(.overlayImage(add: state, remove: nil))
    }
    
    /// Places (or replaces) an overlay image in the bounds of a PDF button/signature widget (e.g. “attach image” fields).
    func addOverlayImage(_ image: UIImage, forFormWidget annotation: PDFAnnotation, on page: PDFPage) {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        let insetBounds = annotation.bounds.insetBy(dx: 3, dy: 3)
        guard insetBounds.width > 4, insetBounds.height > 4 else { return }
        let docRect = docRect(fromPageRect: insetBounds, on: page)
        let pageIndex = document?.index(for: page) ?? -1
        
        var removed: OverlayImageState?
        if pageIndex >= 0 {
            for (id, box) in imageBoxViews {
                guard let info = pageRect(fromDocRect: box.frame), info.pageIndex == pageIndex else { continue }
                let center = CGPoint(x: info.pageRect.midX, y: info.pageRect.midY)
                if annotation.bounds.contains(center), let state = overlayImageState(id: id) {
                    removed = state
                    removeOverlayImage(id: id)
                    break
                }
            }
        }
        
        let borderW = formViewModel?.imageBorderWidth ?? 0
        let borderC = formViewModel?.imageBorderColor ?? .black
        let state = OverlayImageState(id: UUID(), frame: docRect, imageData: data, borderWidth: borderW, borderColor: borderC)
        addOverlayImage(from: state)
        formViewModel?.didMakeChange(.overlayImage(add: state, remove: removed))
    }
    
    func addOverlayImage(from state: OverlayImageState) {
        let box = ImageBoxView(id: state.id, imageData: state.imageData)
        box.frame = state.frame
        box.updateBorder(width: state.borderWidth, color: state.borderColor)
        box.setSelectMode(isSelectMode)
        box.onSelect = { [weak self] id in
            self?.selectImageBox(id: id)
        }
        box.onEndChange = { [weak self] before, after in
            guard before.frame != after.frame else { return }
            self?.formViewModel?.didMakeChange(.overlayImageUpdate(before: before, after: after))
        }
        textBoxOverlayView.addSubview(box)
        imageBoxViews[state.id] = box
    }

    func updateOverlayImage(from state: OverlayImageState) {
        guard let box = imageBoxViews[state.id] else { return }
        box.frame = state.frame
        box.setImageData(state.imageData)
        box.updateBorder(width: state.borderWidth, color: state.borderColor)
    }
    
    func removeOverlayImage(id: UUID) {
        if let box = imageBoxViews[id] {
            box.removeFromSuperview()
            imageBoxViews[id] = nil
        }
        if selectedImageBoxID == id {
            selectedImageBoxID = nil
            syncOverlaySelectionState()
        }
    }
    
    func overlayImageState(id: UUID) -> OverlayImageState? {
        guard let box = imageBoxViews[id] else { return nil }
        return OverlayImageState(
            id: id,
            frame: box.frame,
            imageData: box.imageData,
            borderWidth: box.imageBorderWidth,
            borderColor: box.imageBorderColor
        )
    }

    func deleteSelectedOverlayObject() {
        if let selectedTextBoxID, let state = overlayTextBoxState(id: selectedTextBoxID) {
            removeOverlayTextBox(id: selectedTextBoxID)
            formViewModel?.didMakeChange(.overlayTextBox(add: nil, remove: state))
            formViewModel?.selectedOverlayKind = nil
            return
        }
        if let selectedImageBoxID, let state = overlayImageState(id: selectedImageBoxID) {
            removeOverlayImage(id: selectedImageBoxID)
            formViewModel?.didMakeChange(.overlayImage(add: nil, remove: state))
            formViewModel?.selectedOverlayKind = nil
            return
        }
        if let selectedShapeID, let state = overlayShapeState(id: selectedShapeID) {
            removeOverlayShape(id: selectedShapeID)
            formViewModel?.didMakeChange(.overlayShape(add: nil, remove: state))
            formViewModel?.selectedOverlayKind = nil
        }
    }

    func endOverlayTextEditing() {
        textBoxViews.values.forEach { $0.endEditingIfNeeded() }
        textBoxOverlayView.endEditing(true)
        syncOverlayCanvasDismissTap()
    }

    private func selectTextBox(id: UUID) {
        selectedTextBoxID = id
        selectedImageBoxID = nil
        selectedShapeID = nil
        deselectInkAnnotation()
        formViewModel?.selectedOverlayKind = .textBox
        if let box = textBoxViews[id] {
            formViewModel?.selectedTextBoxAutoResize = box.currentAutoResize
            formViewModel?.selectedTextBoxBorderWidth = box.currentBorderWidth
            formViewModel?.selectedTextBoxBorderColor = box.currentBorderColor
            textBoxOverlayView.bringSubviewToFront(box)
        }
        updateOverlaySelectionUI()
    }

    private func selectImageBox(id: UUID) {
        selectedImageBoxID = id
        selectedTextBoxID = nil
        selectedShapeID = nil
        deselectInkAnnotation()
        formViewModel?.selectedOverlayKind = .image
        if let box = imageBoxViews[id] {
            formViewModel?.imageBorderWidth = box.imageBorderWidth
            formViewModel?.imageBorderColor = box.imageBorderColor
        }
        updateOverlaySelectionUI()
        if let box = imageBoxViews[id] {
            textBoxOverlayView.bringSubviewToFront(box)
        }
    }

    private func updateOverlaySelectionUI() {
        for (id, box) in textBoxViews {
            box.setSelected(id == selectedTextBoxID)
        }
        for (id, box) in imageBoxViews {
            box.setSelected(id == selectedImageBoxID)
        }
        for (id, box) in shapeBoxViews {
            box.setSelected(id == selectedShapeID)
        }
        syncOverlaySelectionState()
        syncOverlayCanvasDismissTap()
    }

    private func syncOverlaySelectionState() {
        formViewModel?.hasSelectedOverlayObject = (selectedTextBoxID != nil || selectedImageBoxID != nil || selectedShapeID != nil)
    }

    func deselectOverlaySelection() {
        selectedTextBoxID = nil
        selectedImageBoxID = nil
        selectedShapeID = nil
        formViewModel?.selectedOverlayKind = nil
        updateOverlaySelectionUI()
    }

    func writeOverlayMetadata() {
        guard let document else { return }
        
        let metadata = overlayMetadataSnapshot()
        let isEmpty = metadata.textBoxes.isEmpty && metadata.images.isEmpty && metadata.shapes.isEmpty
        
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            for annotation in page.annotations where annotation.contents?.hasPrefix(overlayMetadataPrefix) == true || annotation.contents?.hasPrefix(overlayMetadataPartPrefix) == true {
                page.removeAnnotation(annotation)
            }
        }
        
        guard !isEmpty else { return }
        
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(metadata) else { return }
        let base64 = data.base64EncodedString()
        
        guard let firstPage = document.page(at: 0) else { return }
        let maxChunkSize = 20000
        let chunks = stride(from: 0, to: base64.count, by: maxChunkSize).map { start -> String in
            let startIndex = base64.index(base64.startIndex, offsetBy: start)
            let endIndex = base64.index(startIndex, offsetBy: min(maxChunkSize, base64.count - start))
            return String(base64[startIndex..<endIndex])
        }
        
        if chunks.count == 1 {
            let contents = overlayMetadataPrefix + chunks[0]
            let annotation = PDFAnnotation(bounds: CGRect(x: 0, y: 0, width: 1, height: 1), forType: .text, withProperties: nil)
            annotation.contents = contents
            annotation.shouldDisplay = false
            annotation.shouldPrint = false
            firstPage.addAnnotation(annotation)
        } else {
            for (index, chunk) in chunks.enumerated() {
                let contents = "\(overlayMetadataPartPrefix)\(index+1)/\(chunks.count):" + chunk
                let annotation = PDFAnnotation(bounds: CGRect(x: 0, y: 0, width: 1, height: 1), forType: .text, withProperties: nil)
                annotation.contents = contents
                annotation.shouldDisplay = false
                annotation.shouldPrint = false
                firstPage.addAnnotation(annotation)
            }
        }
    }
    
    func readOverlayMetadata() {
        guard let document else { return }
        
        var encoded: String?
        var parts: [Int: String] = [:]
        var totalParts: Int?
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            for annotation in page.annotations {
                guard let contents = annotation.contents else { continue }
                if contents.hasPrefix(overlayMetadataPrefix) {
                    encoded = String(contents.dropFirst(overlayMetadataPrefix.count))
                    break
                }
                if contents.hasPrefix(overlayMetadataPartPrefix) {
                    let tail = String(contents.dropFirst(overlayMetadataPartPrefix.count))
                    let components = tail.split(separator: ":", maxSplits: 1)
                    guard components.count == 2 else { continue }
                    let header = components[0].split(separator: "/")
                    guard header.count == 2,
                          let part = Int(header[0]),
                          let total = Int(header[1]) else { continue }
                    totalParts = total
                    parts[part] = String(components[1])
                }
            }
            if encoded != nil {
                break
            }
        }
        
        clearOverlayViews()
        if encoded == nil, let totalParts, parts.count == totalParts {
            let joined = (1...totalParts).compactMap { parts[$0] }.joined()
            encoded = joined
        }
        
        guard let encoded, let data = Data(base64Encoded: encoded) else { return }
        let decoder = JSONDecoder()
        guard let metadata = try? decoder.decode(OverlayDocumentMetadata.self, from: data) else { return }
        
        importOverlayMetadata(metadata)
    }
    
    func overlayMetadataSnapshot() -> OverlayDocumentMetadata {
        var textMetas: [OverlayTextBoxMeta] = []
        var imageMetas: [OverlayImageMeta] = []
        var shapeMetas: [OverlayShapeMeta] = []

        for (id, box) in textBoxViews {
            guard let pageInfo = pageRect(fromDocRect: box.frame) else { continue }
            let meta = OverlayTextBoxMeta(
                id: id,
                pageIndex: pageInfo.pageIndex,
                rect: RectCodable(pageInfo.pageRect),
                text: box.currentText,
                background: RGBAColor(box.currentBackgroundColor),
                fontSize: box.currentFontSize,
                isBold: box.currentIsBold,
                textColor: RGBAColor(box.currentTextColor),
                textAlignment: box.currentTextAlignment.rawValue,
                verticalAlignment: box.currentVerticalAlignment.rawValue,
                autoResize: box.currentAutoResize ? true : nil,
                borderWidth: box.currentBorderWidth > 0 ? box.currentBorderWidth : nil,
                borderColor: box.currentBorderWidth > 0 ? RGBAColor(box.currentBorderColor) : nil
            )
            textMetas.append(meta)
        }

        for (id, box) in imageBoxViews {
            guard let pageInfo = pageRect(fromDocRect: box.frame) else { continue }
            let meta = OverlayImageMeta(
                id: id,
                pageIndex: pageInfo.pageIndex,
                rect: RectCodable(pageInfo.pageRect),
                imageBase64: box.imageData.base64EncodedString(),
                borderWidth: box.imageBorderWidth > 0 ? box.imageBorderWidth : nil,
                borderColor: box.imageBorderWidth > 0 ? RGBAColor(box.imageBorderColor) : nil
            )
            imageMetas.append(meta)
        }

        for (id, box) in shapeBoxViews {
            guard let pageInfo = pageRect(fromDocRect: box.frame) else { continue }
            let meta = OverlayShapeMeta(
                id: id,
                pageIndex: pageInfo.pageIndex,
                rect: RectCodable(pageInfo.pageRect),
                kindRaw: box.shapeKind.rawValue,
                strokeColor: RGBAColor(box.strokeColor),
                lineWidth: box.lineWidth
            )
            shapeMetas.append(meta)
        }

        return OverlayDocumentMetadata(textBoxes: textMetas, images: imageMetas, shapes: shapeMetas)
    }
    
    private func importOverlayMetadata(_ metadata: OverlayDocumentMetadata) {
        for text in metadata.textBoxes {
            guard let page = document?.page(at: text.pageIndex) else { continue }
            let docRect = docRect(fromPageRect: text.rect.cgRect, on: page)
            let state = OverlayTextBoxState(
                id: text.id,
                frame: docRect,
                text: text.text,
                backgroundColor: text.background.uiColor,
                fontSize: text.fontSize ?? 14,
                isBold: text.isBold ?? false,
                textColor: (text.textColor?.uiColor) ?? .label,
                textAlignment: NSTextAlignment(rawValue: text.textAlignment ?? 0) ?? .left,
                verticalAlignment: TextVerticalAlignment(rawValue: text.verticalAlignment ?? "") ?? .top,
                autoResizeEnabled: text.autoResize ?? false,
                borderWidth: text.borderWidth ?? 0,
                borderColor: text.borderColor?.uiColor ?? .black
            )
            addOverlayTextBox(from: state, beginEditing: false)
        }
        
        for image in metadata.images {
            guard let page = document?.page(at: image.pageIndex),
                  let data = Data(base64Encoded: image.imageBase64) else { continue }
            let docRect = docRect(fromPageRect: image.rect.cgRect, on: page)
            let state = OverlayImageState(
                id: image.id,
                frame: docRect,
                imageData: data,
                borderWidth: image.borderWidth ?? 0,
                borderColor: image.borderColor?.uiColor ?? .black
            )
            addOverlayImage(from: state)
        }

        for shape in metadata.shapes {
            guard let page = document?.page(at: shape.pageIndex),
                  let kind = OverlayShapeKind(rawValue: shape.kindRaw) else { continue }
            let docRect = docRect(fromPageRect: shape.rect.cgRect, on: page)
            let state = OverlayShapeState(
                id: shape.id,
                frame: docRect,
                kind: kind,
                strokeColor: shape.strokeColor.uiColor,
                lineWidth: shape.lineWidth
            )
            addOverlayShape(from: state)
        }
    }
    
    private func clearOverlayViews() {
        for view in textBoxViews.values {
            view.removeFromSuperview()
        }
        textBoxViews.removeAll()
        for view in imageBoxViews.values {
            view.removeFromSuperview()
        }
        imageBoxViews.removeAll()
        for view in shapeBoxViews.values {
            view.removeFromSuperview()
        }
        shapeBoxViews.removeAll()
    }
    
    private func pageRect(fromDocRect rectInDoc: CGRect) -> (pageIndex: Int, pageRect: CGRect)? {
        guard let docView = documentView,
              let document else { return nil }
        let rectInView = convert(rectInDoc, from: docView)
        let center = CGPoint(x: rectInView.midX, y: rectInView.midY)
        guard let page = page(for: center, nearest: true) else { return nil }
        let pageIndex = document.index(for: page)
        let pageRect = convert(rectInView, to: page)
        return (pageIndex, pageRect)
    }
    
    private func docRect(fromPageRect rect: CGRect, on page: PDFPage) -> CGRect {
        guard let docView = documentView else { return .zero }
        let viewRect = convert(rect, from: page)
        return convert(viewRect, to: docView)
    }
    
    private func overlayImageStateForNewImage(data: Data) -> OverlayImageState {
        let targetWidth: CGFloat = 220
        let image = UIImage(data: data) ?? UIImage()
        let aspect = image.size.height > 0 ? image.size.width / image.size.height : 1
        let width = targetWidth
        let height = max(120, targetWidth / max(aspect, 0.1))
        let size = CGSize(width: width, height: height)
        
        let frameInDoc = defaultOverlayFrame(size: size)
        let borderW = formViewModel?.imageBorderWidth ?? 0
        let borderC = formViewModel?.imageBorderColor ?? .black
        return OverlayImageState(id: UUID(), frame: frameInDoc, imageData: data, borderWidth: borderW, borderColor: borderC)
    }
    
    private func defaultOverlayFrame(size: CGSize) -> CGRect {
        guard let docView = documentView else {
            return CGRect(origin: CGPoint(x: 40, y: 40), size: size)
        }
        if let page = currentPage {
            let pageBounds = page.bounds(for: .mediaBox)
            let pageRect = CGRect(
                x: pageBounds.midX - size.width / 2,
                y: pageBounds.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
            let viewRect = convert(pageRect, from: page)
            let docRect = convert(viewRect, to: docView)
            return docRect
        } else {
            let centerInView = CGPoint(x: bounds.midX, y: bounds.midY)
            let centerInDoc = convert(centerInView, to: docView)
            return CGRect(
                x: centerInDoc.x - size.width / 2,
                y: centerInDoc.y - size.height / 2,
                width: size.width,
                height: size.height
            )
        }
    }
    
    // MARK: - Eraser
    
    private func eraseAnnotation(at pagePoint: CGPoint, on page: PDFPage) {
        
        for annotation in page.annotations {
            guard annotation.type == "Ink" else { continue }
            let lineWidth = annotation.border?.lineWidth ?? currentLineWidth
            let color = annotation.color
            
            guard let paths = annotation.paths, !paths.isEmpty else { continue }
            let pointInAnnotation = CGPoint(
                x: pagePoint.x - annotation.bounds.origin.x,
                y: pagePoint.y - annotation.bounds.origin.y
            )
            
            var newPaths: [UIBezierPath] = []
            var didErase = false
            
            for path in paths {
                let splitResult = splitInkPath(path, eraserCenter: pointInAnnotation, radius: eraserRadius)
                didErase = didErase || splitResult.didErase
                newPaths.append(contentsOf: splitResult.paths)
            }
            
            guard didErase else { continue }
            
            let annotationID = ObjectIdentifier(annotation)
            let rootID = eraserRootByAnnotationID[annotationID] ?? annotationID
            if eraserRootByAnnotationID[annotationID] == nil {
                eraserRootByAnnotationID[annotationID] = rootID
                eraserRootAnnotations[rootID] = annotation
            }
            
            page.removeAnnotation(annotation)
            
            if !newPaths.isEmpty {
                let newAnnotation = PDFAnnotation(bounds: annotation.bounds, forType: .ink, withProperties: nil)
                newAnnotation.color = color
                newAnnotation.border = PDFBorder()
                newAnnotation.border?.lineWidth = lineWidth
                newAnnotation.shouldDisplay = true
                newAnnotation.shouldPrint = true
                newAnnotation.contents = annotation.contents
                
                for path in newPaths {
                    newAnnotation.add(path)
                }
                
                page.addAnnotation(newAnnotation)
                let newID = ObjectIdentifier(newAnnotation)
                eraserRootByAnnotationID[newID] = rootID
                eraserCurrentAnnotations[rootID] = newAnnotation
            } else {
                eraserCurrentAnnotations[rootID] = nil
            }
        }
    }
    
    private func splitInkPath(
        _ path: UIBezierPath,
        eraserCenter: CGPoint,
        radius: CGFloat
    ) -> (paths: [UIBezierPath], didErase: Bool) {
        let points = points(from: path)
        guard points.count >= 2 else { return ([], false) }
        
        var segments: [[CGPoint]] = []
        var current: [CGPoint] = []
        var didErase = false
        
        for point in points {
            if point.distance(to: eraserCenter) <= radius {
                didErase = true
                if current.count >= 2 {
                    segments.append(current)
                }
                current = []
            } else {
                current.append(point)
            }
        }
        
        if current.count >= 2 {
            segments.append(current)
        }
        
        let paths = segments.map { segmentPoints -> UIBezierPath in
            let newPath = UIBezierPath()
            newPath.move(to: segmentPoints[0])
            for point in segmentPoints.dropFirst() {
                newPath.addLine(to: point)
            }
            newPath.lineWidth = path.lineWidth
            newPath.lineCapStyle = .round
            newPath.lineJoinStyle = .round
            return newPath
        }
        
        return (paths, didErase)
    }
    
    private func points(from path: UIBezierPath) -> [CGPoint] {
        var points: [CGPoint] = []
        var lastPoint = CGPoint.zero
        
        path.cgPath.forEach { [self] element in
            switch element.type {
            case .moveToPoint:
                lastPoint = element.points[0]
                points.append(lastPoint)
            case .addLineToPoint:
                lastPoint = element.points[0]
                points.append(lastPoint)
            case .addQuadCurveToPoint:
                let control = element.points[0]
                let end = element.points[1]
                let sampled = sampleQuadraticCurve(from: lastPoint, control: control, to: end)
                points.append(contentsOf: sampled.dropFirst())
                lastPoint = end
            case .addCurveToPoint:
                let control1 = element.points[0]
                let control2 = element.points[1]
                let end = element.points[2]
                let sampled = sampleCubicCurve(from: lastPoint, control1: control1, control2: control2, to: end)
                points.append(contentsOf: sampled.dropFirst())
                lastPoint = end
            case .closeSubpath:
                break
            @unknown default:
                break
            }
        }
        
        return points
    }
    
    private func sampleQuadraticCurve(from start: CGPoint, control: CGPoint, to end: CGPoint) -> [CGPoint] {
        var result: [CGPoint] = [start]
        let steps = 8
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let oneMinusT = 1 - t
            let point = CGPoint(
                x: oneMinusT * oneMinusT * start.x + 2 * oneMinusT * t * control.x + t * t * end.x,
                y: oneMinusT * oneMinusT * start.y + 2 * oneMinusT * t * control.y + t * t * end.y
            )
            result.append(point)
        }
        return result
    }
    
    private func sampleCubicCurve(
        from start: CGPoint,
        control1: CGPoint,
        control2: CGPoint,
        to end: CGPoint
    ) -> [CGPoint] {
        var result: [CGPoint] = [start]
        let steps = 8
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let oneMinusT = 1 - t
            let point = CGPoint(
                x: oneMinusT * oneMinusT * oneMinusT * start.x
                    + 3 * oneMinusT * oneMinusT * t * control1.x
                    + 3 * oneMinusT * t * t * control2.x
                    + t * t * t * end.x,
                y: oneMinusT * oneMinusT * oneMinusT * start.y
                    + 3 * oneMinusT * oneMinusT * t * control1.y
                    + 3 * oneMinusT * t * t * control2.y
                    + t * t * t * end.y
            )
            result.append(point)
        }
        return result
    }
    
    // MARK: - Scribble
    
    private func setupScribbleInteraction() {
        let interaction = UIIndirectScribbleInteraction(delegate: self)
        addInteraction(interaction)
        scribbleInteraction = interaction
    }

    /// Single source of truth for Scribble on the PDF surface and on overlay text boxes.
    ///
    /// - **PDF** (`UIIndirectScribbleInteraction`): enabled only in **Form** mode so pencil can
    ///   write into PDF form widgets.
    /// - **Overlay text boxes** (`UITextView`): Scribble enabled only in **Text** or **Form** mode;
    ///   draw, erase, PencilKit, select, and shape tools suppress overlay Scribble so the pencil stays on the canvas.
    private func syncScribbleInteraction() {
        if let scribble = scribbleInteraction {
            let shouldEnable = isFormMode
            let isAdded = interactions.contains { $0 === scribble }
            if shouldEnable && !isAdded {
                addInteraction(scribble)
            } else if !shouldEnable && isAdded {
                removeInteraction(scribble)
            }
        }
        syncOverlayTextViewsScribbleEnabled()
        syncOverlayCanvasDismissTap()
    }

    /// Overlay `UITextView` Scribble: on for **Text** and **Form** tools only.
    private func syncOverlayTextViewsScribbleEnabled() {
        let scribbleAllowedOnTextOverlays = isTextMode || isFormMode
        for box in textBoxViews.values {
            box.setTextInputScribbleEnabled(scribbleAllowedOnTextOverlays)
        }
    }

    /// Tap on empty overlay canvas: select-mode deselect, text-mode dismiss, or (when a text box
    /// is focused/selected outside Text/Select tools) dismiss keyboard — without blocking drawing.
    private func syncOverlayCanvasDismissTap() {
        let overlayTextNeedsDismissTap = selectedTextBoxID != nil
            || textBoxViews.values.contains(where: { $0.isTextInputFirstResponder })
        let enable = !isFormMode && (isSelectMode || isTextMode || overlayTextNeedsDismissTap)
        overlaySelectTapGesture?.isEnabled = enable
    }

    // MARK: - Form Field Tracking
    
    private func setupTextSelectionObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTextSelectionChanged),
            name: .PDFViewSelectionChanged,
            object: self
        )
    }
    
    private func setupPageChangeObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePageChanged),
            name: .PDFViewPageChanged,
            object: self
        )
    }

    /// Enables or disables PDFKit's internal double-tap-to-zoom gesture recognizers.
    /// Called when form field text editing begins/ends so word-selection double-tap
    /// is not hijacked by zoom while the user is typing in a field.
    private func setDoubleTapZoomEnabled(_ enabled: Bool) {
        // PDFKit registers its zoom double-tap on the PDFView itself
        gestureRecognizers?
            .compactMap { $0 as? UITapGestureRecognizer }
            .filter { $0 !== inkSelectTapGesture && $0 !== formPencilTapGesture && $0.numberOfTapsRequired == 2 }
            .forEach { $0.isEnabled = enabled }

        // Belt-and-suspenders: also check the internal scroll view
        scrollView?.gestureRecognizers?
            .compactMap { $0 as? UITapGestureRecognizer }
            .filter { $0.numberOfTapsRequired == 2 }
            .forEach { $0.isEnabled = enabled }
    }
    
    @objc private func handleTextSelectionChanged() {
        // When a widget is focused, a non-empty PDF *document* `currentSelection` can steal first
        // responder from the widget. Only clear in that case — avoid calling `clearSelection()`
        // on every notification (including empty), which can disrupt UITextView selection gestures.
        if isFormMode && formTextInputIsFirstResponder(in: self) {
            let hadDocSel = currentSelection != nil && !(currentSelection?.string?.isEmpty ?? true)
            if hadDocSel {
                clearSelection()
            }
        }
        let hasSelection = currentSelection != nil && !(currentSelection?.string?.isEmpty ?? true)
        formViewModel?.hasTextSelection = hasSelection
        if !isFormFieldTextActive && isDirectTouchInProgress && hasSelection && !isTextSelectionInProgress {
            beginTextSelectionScrollLock()
        } else if !hasSelection {
            endTextSelectionScrollLock()
        }
    }
    
    @objc private func handlePageChanged() {
        formViewModel?.updatePageMetrics()
        if let docView = documentView {
            docView.bringSubviewToFront(textBoxOverlayView)
            if inkSelectionOverlayView.superview != nil {
                docView.bringSubviewToFront(inkSelectionOverlayView)
            }
        }
    }
    
    func highlightCurrentSelection() {
        guard let selection = self.currentSelection,
              !selection.pages.isEmpty else { return }
        
        let selectionLinesByPage = selectionLineBoundsByPage(for: selection)
        guard !selectionLinesByPage.isEmpty else { return }
        var pageDeltas: [PDFPage: (removed: [PDFAnnotation], added: [PDFAnnotation])] = [:]
        
        func delta(for page: PDFPage) -> (removed: [PDFAnnotation], added: [PDFAnnotation]) {
            pageDeltas[page] ?? ([], [])
        }
        func appendRemove(_ ann: PDFAnnotation, page: PDFPage) {
            var d = delta(for: page)
            d.removed.append(ann)
            pageDeltas[page] = d
        }
        func appendAdd(_ ann: PDFAnnotation, page: PDFPage) {
            var d = delta(for: page)
            d.added.append(ann)
            pageDeltas[page] = d
        }
        
        let matchingHighlightsByPage = selectionLinesByPage.reduce(into: [PDFPage: [PDFAnnotation]]()) { partialResult, entry in
            let (page, lineBounds) = entry
            let highlights = page.annotations.filter { Self.isHighlightAnnotation($0) }
            let matching = highlights.filter { highlight in
                let matchedByRect = lineBounds.contains(where: { bounds in
                    Self.highlight(highlight.bounds, matchesSelectionLine: bounds)
                })
                if matchedByRect { return true }

                // Point-sampling fallback: check if the center of any selection
                // line falls inside this highlight (with padding), or vice versa.
                let paddedHighlight = highlight.bounds.insetBy(dx: -6, dy: -4)
                return lineBounds.contains { bounds in
                    let selMid = CGPoint(x: bounds.midX, y: bounds.midY)
                    if paddedHighlight.contains(selMid) { return true }
                    let hlMid = CGPoint(x: highlight.bounds.midX, y: highlight.bounds.midY)
                    let paddedSelection = bounds.insetBy(dx: -4, dy: -4)
                    return paddedSelection.contains(hlMid)
                }
            }
            if !matching.isEmpty {
                partialResult[page] = matching
            }
        }
        let shouldRemoveHighlights = !matchingHighlightsByPage.isEmpty
        
        for (page, lineBounds) in selectionLinesByPage {
            let highlights = page.annotations.filter { Self.isHighlightAnnotation($0) }
            
            if shouldRemoveHighlights {
                let matches = matchingHighlightsByPage[page] ?? []
                for existing in matches {
                    page.removeAnnotation(existing)
                    appendRemove(existing, page: page)
                }
            } else {
                for bounds in lineBounds where !highlights.contains(where: {
                    Self.highlight($0.bounds, matchesSelectionLine: bounds)
                }) {
                    let highlight = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
                    page.addAnnotation(highlight)
                    appendAdd(highlight, page: page)
                }
            }
        }
        
        clearSelection()
        
        for (page, delta) in pageDeltas where !delta.removed.isEmpty || !delta.added.isEmpty {
            formViewModel?.didMakeChange(.drawingSession(
                page: page,
                oldAnnotations: delta.removed,
                newAnnotations: delta.added
            ))
        }
    }
    
    private func selectionLineBoundsByPage(for selection: PDFSelection) -> [PDFPage: [CGRect]] {
        var linesByPage: [PDFPage: [CGRect]] = [:]
        
        for page in selection.pages {
            var lineBounds: [CGRect] = []
            for lineSelection in selection.selectionsByLine() {
                guard lineSelection.pages.contains(page) else { continue }
                let bounds = lineSelection.bounds(for: page)
                guard bounds.width > 1, bounds.height > 1 else { continue }
                lineBounds.append(bounds)
            }
            
            if !lineBounds.isEmpty {
                linesByPage[page] = lineBounds
            }
        }
        
        return linesByPage
    }
    
    /// Checks both `"Highlight"` and `"/Highlight"` because `PDFAnnotation.type`
    /// may omit the slash prefix that `PDFAnnotationSubtype.highlight.rawValue` includes.
    private static func isHighlightAnnotation(_ annotation: PDFAnnotation) -> Bool {
        annotation.type == "Highlight" || annotation.type == "/Highlight"
    }
    
    /// True when a highlight annotation lies on top of the selected text line.
    private static func highlight(_ highlightBounds: CGRect, matchesSelectionLine selectionLine: CGRect) -> Bool {
        let expandedHighlight = highlightBounds.insetBy(dx: -8, dy: -6)
        let expandedSelection = selectionLine.insetBy(dx: -4, dy: -4)

        // Fast path: if either midpoint is contained in the other's expanded rect,
        // the two rects clearly cover the same text region.
        let selectionMid = CGPoint(x: selectionLine.midX, y: selectionLine.midY)
        let highlightMid = CGPoint(x: highlightBounds.midX, y: highlightBounds.midY)
        if expandedHighlight.contains(selectionMid) || expandedSelection.contains(highlightMid) {
            return true
        }

        let intersection = expandedHighlight.intersection(expandedSelection)
        guard intersection.width > 0, intersection.height > 0 else { return false }

        let selectionWidth = max(selectionLine.width, 1)
        let highlightWidth = max(highlightBounds.width, 1)
        let horizontalCoverageOnSelection = intersection.width / selectionWidth
        let horizontalCoverageOnHighlight = intersection.width / highlightWidth
        let verticallyAligned = abs(highlightBounds.midY - selectionLine.midY) <= max(12, selectionLine.height * 0.8)

        return verticallyAligned && (horizontalCoverageOnSelection >= 0.3 || horizontalCoverageOnHighlight >= 0.3)
    }
    
    private func setupFormFieldTracking() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardDidHide),
            name: UIResponder.keyboardDidHideNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardDidChangeFrame),
            name: UIResponder.keyboardDidChangeFrameNotification,
            object: nil
        )
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(formHostedTextInputEditingChanged), name: UITextField.textDidBeginEditingNotification, object: nil)
        nc.addObserver(self, selector: #selector(formHostedTextInputEditingChanged), name: UITextField.textDidChangeNotification, object: nil)
        nc.addObserver(self, selector: #selector(formHostedTextInputEditingChanged), name: UITextField.textDidEndEditingNotification, object: nil)
        nc.addObserver(self, selector: #selector(formHostedTextInputEditingChanged), name: UITextView.textDidBeginEditingNotification, object: nil)
        nc.addObserver(self, selector: #selector(formHostedTextInputEditingChanged), name: UITextView.textDidChangeNotification, object: nil)
        nc.addObserver(self, selector: #selector(formHostedTextInputEditingChanged), name: UITextView.textDidEndEditingNotification, object: nil)
    }

    /// PDFKit embeds widget editing in `UITextField` / `UITextView` subviews.
    private func formTextInputIsFirstResponder(in view: UIView) -> Bool {
        pdfHostedTextInputWithFocus(in: view) != nil
    }

    private func beginTextSelectionScrollLock() {
        guard !isTextSelectionInProgress, let sv = scrollView else { return }
        isTextSelectionInProgress = true
        textSelectionLockedOffset = sv.contentOffset
        textSelectionScrollObserver = sv.observe(\.contentOffset, options: [.new]) { [weak self] sv, _ in
            guard let self, let locked = self.textSelectionLockedOffset else { return }
            if sv.contentOffset != locked {
                sv.setContentOffset(locked, animated: false)
            }
        }
    }

    private func endTextSelectionScrollLock() {
        guard isTextSelectionInProgress else { return }
        isTextSelectionInProgress = false
        textSelectionScrollObserver = nil
        textSelectionLockedOffset = nil
    }

    /// The focused PDF widget text control under `view`, if any (e.g. `PDFTextWidgetTextView`).
    private func pdfHostedTextInputWithFocus(in view: UIView) -> UIView? {
        if (view is UITextField || view is UITextView), view.isFirstResponder { return view }
        for sub in view.subviews {
            if let found = pdfHostedTextInputWithFocus(in: sub) { return found }
        }
        return nil
    }

    /// PDFKit can leave the most recent widget editor visible after it resigns
    /// first responder. Scan every hosted text input so refresh can sync stale
    /// editors, not just the currently focused one.
    private func pdfHostedTextInputs(in view: UIView) -> [UIView] {
        var inputs: [UIView] = []
        if (view is UITextField || view is UITextView),
           !view.isDescendant(of: textBoxOverlayView) {
            inputs.append(view)
        }
        for subview in view.subviews {
            inputs.append(contentsOf: pdfHostedTextInputs(in: subview))
        }
        return inputs
    }

    /// Copies the focused native PDF widget editor's text into `widgetStringValue`
    /// so undo/export reads the current string even when PDFKit has not yet
    /// synced after editing.
    func commitActiveFormWidgetTextToAnnotations() {
        guard let focused = pdfHostedTextInputWithFocus(in: self) else { return }
        commitFormWidgetText(from: focused)
    }

    /// Forces form-field undo tracking to capture any widget changes now,
    /// instead of waiting for keyboard notifications.
    func flushPendingFormFieldUndoTracking() {
        if let focused = pdfHostedTextInputWithFocus(in: self) {
            commitFormWidgetText(from: focused)
        }
        recordActiveFormFieldChange(resetSession: true)
        recordFormFieldChanges()
    }

    private func beginFormFieldEditSession(for textInput: UIView) {
        guard !isApplyingFormUndoRedo else { return }
        guard let annotation = formWidgetAnnotationOwningFirstResponderIfKnown(textInput),
              let fieldName = annotation.fieldName else { return }
        let wt = annotation.widgetFieldType
        guard wt == .text || wt == .choice else { return }

        if activeFormFieldAnnotation !== annotation || activeFormFieldName != fieldName {
            recordActiveFormFieldChange(resetSession: false)
        }

        let currentValue = annotation.widgetStringValue
        if formFieldStates[fieldName] == nil {
            formFieldStates[fieldName] = currentValue
        }

        activeFormFieldAnnotation = annotation
        activeFormFieldName = fieldName
        activeFormFieldInitialValue = formFieldStates[fieldName] ?? currentValue
    }

    @discardableResult
    private func commitFormWidgetText(from textInput: UIView) -> PDFAnnotation? {
        guard textInput is UITextField || textInput is UITextView else { return nil }
        guard !textInput.isDescendant(of: textBoxOverlayView) else { return nil }
        guard let annotation = formWidgetAnnotationOwningFirstResponderIfKnown(textInput) else { return nil }
        let wt = annotation.widgetFieldType
        guard wt == .text || wt == .choice else { return nil }

        let committed: String
        if let textField = textInput as? UITextField {
            committed = textField.text ?? ""
        } else if let textView = textInput as? UITextView {
            committed = textView.text ?? ""
        } else {
            return nil
        }

        annotation.widgetStringValue = committed
        annotation.setValue(committed, forAnnotationKey: .widgetValue)
        return annotation
    }

    private func syncHostedFormWidgetTextInputs() {
        for textInput in pdfHostedTextInputs(in: self) {
            guard let annotation = formWidgetAnnotationOwningFirstResponderIfKnown(textInput) else { continue }
            let wt = annotation.widgetFieldType
            guard wt == .text || wt == .choice else { continue }

            let textValue = annotation.widgetStringValue ?? ""
            if let textField = textInput as? UITextField, textField.text != textValue {
                textField.text = textValue
            } else if let textView = textInput as? UITextView, textView.text != textValue {
                textView.text = textValue
            }
            textInput.setNeedsDisplay()
            textInput.setNeedsLayout()
        }
    }

    private func recordActiveFormFieldChange(resetSession: Bool) {
        guard !isApplyingFormUndoRedo else { return }
        guard let annotation = activeFormFieldAnnotation,
              let fieldName = activeFormFieldName else { return }
        let currentValue = annotation.widgetStringValue
        let previousValue = activeFormFieldInitialValue
        guard previousValue != currentValue else {
            formFieldStates[fieldName] = currentValue
            if resetSession {
                activeFormFieldInitialValue = currentValue
            } else {
                clearActiveFormFieldEditSession()
            }
            return
        }

        formViewModel?.recordFormFieldChange(
            annotation: annotation,
            previousValue: previousValue,
            newValue: currentValue
        )
        formFieldStates[fieldName] = currentValue

        if resetSession {
            activeFormFieldInitialValue = currentValue
        } else {
            clearActiveFormFieldEditSession()
        }
    }

    private func clearActiveFormFieldEditSession() {
        activeFormFieldAnnotation = nil
        activeFormFieldName = nil
        activeFormFieldInitialValue = nil
    }

    func beginApplyingFormUndoRedo() {
        isApplyingFormUndoRedo = true
    }

    func endApplyingFormUndoRedo() {
        isApplyingFormUndoRedo = false
    }

    func syncFormFieldBaseline(for annotation: PDFAnnotation) {
        guard let fieldName = annotation.fieldName else { return }
        formFieldStates[fieldName] = annotation.widgetStringValue
        if activeFormFieldName == fieldName {
            activeFormFieldInitialValue = annotation.widgetStringValue
        }
    }

    func refreshFormWidgetAppearance(for annotation: PDFAnnotation) {
        let matchingAnnotations = formWidgetAnnotationsMatching(annotation)
        let value = annotation.widgetStringValue
        if let focused = pdfHostedTextInputWithFocus(in: self),
           let activeAnnotation = formWidgetAnnotationOwningFirstResponderIfKnown(focused),
           matchingAnnotations.contains(where: { $0 === activeAnnotation }) {
            let textValue = value ?? ""
            if let tf = focused as? UITextField, tf.text != textValue {
                tf.text = textValue
            } else if let tv = focused as? UITextView, tv.text != textValue {
                tv.text = textValue
            }
        }
        for ann in matchingAnnotations {
            guard let page = ann.page else { continue }
            ann.widgetStringValue = value
            ann.setValue(value as Any, forAnnotationKey: .widgetValue)
            let viewRect = convert(ann.bounds, from: page).insetBy(dx: -8, dy: -8)
            page.removeAnnotation(ann)
            page.addAnnotation(ann)
            setNeedsDisplay(viewRect)
        }
        setNeedsDisplay()
        documentView?.setNeedsDisplay()
        documentView?.setNeedsLayout()
        scrollView?.setNeedsDisplay()
        scrollView?.setNeedsLayout()
        syncHostedFormWidgetTextInputs()
        updateFormFieldHighlights()
        scheduleFormWidgetTextSync()
    }

    func refreshAllFormWidgetAppearances() {
        guard let document else { return }

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            let annotations = page.annotations
            for annotation in annotations {
                guard annotation.type == PDFAnnotationSubtype.widget.rawValue else { continue }
                let fieldType = annotation.widgetFieldType
                guard fieldType == .text || fieldType == .choice else { continue }

                let value = annotation.widgetStringValue
                annotation.widgetStringValue = value
                annotation.setValue(value as Any, forAnnotationKey: .widgetValue)

                let viewRect = convert(annotation.bounds, from: page).insetBy(dx: -8, dy: -8)
                page.removeAnnotation(annotation)
                page.addAnnotation(annotation)
                setNeedsDisplay(viewRect)
            }
        }

        setNeedsDisplay()
        documentView?.setNeedsDisplay()
        documentView?.setNeedsLayout()
        scrollView?.setNeedsDisplay()
        scrollView?.setNeedsLayout()
        layoutDocumentView()
        syncHostedFormWidgetTextInputs()
        updateFormFieldHighlights()
        scheduleFormWidgetTextSync()
    }

    func scheduleFullFormWidgetAppearanceRefresh() {
        guard !fullFormWidgetRefreshScheduled else { return }
        fullFormWidgetRefreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.fullFormWidgetRefreshScheduled = false
            self.refreshAllFormWidgetAppearances()
        }
    }

    private func formWidgetAnnotationsMatching(_ annotation: PDFAnnotation) -> [PDFAnnotation] {
        guard let document, let fieldName = annotation.fieldName else { return [annotation] }
        var matches: [PDFAnnotation] = []
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            for candidate in page.annotations {
                guard candidate.type == PDFAnnotationSubtype.widget.rawValue else { continue }
                guard candidate.fieldName == fieldName else { continue }
                guard candidate.widgetFieldType == .text || candidate.widgetFieldType == .choice else { continue }
                matches.append(candidate)
            }
        }
        return matches.isEmpty ? [annotation] : matches
    }

    private func syncFormWidgetTextEditingState() {
        guard isFormMode else {
            updatePDFScrollInteractionForEmbeddedWidgetTextEditing(false)
            if isFormFieldTextActive {
                isFormFieldTextActive = false
            }
            if !isDrawingMode && !isTextMode {
                setDoubleTapZoomEnabled(true)
            }
            return
        }
        setDoubleTapZoomEnabled(false)
        let active = formTextInputIsFirstResponder(in: self)
        if active != isFormFieldTextActive {
            isFormFieldTextActive = active
        }
        updatePDFScrollInteractionForEmbeddedWidgetTextEditing(active)
        updateFormFieldHighlights()
    }

    /// Coalesces `textDidEnd` → `textDidBegin` on field switches so we don't briefly re-enable PDF double-tap zoom.
    private func scheduleFormWidgetTextSync() {
        guard isFormMode else { return }
        guard !formWidgetTextSyncScheduled else { return }
        formWidgetTextSyncScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.formWidgetTextSyncScheduled = false
            self.syncFormWidgetTextEditingState()
        }
    }

    @objc private func formHostedTextInputEditingChanged(_ notification: Notification) {
        guard isFormMode else { return }
        guard let view = notification.object as? UIView, view.isDescendant(of: self) else { return }
        // Overlay text boxes live under `textBoxOverlayView`; ignore them whenever they could receive events.
        if view.isDescendant(of: textBoxOverlayView) { return }

        if notification.name == UITextField.textDidBeginEditingNotification ||
            notification.name == UITextView.textDidBeginEditingNotification {
            beginFormFieldEditSession(for: view)
            // Keyboard may already be visible (user tapped a second field); scroll into view.
            if !lastKnownKeyboardFrame.isEmpty {
                scrollFocusedFormFieldAboveKeyboard(animationDuration: 0.25)
            }
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view else { return }
                self.beginFormFieldEditSession(for: view)
            }
        } else if notification.name == UITextField.textDidChangeNotification ||
                    notification.name == UITextView.textDidChangeNotification {
            if activeFormFieldAnnotation == nil {
                beginFormFieldEditSession(for: view)
            }
            commitFormWidgetText(from: view)
        } else if notification.name == UITextField.textDidEndEditingNotification ||
                    notification.name == UITextView.textDidEndEditingNotification {
            commitFormWidgetText(from: view)
            recordActiveFormFieldChange(resetSession: false)
        }

        scheduleFormWidgetTextSync()
    }
    
    @objc private func keyboardWillShow(_ notification: Notification) {
        captureFormFieldStates()

        if let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
            lastKnownKeyboardFrame = endFrame
        }

        // First responder on a PDF widget may lag the keyboard; resync after layout.
        if isFormMode {
            syncFormWidgetTextEditingState()
            DispatchQueue.main.async { [weak self] in
                self?.syncFormWidgetTextEditingState()
            }
            let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
            scrollFocusedFormFieldAboveKeyboard(animationDuration: duration)
        }

        // Preserve scroll position when editing an overlay text box
        if selectedTextBoxID != nil, let sv = scrollView {
            savedTextBoxContentOffset = sv.contentOffset
        }
    }

    @objc private func keyboardDidHide(_ notification: Notification) {
        recordFormFieldChanges()
        lastKnownKeyboardFrame = .zero
        savedTextBoxContentOffset = nil

        // Keyboard can hide while a widget stays first responder (e.g. iPad); re-sync from the view tree.
        if isFormMode {
            syncFormWidgetTextEditingState()
            DispatchQueue.main.async { [weak self] in
                self?.syncFormWidgetTextEditingState()
            }
        }
    }

    @objc private func keyboardDidChangeFrame(_ notification: Notification) {
        // Restore scroll position when editing an overlay text box so the
        // keyboard appearance doesn't shift annotations around the page.
        guard let saved = savedTextBoxContentOffset,
              selectedTextBoxID != nil,
              let sv = scrollView else { return }
        if sv.contentOffset != saved {
            sv.setContentOffset(saved, animated: false)
        }
    }
    
    private func scrollFocusedFormFieldAboveKeyboard(animationDuration: Double = 0.25) {
        guard isFormMode, selectedTextBoxID == nil else { return }
        guard let sv = scrollView, let window else { return }
        guard !lastKnownKeyboardFrame.isEmpty else { return }

        // Keyboard frames reported while the device is in landscape can be in portrait
        // coordinates on older iOS; only act when the keyboard visibly covers screen space.
        let keyboardFrameInWindow = window.convert(lastKnownKeyboardFrame, from: nil)
        let windowHeight = window.bounds.height
        guard keyboardFrameInWindow.minY < windowHeight else { return }

        // Locate the focused form-widget text input. PDFKit assigns first responder
        // slightly after the tap, so defer one run-loop pass if it's not ready yet.
        guard let focused = pdfHostedTextInputWithFocus(in: self) else {
            DispatchQueue.main.async { [weak self] in
                self?.scrollFocusedFormFieldAboveKeyboard(animationDuration: animationDuration)
            }
            return
        }

        let fieldFrameInWindow = focused.convert(focused.bounds, to: window)
        let keyboardTop = keyboardFrameInWindow.minY
        let padding: CGFloat = 24

        // Field is already clear of the keyboard — nothing to do.
        guard fieldFrameInWindow.maxY + padding > keyboardTop else { return }

        // Shift scroll so the field's bottom sits `padding` above the keyboard.
        let overlap = fieldFrameInWindow.maxY + padding - keyboardTop
        let maxOffset = max(0, sv.contentSize.height - sv.bounds.height)
        let newOffsetY = min(sv.contentOffset.y + overlap, maxOffset)
        guard newOffsetY != sv.contentOffset.y else { return }

        UIView.animate(withDuration: animationDuration) {
            sv.contentOffset = CGPoint(x: sv.contentOffset.x, y: newOffsetY)
        }
    }

    private func captureFormFieldStates() {
        guard let document = self.document else { return }
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            for annotation in page.annotations {
                if let fieldName = annotation.fieldName,
                   annotation.widgetFieldType == .text || annotation.widgetFieldType == .choice {
                    formFieldStates[fieldName] = annotation.widgetStringValue
                }
            }
        }
    }
    
    private func recordFormFieldChanges() {
        guard !isApplyingFormUndoRedo else { return }
        guard let document = self.document else { return }
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            for annotation in page.annotations {
                guard let fieldName = annotation.fieldName,
                      annotation.widgetFieldType == .text || annotation.widgetFieldType == .choice else { continue }
                let currentValue = annotation.widgetStringValue
                guard let previousValue = formFieldStates[fieldName] else {
                    formFieldStates[fieldName] = currentValue
                    continue
                }
                guard previousValue != currentValue else { continue }
                formViewModel?.recordFormFieldChange(
                    annotation: annotation,
                    previousValue: previousValue,
                    newValue: currentValue
                )
                formFieldStates[fieldName] = currentValue
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if suppressGoTo { return }
        if shouldInterceptAllTouches {
            if isTextMode, let touch = touches.first {
                textModeTouchStart = touch.location(in: self)
            } else if !isFormMode, let touch = touches.first, touch.type == .direct,
                      selectedTextBoxID != nil || textBoxViews.values.contains(where: { $0.isTextInputFirstResponder }) {
                fingerDismissOverlayTouchStart = touch.location(in: self)
            }
            return
        }
        // Mark a finger touch as in-progress so go(to:rect:on:) can suppress
        // PDFKit's selection-anchor scroll for the full duration of the gesture.
        if touches.contains(where: { $0.type == .direct }) {
            isDirectTouchInProgress = true
        }
        super.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if suppressGoTo { return }
        if shouldInterceptAllTouches { return }
        super.touchesMoved(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if suppressGoTo { return }
        if shouldInterceptAllTouches {
            if isTextMode, let touch = touches.first {
                // A pan gesture that begins sends touchesCancelled (clearing textModeTouchStart),
                // so touchesEnded only runs for genuine taps — handle them here.
                if let start = textModeTouchStart {
                    let end = touch.location(in: self)
                    let distance = hypot(end.x - start.x, end.y - start.y)
                    if distance < 15 {
                        handleTextModeTap(at: start)
                    }
                }
            } else if !isFormMode, let touch = touches.first, touch.type == .direct,
                      let start = fingerDismissOverlayTouchStart {
                let end = touch.location(in: self)
                let distance = hypot(end.x - start.x, end.y - start.y)
                if distance < 15, textBoxViewAtPoint(end) == nil {
                    endOverlayTextEditing()
                    deselectOverlaySelection()
                }
            }
            textModeTouchStart = nil
            fingerDismissOverlayTouchStart = nil
            return
        }
        isDirectTouchInProgress = false
        endTextSelectionScrollLock()
        super.touchesEnded(touches, with: event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if suppressGoTo { return }
        isDirectTouchInProgress = false
        endTextSelectionScrollLock()
        if shouldInterceptAllTouches {
            // Pan gesture began — it owns this touch, clear the tap tracker.
            textModeTouchStart = nil
            fingerDismissOverlayTouchStart = nil
            return
        }
        super.touchesCancelled(touches, with: event)
    }

    override func go(to page: PDFPage) {
        if shouldInterceptAllTouches || suppressGoTo { return }
        super.go(to: page)
    }

    override func go(to destination: PDFDestination) {
        if shouldInterceptAllTouches || suppressGoTo { return }
        super.go(to: destination)
    }

    override func go(to rect: CGRect, on page: PDFPage) {
        if shouldInterceptAllTouches || suppressGoTo { return }
        super.go(to: rect, on: page)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if shouldInterceptAllTouches || suppressGoTo {
            return self
        }
        // `PDFDocumentView` can win `hitTest` over a focused `PDFTextWidgetTextView`, so taps do
        // not reach `UITextInteraction`. Prefer the first-responder widget inside a slightly
        // expanded bounds for near-edge taps.
        if isFormMode, let widgetText = pdfHostedTextInputWithFocus(in: self) {
            let pInWidget = convert(point, to: widgetText)
            let targetRect = widgetText.bounds.insetBy(dx: -14, dy: -14)
            if targetRect.contains(pInWidget) {
                return widgetText.hitTest(pInWidget, with: event) ?? widgetText
            }
        }
        return super.hitTest(point, with: event)
    }

    override func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        if gestureRecognizer === inkDragPanGesture || otherGestureRecognizer === inkDragPanGesture {
            return false
        }
        let drawGestures: [UIGestureRecognizer?] = [pencilDrawingGesture, pencilTextTapGesture, fingerPanGesture, fingerPinchGesture, shapePanGesture, textBoxPanGesture]
        let isFirst = drawGestures.contains(where: { $0 === gestureRecognizer })
        let isSecond = drawGestures.contains(where: { $0 === otherGestureRecognizer })
        if isFirst && isSecond { return true }
        if isFirst || isSecond { return false }
        return super.gestureRecognizer(gestureRecognizer, shouldRecognizeSimultaneouslyWith: otherGestureRecognizer)
    }
    
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === textBoxPanGesture {
            guard isTextMode else { return false }
        }
        if gestureRecognizer === shapePanGesture {
            // In shape mode the user always intends to draw a new shape — allow the
            // gesture to begin over any content, including existing overlay objects.
            guard isShapeMode else { return false }
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }
}

// MARK: - UIPencilInteractionDelegate

extension DrawingPDFView: UIPencilInteractionDelegate {

    // MARK: Double Tap

    /// Legacy tap handler — covers iOS < 17.5. Apple Pencil 2 and Pro only.
    /// On iOS 17.5+ the system calls `pencilInteraction(_:didReceiveTap:)` instead.
    func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        guard let vm = formViewModel else { return }
        vm.perform(vm.pencilDoubleTapAction)
    }

    /// iOS 17.5+ tap handler — supersedes `pencilInteractionDidTap` on iOS 17.5+.
    /// Handles double-tap on Apple Pencil 2 and Apple Pencil Pro.
    @available(iOS 17.5, *)
    func pencilInteraction(_ interaction: UIPencilInteraction,
                           didReceiveTap tap: UIPencilInteraction.Tap) {
        guard let vm = formViewModel else { return }
        vm.perform(vm.pencilDoubleTapAction)
    }

    // MARK: Squeeze (Apple Pencil Pro, iOS 17.5+)

    /// Detects single and double squeezes.
    /// - A single squeeze fires after a short delay (to confirm no second squeeze).
    /// - A second squeeze arriving within that delay cancels the single and fires double.
    @available(iOS 17.5, *)
    func pencilInteraction(_ interaction: UIPencilInteraction,
                           didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
        guard squeeze.phase == .ended, let vm = formViewModel else { return }

        if singleSqueezePendingTask != nil {
            // A second squeeze arrived while we were waiting → double squeeze
            singleSqueezePendingTask?.cancel()
            singleSqueezePendingTask = nil
            vm.perform(vm.pencilDoubleSqueezeAction)
        } else {
            // First squeeze: wait briefly to confirm no second one follows
            singleSqueezePendingTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(400))
                guard let self, !Task.isCancelled else { return }
                self.singleSqueezePendingTask = nil
                vm.perform(vm.pencilSqueezeAction)
            }
        }
    }
}
