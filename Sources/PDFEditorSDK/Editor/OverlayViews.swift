//
//  OverlayViews.swift
//  PDFEditorSDK
//
//  Extracted from PDFEditorView.swift
//

import SwiftUI
import PDFKit
import UIKit

/// Default `UIView.hitTest` ignores touches outside the view’s `bounds`, so subviews laid out past the edge (move/resize handles) never receive them. Call `superHitTest` when the point is inside `bounds`; otherwise ask subviews in z-order.
private func overlayHitTestForwardingOutOfBounds(
    host: UIView,
    point: CGPoint,
    event: UIEvent?,
    superHitTest: (CGPoint, UIEvent?) -> UIView?
) -> UIView? {
    guard host.isUserInteractionEnabled, !host.isHidden, host.alpha > 0.01 else { return nil }
    if host.point(inside: point, with: event) {
        return superHitTest(point, event)
    }
    for sub in host.subviews.reversed() {
        guard sub.isUserInteractionEnabled, !sub.isHidden, sub.alpha > 0.01 else { continue }
        let p = sub.convert(point, from: host)
        if let hit = sub.hitTest(p, with: event) {
            return hit
        }
    }
    return nil
}

final class TextBoxView: UIView, UITextViewDelegate, UIScribbleInteractionDelegate {
    private let textView = UITextView()
    /// Added only while Scribble should be suppressed; `UITextView` has no `isScribbleEnabled` (unlike `UITextField`).
    private var scribbleSuppressionInteraction: UIScribbleInteraction?
    private let padding = UIEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
    private let moveHandle = UIView()
    private let moveIcon = UIImageView()
    private let resizeHitTarget = ResizeHandleHitTargetView()
    private let resizeHandleVisual = UIView()
    private let resizeIcon = UIImageView()
    private let resizeVisualSize: CGFloat = 24
    private var isSelected: Bool = false {
        didSet { updateSelectionUI() }
    }
    private var isSelectMode: Bool = false
    private let minSize = CGSize(width: 80, height: 40)
    var currentText: String { textView.text ?? "" }
    var currentBackgroundColor: UIColor { backgroundColor ?? .clear }
    var currentFontSize: CGFloat { textView.font?.pointSize ?? 14 }
    var currentTextColor: UIColor { textView.textColor ?? .label }
    var currentIsBold: Bool {
        textView.font?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false
    }
    var currentTextAlignment: NSTextAlignment { textView.textAlignment }
    private var _verticalAlignment: TextVerticalAlignment = .top
    var currentVerticalAlignment: TextVerticalAlignment { _verticalAlignment }
    private var _autoResizeEnabled: Bool = false
    var currentAutoResize: Bool { _autoResizeEnabled }
    private var _borderWidth: CGFloat = 0
    private var _borderColor: UIColor = .black
    var currentBorderWidth: CGFloat { _borderWidth }
    var currentBorderColor: UIColor { _borderColor }
    private let overflowIndicator = UIImageView()
    var onSelect: ((UUID) -> Void)?
    /// Called when the embedded `UITextView` gains or loses first responder (keyboard show/hide).
    var onTextEditingFocusChange: (() -> Void)?
    let id: UUID
    private var startFrame: CGRect = .zero
    private var pinchStartFrame: CGRect = .zero
    private var bodyMovePan: UIPanGestureRecognizer?
    private var moveHandlePan: UIPanGestureRecognizer?
    private var resizeHandlePan: UIPanGestureRecognizer?
    private var pinchGesture: UIPinchGestureRecognizer?
    
    init(id: UUID) {
        self.id = id
        super.init(frame: .zero)
        setup()
    }
    
    required init?(coder: NSCoder) {
        self.id = UUID()
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        layer.zPosition = 1
        layer.cornerRadius = 6
        applyUserBorder()
        
        textView.backgroundColor = .clear
        textView.font = UIFont.systemFont(ofSize: 14)
        textView.textColor = .label
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.delegate = self
        addSubview(textView)
        
        moveHandle.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.12)
        moveHandle.layer.cornerRadius = 6
        moveHandle.layer.borderWidth = 1
        moveHandle.layer.borderColor = UIColor.systemBlue.cgColor
        moveIcon.image = UIImage(systemName: "arrow.up.and.down.and.arrow.left.and.right")
        moveIcon.tintColor = UIColor.systemBlue
        moveIcon.contentMode = .scaleAspectFit
        moveHandle.addSubview(moveIcon)
        addSubview(moveHandle)
        
        resizeHandleVisual.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.12)
        resizeHandleVisual.layer.cornerRadius = 6
        resizeHandleVisual.layer.borderWidth = 1
        resizeHandleVisual.layer.borderColor = UIColor.systemOrange.cgColor
        resizeIcon.image = UIImage(systemName: "arrow.up.left.and.down.right")
        resizeIcon.tintColor = UIColor.systemOrange
        resizeIcon.contentMode = .scaleAspectFit
        resizeHandleVisual.addSubview(resizeIcon)
        resizeHitTarget.addSubview(resizeHandleVisual)
        addSubview(resizeHitTarget)
        resizeHitTarget.isUserInteractionEnabled = true
        
        let movePan = UIPanGestureRecognizer(target: self, action: #selector(handleMovePan(_:)))
        moveHandle.addGestureRecognizer(movePan)
        moveHandle.isUserInteractionEnabled = true
        moveHandlePan = movePan
        
        let bodyMovePan = UIPanGestureRecognizer(target: self, action: #selector(handleBodyMovePan(_:)))
        bodyMovePan.cancelsTouchesInView = false
        addGestureRecognizer(bodyMovePan)
        self.bodyMovePan = bodyMovePan
        
        let resizePan = UIPanGestureRecognizer(target: self, action: #selector(handleResizePan(_:)))
        resizeHitTarget.addGestureRecognizer(resizePan)
        resizeHandlePan = resizePan
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleSelect))
        addGestureRecognizer(tap)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        addGestureRecognizer(pinch)
        pinchGesture = pinch

        let overflowSymbolConfig = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
            .applying(UIImage.SymbolConfiguration(paletteColors: [.systemBackground, .systemOrange]))
        overflowIndicator.image = UIImage(systemName: "exclamationmark.circle.fill",
                                          withConfiguration: overflowSymbolConfig)
        overflowIndicator.contentMode = .scaleAspectFit
        overflowIndicator.isHidden = true
        overflowIndicator.layer.zPosition = 3
        overflowIndicator.isUserInteractionEnabled = false
        addSubview(overflowIndicator)

        isSelected = true
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        overlayHitTestForwardingOutOfBounds(host: self, point: point, event: event) { p, e in
            super.hitTest(p, with: e)
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        textView.frame = bounds.inset(by: padding)
        updateVerticalInset()

        let handleSize: CGFloat = 16
        moveHandle.frame = CGRect(x: -6, y: -6, width: handleSize, height: handleSize)
        moveIcon.frame = moveHandle.bounds.insetBy(dx: 2, dy: 2)
        let v = resizeVisualSize
        resizeHitTarget.frame = CGRect(
            x: bounds.width - v + 6,
            y: bounds.height - v + 6,
            width: v,
            height: v
        )
        resizeHandleVisual.frame = resizeHitTarget.bounds
        resizeIcon.frame = resizeHandleVisual.bounds.insetBy(dx: 3, dy: 3)

        let indicatorSize: CGFloat = 18
        overflowIndicator.frame = CGRect(
            x: (bounds.width - indicatorSize) / 2,
            y: bounds.height - indicatorSize * 0.55,
            width: indicatorSize,
            height: indicatorSize
        )
    }
    
    func setText(_ text: String) {
        textView.text = text
        if _autoResizeEnabled { autoExpandIfNeeded() }
        updateVerticalInset()
    }

    func setBackground(_ color: UIColor) {
        backgroundColor = color
    }

    func setFontSize(_ size: CGFloat, isBold: Bool = false) {
        textView.font = isBold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size)
        if _autoResizeEnabled { autoExpandIfNeeded() }
        updateVerticalInset()
    }

    func setAutoResize(_ enabled: Bool) {
        _autoResizeEnabled = enabled
        if enabled { autoExpandIfNeeded() }
        updateOverflowIndicator()
    }

    /// Backward-compatible entry point used by tap-create code paths.
    /// Keeps auto-resize enabled and optionally clamps the initial width.
    func setTapCreateAutoResize(enabled: Bool, maxWidth: CGFloat) {
        setAutoResize(enabled)
        guard enabled, maxWidth > 0 else { return }
        if frame.width > maxWidth {
            frame = CGRect(origin: frame.origin, size: CGSize(width: maxWidth, height: frame.height))
            autoExpandIfNeeded()
        }
    }

    func updateBorder(width: CGFloat, color: UIColor) {
        _borderWidth = width
        _borderColor = color
        if isSelected {
            updateSelectionUI()
        } else {
            applyUserBorder()
        }
    }

    private func applyUserBorder() {
        guard !isSelected else { return }
        layer.borderWidth = _borderWidth > 0 ? _borderWidth : 0
        layer.borderColor = _borderWidth > 0 ? _borderColor.cgColor : UIColor.clear.cgColor
    }

    /// Grows the text box height vertically to fit the current text content.
    /// Only modifies height; the user retains full control of width and position.
    private func autoExpandIfNeeded() {
        guard _autoResizeEnabled, let container = superview else { return }
        let textWidth = max(1, bounds.width - padding.left - padding.right)
        let fitting = textView.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude))
        let required = max(minSize.height, ceil(fitting.height) + padding.top + padding.bottom)
        let maxAllowed = container.bounds.height - frame.origin.y
        let newHeight = min(required, maxAllowed)
        guard abs(newHeight - frame.height) > 0.5 else { return }
        frame = CGRect(origin: frame.origin, size: CGSize(width: frame.width, height: newHeight))
    }
    
    func setTextColor(_ color: UIColor) {
        textView.textColor = color
    }

    func setTextAlignment(_ alignment: NSTextAlignment) {
        textView.textAlignment = alignment
    }

    func setVerticalAlignment(_ alignment: TextVerticalAlignment) {
        _verticalAlignment = alignment
        updateVerticalInset()
    }

    /// Adjusts `textContainerInset.top` so the text content sits at the
    /// correct vertical position within the text view frame.
    private func updateVerticalInset() {
        guard textView.frame.height > 0 else { return }
        let fitting = textView.sizeThatFits(CGSize(width: textView.frame.width, height: .greatestFiniteMagnitude))
        let contentHeight = fitting.height
        let available = textView.frame.height
        var topOffset: CGFloat = 0
        switch _verticalAlignment {
        case .top:
            topOffset = 0
        case .middle:
            topOffset = max(0, (available - contentHeight) / 2)
        case .bottom:
            topOffset = max(0, available - contentHeight)
        }
        textView.textContainerInset = UIEdgeInsets(top: topOffset, left: 0, bottom: 0, right: 0)
        updateOverflowIndicator()
    }

    private func updateOverflowIndicator() {
        guard textView.frame.width > 0, textView.frame.height > 0 else { return }
        let fitting = textView.sizeThatFits(
            CGSize(width: textView.frame.width, height: .greatestFiniteMagnitude)
        )
        let isOverflowing = fitting.height > textView.frame.height + 1
        overflowIndicator.isHidden = !isOverflowing
    }

    var isTextInputFirstResponder: Bool { textView.isFirstResponder }

    /// When `false`, Scribble is suppressed on this `UITextView` via `UIScribbleInteraction`.
    func setTextInputScribbleEnabled(_ enabled: Bool) {
        if enabled {
            if let interaction = scribbleSuppressionInteraction {
                textView.removeInteraction(interaction)
                scribbleSuppressionInteraction = nil
            }
        } else if scribbleSuppressionInteraction == nil {
            let interaction = UIScribbleInteraction(delegate: self)
            scribbleSuppressionInteraction = interaction
            textView.addInteraction(interaction)
        }
    }

    func scribbleInteraction(_ interaction: UIScribbleInteraction, shouldBeginAt location: CGPoint) -> Bool {
        false
    }
    
    func beginEditing() {
        textView.becomeFirstResponder()
    }

    func endEditingIfNeeded() {
        if textView.isFirstResponder {
            textView.resignFirstResponder()
        }
    }

    func setSelected(_ selected: Bool) {
        isSelected = selected
        updateSelectionUI()
    }
    
    func setSelectMode(_ enabled: Bool) {
        if enabled {
            endEditingIfNeeded()
        }
        isSelectMode = enabled
        textView.isEditable = !enabled
        bodyMovePan?.isEnabled = enabled
        moveHandlePan?.isEnabled = enabled
        resizeHandlePan?.isEnabled = enabled
        pinchGesture?.isEnabled = enabled
        if !enabled { isSelected = false }
        updateSelectionUI()
    }
    
    private func updateSelectionUI() {
        let alpha: CGFloat = (isSelectMode && isSelected) ? 1.0 : 0.0
        moveHandle.alpha = alpha
        resizeHitTarget.alpha = alpha
        if isSelectMode && isSelected {
            layer.borderWidth = max(_borderWidth, 1)
            layer.borderColor = UIColor.systemBlue.cgColor
        } else if isSelected {
            layer.borderWidth = max(_borderWidth, 1)
            layer.borderColor = UIColor.systemBlue.withAlphaComponent(0.45).cgColor
        } else {
            applyUserBorder()
        }
    }
    
    @objc private func handleSelect() {
        guard isSelectMode else { return }
        isSelected = true
        superview?.bringSubviewToFront(self)
        onSelect?(id)
    }
    
    @objc private func handleMovePan(_ gesture: UIPanGestureRecognizer) {
        guard isSelectMode else { return }
        guard let container = superview else { return }
        let translation = gesture.translation(in: container)
        var newFrame = frame.offsetBy(dx: translation.x, dy: translation.y)
        newFrame.origin.x = max(0, min(newFrame.origin.x, container.bounds.width - newFrame.width))
        newFrame.origin.y = max(0, min(newFrame.origin.y, container.bounds.height - newFrame.height))
        frame = newFrame
        gesture.setTranslation(.zero, in: container)
    }
    
    @objc private func handleBodyMovePan(_ gesture: UIPanGestureRecognizer) {
        guard isSelectMode else { return }
        guard let container = superview else { return }
        let translation = gesture.translation(in: container)
        switch gesture.state {
        case .began:
            startFrame = frame
            isSelected = true
            superview?.bringSubviewToFront(self)
            onSelect?(id)
        case .changed:
            var newFrame = frame.offsetBy(dx: translation.x, dy: translation.y)
            newFrame.origin.x = max(0, min(newFrame.origin.x, container.bounds.width - newFrame.width))
            newFrame.origin.y = max(0, min(newFrame.origin.y, container.bounds.height - newFrame.height))
            frame = newFrame
            gesture.setTranslation(.zero, in: container)
        default:
            break
        }
    }
    
    @objc private func handleResizePan(_ gesture: UIPanGestureRecognizer) {
        guard let container = superview else { return }
        let translation = gesture.translation(in: container)
        var newSize = CGSize(
            width: max(minSize.width, frame.width + translation.x),
            height: max(minSize.height, frame.height + translation.y)
        )
        if frame.origin.x + newSize.width > container.bounds.width {
            newSize.width = container.bounds.width - frame.origin.x
        }
        if frame.origin.y + newSize.height > container.bounds.height {
            newSize.height = container.bounds.height - frame.origin.y
        }
        frame = CGRect(origin: frame.origin, size: newSize)
        gesture.setTranslation(.zero, in: container)
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard isSelectMode, let container = superview else { return }
        switch gesture.state {
        case .began:
            pinchStartFrame = frame
            isSelected = true
            superview?.bringSubviewToFront(self)
            onSelect?(id)
        case .changed:
            let scale = gesture.scale
            let center = CGPoint(x: pinchStartFrame.midX, y: pinchStartFrame.midY)
            var newW = max(minSize.width,  pinchStartFrame.width  * scale)
            var newH = max(minSize.height, pinchStartFrame.height * scale)
            var newX = center.x - newW / 2
            var newY = center.y - newH / 2
            newX = max(0, min(newX, container.bounds.width  - newW))
            newY = max(0, min(newY, container.bounds.height - newH))
            newW = min(newW, container.bounds.width  - newX)
            newH = min(newH, container.bounds.height - newY)
            frame = CGRect(x: newX, y: newY, width: newW, height: newH)
        default:
            break
        }
    }
    
    func applyTextStyle(fontSize: CGFloat, isBold: Bool, textColor: UIColor) {
        let font = isBold ? UIFont.boldSystemFont(ofSize: fontSize) : UIFont.systemFont(ofSize: fontSize)
        if let range = textView.selectedTextRange, !textView.selectedTextRange!.isEmpty {
            let nsRange = textView.selectedRange
            let mutable = NSMutableAttributedString(attributedString: textView.attributedText ?? NSAttributedString(string: textView.text ?? ""))
            mutable.addAttribute(.font, value: font, range: nsRange)
            mutable.addAttribute(.foregroundColor, value: textColor, range: nsRange)
            textView.attributedText = mutable
            textView.selectedRange = nsRange
        } else {
            textView.font = font
            textView.textColor = textColor
        }
        textView.typingAttributes[.font] = font
        textView.typingAttributes[.foregroundColor] = textColor
        if _autoResizeEnabled { autoExpandIfNeeded() }
        updateVerticalInset()
    }

    func textViewDidChange(_ textView: UITextView) {
        if _autoResizeEnabled { autoExpandIfNeeded() }
        updateVerticalInset()
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        isSelected = true
        onSelect?(id)
        onTextEditingFocusChange?()
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        onTextEditingFocusChange?()
    }
}

/// Expands the tappable region beyond the visible resize knob (UIKit hit-testing uses `point(inside:with:)`).
private final class ResizeHandleHitTargetView: UIView {
    /// Extra points beyond the visible handle bounds that still count as a hit (easier to grab when resizing).
    static let expansion: CGFloat = 18
    
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -Self.expansion, dy: -Self.expansion).contains(point)
    }
}

final class ImageBoxView: UIView {
    private let imageView = UIImageView()
    private let moveHandle = UIView()
    private let moveIcon = UIImageView()
    private let resizeHitTarget = ResizeHandleHitTargetView()
    private let resizeHandleVisual = UIView()
    private let resizeIcon = UIImageView()
    private var pinchGesture: UIPinchGestureRecognizer?
    private let resizeFeedback = UIImpactFeedbackGenerator(style: .light)
    private let minSize = CGSize(width: 80, height: 80)
    private let resizeVisualSize: CGFloat = 24
    private var pinchStartFrame: CGRect = .zero
    
    let id: UUID
    var imageData: Data
    var imageBorderWidth: CGFloat = 0
    var imageBorderColor: UIColor = .black
    var onSelect: ((UUID) -> Void)?
    var onEndChange: ((OverlayImageState, OverlayImageState) -> Void)?
    private var startFrame: CGRect = .zero
    private var isSelectMode: Bool = false
    private var isSelected: Bool = false

    init(id: UUID, imageData: Data) {
        self.id = id
        self.imageData = imageData
        super.init(frame: .zero)
        setup()
        setImageData(imageData)
    }
    
    required init?(coder: NSCoder) {
        self.id = UUID()
        self.imageData = Data()
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        layer.cornerRadius = 6
        clipsToBounds = true
        applyImageBorder()

        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .clear
        addSubview(imageView)
        
        moveHandle.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.12)
        moveHandle.layer.cornerRadius = 6
        moveHandle.layer.borderWidth = 1
        moveHandle.layer.borderColor = UIColor.systemBlue.cgColor
        moveIcon.image = UIImage(systemName: "arrow.up.and.down.and.arrow.left.and.right")
        moveIcon.tintColor = UIColor.systemBlue
        moveIcon.contentMode = .scaleAspectFit
        moveHandle.addSubview(moveIcon)
        addSubview(moveHandle)
        
        resizeHandleVisual.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.12)
        resizeHandleVisual.layer.cornerRadius = 6
        resizeHandleVisual.layer.borderWidth = 1
        resizeHandleVisual.layer.borderColor = UIColor.systemOrange.cgColor
        resizeIcon.image = UIImage(systemName: "arrow.up.left.and.down.right")
        resizeIcon.tintColor = UIColor.systemOrange
        resizeIcon.contentMode = .scaleAspectFit
        resizeHandleVisual.addSubview(resizeIcon)
        resizeHitTarget.addSubview(resizeHandleVisual)
        addSubview(resizeHitTarget)
        resizeHitTarget.isUserInteractionEnabled = true
        
        let movePan = UIPanGestureRecognizer(target: self, action: #selector(handleMovePan(_:)))
        moveHandle.addGestureRecognizer(movePan)
        moveHandle.isUserInteractionEnabled = true
        
        let bodyMovePan = UIPanGestureRecognizer(target: self, action: #selector(handleBodyMovePan(_:)))
        addGestureRecognizer(bodyMovePan)
        
        let resizePan = UIPanGestureRecognizer(target: self, action: #selector(handleResizePan(_:)))
        resizeHitTarget.addGestureRecognizer(resizePan)
        
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinchGesture = pinch
        addGestureRecognizer(pinch)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleSelect))
        addGestureRecognizer(tap)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        overlayHitTestForwardingOutOfBounds(host: self, point: point, event: event) { p, e in
            super.hitTest(p, with: e)
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
        
        let handleSize: CGFloat = 16
        moveHandle.frame = CGRect(x: -6, y: -6, width: handleSize, height: handleSize)
        moveIcon.frame = moveHandle.bounds.insetBy(dx: 2, dy: 2)
        let v = resizeVisualSize
        resizeHitTarget.frame = CGRect(
            x: bounds.width - v + 6,
            y: bounds.height - v + 6,
            width: v,
            height: v
        )
        resizeHandleVisual.frame = resizeHitTarget.bounds
        resizeIcon.frame = resizeHandleVisual.bounds.insetBy(dx: 3, dy: 3)
    }
    
    func setImageData(_ data: Data) {
        imageData = data
        imageView.image = UIImage(data: data)
    }

    func updateBorder(width: CGFloat, color: UIColor) {
        imageBorderWidth = width
        imageBorderColor = color
        applyImageBorder()
    }

    private func applyImageBorder() {
        layer.borderWidth = imageBorderWidth > 0 ? imageBorderWidth : 0
        layer.borderColor = imageBorderWidth > 0 ? imageBorderColor.cgColor : UIColor.clear.cgColor
    }

    func setSelectMode(_ enabled: Bool) {
        isSelectMode = enabled
        if !enabled {
            isSelected = false
        }
        let alpha: CGFloat = (enabled && isSelected) ? 1.0 : 0.0
        moveHandle.alpha = alpha
        resizeHitTarget.alpha = alpha
        pinchGesture?.isEnabled = enabled
        if !enabled {
            resizeHandleVisual.transform = .identity
        }
        if enabled && isSelected {
            layer.borderWidth = max(imageBorderWidth, 1)
            layer.borderColor = UIColor.systemBlue.cgColor
        } else {
            applyImageBorder()
        }
    }

    func setSelected(_ selected: Bool) {
        isSelected = selected
        setSelectMode(isSelectMode)
    }

    @objc private func handleSelect() {
        guard isSelectMode else { return }
        isSelected = true
        superview?.bringSubviewToFront(self)
        onSelect?(id)
    }
    
    @objc private func handleMovePan(_ gesture: UIPanGestureRecognizer) {
        guard isSelectMode else { return }
        guard let container = superview else { return }
        let translation = gesture.translation(in: container)
        switch gesture.state {
        case .began:
            startFrame = frame
            isSelected = true
            onSelect?(id)
        case .changed:
            var newFrame = frame.offsetBy(dx: translation.x, dy: translation.y)
            newFrame.origin.x = max(0, min(newFrame.origin.x, container.bounds.width - newFrame.width))
            newFrame.origin.y = max(0, min(newFrame.origin.y, container.bounds.height - newFrame.height))
            frame = newFrame
            gesture.setTranslation(.zero, in: container)
        case .ended, .cancelled:
            let before = OverlayImageState(id: id, frame: startFrame, imageData: imageData, borderWidth: imageBorderWidth, borderColor: imageBorderColor)
            let after = OverlayImageState(id: id, frame: frame, imageData: imageData, borderWidth: imageBorderWidth, borderColor: imageBorderColor)
            onEndChange?(before, after)
        default:
            break
        }
    }
    
    @objc private func handleBodyMovePan(_ gesture: UIPanGestureRecognizer) {
        guard isSelectMode else { return }
        guard let container = superview else { return }
        let translation = gesture.translation(in: container)
        switch gesture.state {
        case .began:
            startFrame = frame
            isSelected = true
            onSelect?(id)
            superview?.bringSubviewToFront(self)
        case .changed:
            var newFrame = frame.offsetBy(dx: translation.x, dy: translation.y)
            newFrame.origin.x = max(0, min(newFrame.origin.x, container.bounds.width - newFrame.width))
            newFrame.origin.y = max(0, min(newFrame.origin.y, container.bounds.height - newFrame.height))
            frame = newFrame
            gesture.setTranslation(.zero, in: container)
        case .ended, .cancelled:
            let before = OverlayImageState(id: id, frame: startFrame, imageData: imageData, borderWidth: imageBorderWidth, borderColor: imageBorderColor)
            let after = OverlayImageState(id: id, frame: frame, imageData: imageData, borderWidth: imageBorderWidth, borderColor: imageBorderColor)
            if before.frame != after.frame {
                onEndChange?(before, after)
            }
        default:
            break
        }
    }
    
    @objc private func handleResizePan(_ gesture: UIPanGestureRecognizer) {
        guard isSelectMode else { return }
        guard let container = superview else { return }
        let translation = gesture.translation(in: container)
        switch gesture.state {
        case .began:
            startFrame = frame
            isSelected = true
            onSelect?(id)
            resizeFeedback.prepare()
            resizeFeedback.impactOccurred()
            UIView.animate(withDuration: 0.15, delay: 0, options: [.allowUserInteraction, .curveEaseOut]) {
                self.resizeHandleVisual.transform = CGAffineTransform(scaleX: 1.18, y: 1.18)
            }
        case .changed:
            var newSize = CGSize(
                width: max(minSize.width, frame.width + translation.x),
                height: max(minSize.height, frame.height + translation.y)
            )
            if frame.origin.x + newSize.width > container.bounds.width {
                newSize.width = container.bounds.width - frame.origin.x
            }
            if frame.origin.y + newSize.height > container.bounds.height {
                newSize.height = container.bounds.height - frame.origin.y
            }
            frame = CGRect(origin: frame.origin, size: newSize)
            gesture.setTranslation(.zero, in: container)
        case .ended, .cancelled:
            UIView.animate(withDuration: 0.2, delay: 0, options: [.allowUserInteraction, .curveEaseOut]) {
                self.resizeHandleVisual.transform = .identity
            }
            let before = OverlayImageState(id: id, frame: startFrame, imageData: imageData, borderWidth: imageBorderWidth, borderColor: imageBorderColor)
            let after = OverlayImageState(id: id, frame: frame, imageData: imageData, borderWidth: imageBorderWidth, borderColor: imageBorderColor)
            if before.frame != after.frame {
                onEndChange?(before, after)
            }
        default:
            break
        }
    }
    
    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard isSelectMode else { return }
        guard let container = superview else { return }
        switch gesture.state {
        case .began:
            pinchStartFrame = frame
            startFrame = frame
            isSelected = true
            onSelect?(id)
            superview?.bringSubviewToFront(self)
        case .changed:
            let scale = gesture.scale
            let center = CGPoint(x: pinchStartFrame.midX, y: pinchStartFrame.midY)
            var newW = max(minSize.width, pinchStartFrame.width * scale)
            var newH = max(minSize.height, pinchStartFrame.height * scale)
            var newX = center.x - newW / 2
            var newY = center.y - newH / 2
            newX = max(0, min(newX, container.bounds.width - newW))
            newY = max(0, min(newY, container.bounds.height - newH))
            newW = min(newW, container.bounds.width - newX)
            newH = min(newH, container.bounds.height - newY)
            newW = max(minSize.width, newW)
            newH = max(minSize.height, newH)
            frame = CGRect(x: newX, y: newY, width: newW, height: newH)
        case .ended, .cancelled:
            let before = OverlayImageState(id: id, frame: startFrame, imageData: imageData, borderWidth: imageBorderWidth, borderColor: imageBorderColor)
            let after = OverlayImageState(id: id, frame: frame, imageData: imageData, borderWidth: imageBorderWidth, borderColor: imageBorderColor)
            if before.frame != after.frame {
                onEndChange?(before, after)
            }
        default:
            break
        }
    }
}

// MARK: - ShapeBoxView

final class ShapeBoxView: UIView {
    let id: UUID
    private(set) var shapeKind: OverlayShapeKind
    private(set) var strokeColor: UIColor
    private(set) var lineWidth: CGFloat

    var onSelect: ((UUID) -> Void)?
    var onEndChange: ((OverlayShapeState, OverlayShapeState) -> Void)?

    private var isSelectMode: Bool = false
    private var isSelected: Bool = false

    private let selectionBorderLayer = CAShapeLayer()
    private let moveHandle = UIView()
    private let moveIcon = UIImageView()
    private let resizeHitTarget = ResizeHandleHitTargetView()
    private let resizeHandleVisual = UIView()
    private let resizeIcon = UIImageView()
    private var pinchGesture: UIPinchGestureRecognizer?
    private let resizeFeedback = UIImpactFeedbackGenerator(style: .light)
    private let minSize = CGSize(width: 30, height: 30)
    private let resizeVisualSize: CGFloat = 24
    private var pinchStartFrame: CGRect = .zero
    private var startFrame: CGRect = .zero

    init(id: UUID, kind: OverlayShapeKind, strokeColor: UIColor, lineWidth: CGFloat) {
        self.id = id
        self.shapeKind = kind
        self.strokeColor = strokeColor
        self.lineWidth = lineWidth
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        self.id = UUID()
        self.shapeKind = .rectangle
        self.strokeColor = .systemRed
        self.lineWidth = 2.0
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        isOpaque = false
        backgroundColor = .clear
        clipsToBounds = false

        // Selection border layer (blue dashed outline)
        selectionBorderLayer.fillColor = UIColor.clear.cgColor
        selectionBorderLayer.strokeColor = UIColor.systemBlue.cgColor
        selectionBorderLayer.lineWidth = 2
        selectionBorderLayer.lineDashPattern = [6, 4]
        selectionBorderLayer.isHidden = true
        layer.addSublayer(selectionBorderLayer)

        // Move handle (top-left, blue)
        moveHandle.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.12)
        moveHandle.layer.cornerRadius = 6
        moveHandle.layer.borderWidth = 1
        moveHandle.layer.borderColor = UIColor.systemBlue.cgColor
        moveIcon.image = UIImage(systemName: "arrow.up.and.down.and.arrow.left.and.right")
        moveIcon.tintColor = UIColor.systemBlue
        moveIcon.contentMode = .scaleAspectFit
        moveHandle.addSubview(moveIcon)
        addSubview(moveHandle)

        // Resize handle (bottom-right, orange)
        resizeHandleVisual.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.12)
        resizeHandleVisual.layer.cornerRadius = 6
        resizeHandleVisual.layer.borderWidth = 1
        resizeHandleVisual.layer.borderColor = UIColor.systemOrange.cgColor
        resizeIcon.image = UIImage(systemName: "arrow.up.left.and.down.right")
        resizeIcon.tintColor = UIColor.systemOrange
        resizeIcon.contentMode = .scaleAspectFit
        resizeHandleVisual.addSubview(resizeIcon)
        resizeHitTarget.addSubview(resizeHandleVisual)
        addSubview(resizeHitTarget)
        resizeHitTarget.isUserInteractionEnabled = true

        // Move handle pan
        let movePan = UIPanGestureRecognizer(target: self, action: #selector(handleMovePan(_:)))
        moveHandle.addGestureRecognizer(movePan)
        moveHandle.isUserInteractionEnabled = true

        // Body pan
        let bodyPan = UIPanGestureRecognizer(target: self, action: #selector(handleBodyMovePan(_:)))
        addGestureRecognizer(bodyPan)

        // Resize handle pan
        let resizePan = UIPanGestureRecognizer(target: self, action: #selector(handleResizePan(_:)))
        resizeHitTarget.addGestureRecognizer(resizePan)

        // Pinch gesture
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinchGesture = pinch
        addGestureRecognizer(pinch)

        // Tap to select
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleSelect))
        addGestureRecognizer(tap)

        updateHandleVisibility()
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        overlayHitTestForwardingOutOfBounds(host: self, point: point, event: event) { p, e in
            super.hitTest(p, with: e)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let handleSize: CGFloat = 16
        moveHandle.frame = CGRect(x: -6, y: -6, width: handleSize, height: handleSize)
        moveIcon.frame = moveHandle.bounds.insetBy(dx: 2, dy: 2)
        let v = resizeVisualSize
        resizeHitTarget.frame = CGRect(
            x: bounds.width - v + 6,
            y: bounds.height - v + 6,
            width: v,
            height: v
        )
        resizeHandleVisual.frame = resizeHitTarget.bounds
        resizeIcon.frame = resizeHandleVisual.bounds.insetBy(dx: 3, dy: 3)

        // Update selection border layer path to match the drawn shape
        let inset = lineWidth / 2
        let insetBounds = bounds.insetBy(dx: inset, dy: inset)
        selectionBorderLayer.frame = bounds
        switch shapeKind {
        case .circle:
            selectionBorderLayer.path = UIBezierPath(ovalIn: insetBounds).cgPath
        case .rectangle:
            selectionBorderLayer.path = UIBezierPath(roundedRect: insetBounds, cornerRadius: 4).cgPath
        case .triangle:
            let path = UIBezierPath()
            path.move(to: CGPoint(x: insetBounds.midX, y: insetBounds.minY))
            path.addLine(to: CGPoint(x: insetBounds.maxX, y: insetBounds.maxY))
            path.addLine(to: CGPoint(x: insetBounds.minX, y: insetBounds.maxY))
            path.close()
            selectionBorderLayer.path = path.cgPath
        }
    }

    override func draw(_ rect: CGRect) {
        strokeColor.setStroke()
        let insetRect = bounds.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        switch shapeKind {
        case .circle:
            let path = UIBezierPath(ovalIn: insetRect)
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        case .rectangle:
            let path = UIBezierPath(roundedRect: insetRect, cornerRadius: 4)
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        case .triangle:
            let path = UIBezierPath()
            path.move(to: CGPoint(x: insetRect.midX, y: insetRect.minY))
            path.addLine(to: CGPoint(x: insetRect.maxX, y: insetRect.maxY))
            path.addLine(to: CGPoint(x: insetRect.minX, y: insetRect.maxY))
            path.close()
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        }
    }

    func applyStyle(kind: OverlayShapeKind? = nil, strokeColor: UIColor, lineWidth: CGFloat) {
        if let kind {
            self.shapeKind = kind
        }
        self.strokeColor = strokeColor
        self.lineWidth = lineWidth
        setNeedsDisplay()
        setNeedsLayout()
    }

    func setSelectMode(_ enabled: Bool) {
        isSelectMode = enabled
        if !enabled { isSelected = false }
        pinchGesture?.isEnabled = enabled
        updateHandleVisibility()
    }

    func setSelected(_ selected: Bool) {
        isSelected = selected
        updateHandleVisibility()
    }

    private func updateHandleVisibility() {
        let alpha: CGFloat = (isSelectMode && isSelected) ? 1.0 : 0.0
        moveHandle.alpha = alpha
        resizeHitTarget.alpha = alpha
        selectionBorderLayer.isHidden = !(isSelectMode && isSelected)
    }

    @objc private func handleSelect() {
        guard isSelectMode else { return }
        isSelected = true
        superview?.bringSubviewToFront(self)
        onSelect?(id)
        updateHandleVisibility()
    }

    @objc private func handleMovePan(_ gesture: UIPanGestureRecognizer) {
        guard isSelectMode else { return }
        guard let container = superview else { return }
        let translation = gesture.translation(in: container)
        switch gesture.state {
        case .began:
            startFrame = frame
            isSelected = true
            onSelect?(id)
            updateHandleVisibility()
        case .changed:
            var newFrame = frame.offsetBy(dx: translation.x, dy: translation.y)
            newFrame.origin.x = max(0, min(newFrame.origin.x, container.bounds.width - newFrame.width))
            newFrame.origin.y = max(0, min(newFrame.origin.y, container.bounds.height - newFrame.height))
            frame = newFrame
            gesture.setTranslation(.zero, in: container)
        case .ended, .cancelled:
            let before = OverlayShapeState(id: id, frame: startFrame, kind: shapeKind, strokeColor: strokeColor, lineWidth: lineWidth)
            let after = OverlayShapeState(id: id, frame: frame, kind: shapeKind, strokeColor: strokeColor, lineWidth: lineWidth)
            onEndChange?(before, after)
        default:
            break
        }
    }

    @objc private func handleBodyMovePan(_ gesture: UIPanGestureRecognizer) {
        guard isSelectMode else { return }
        guard let container = superview else { return }
        let translation = gesture.translation(in: container)
        switch gesture.state {
        case .began:
            startFrame = frame
            isSelected = true
            onSelect?(id)
            superview?.bringSubviewToFront(self)
            updateHandleVisibility()
        case .changed:
            var newFrame = frame.offsetBy(dx: translation.x, dy: translation.y)
            newFrame.origin.x = max(0, min(newFrame.origin.x, container.bounds.width - newFrame.width))
            newFrame.origin.y = max(0, min(newFrame.origin.y, container.bounds.height - newFrame.height))
            frame = newFrame
            gesture.setTranslation(.zero, in: container)
        case .ended, .cancelled:
            let before = OverlayShapeState(id: id, frame: startFrame, kind: shapeKind, strokeColor: strokeColor, lineWidth: lineWidth)
            let after = OverlayShapeState(id: id, frame: frame, kind: shapeKind, strokeColor: strokeColor, lineWidth: lineWidth)
            if before.frame != after.frame {
                onEndChange?(before, after)
            }
        default:
            break
        }
    }

    @objc private func handleResizePan(_ gesture: UIPanGestureRecognizer) {
        guard isSelectMode else { return }
        guard let container = superview else { return }
        let translation = gesture.translation(in: container)
        switch gesture.state {
        case .began:
            startFrame = frame
            isSelected = true
            onSelect?(id)
            resizeFeedback.prepare()
            resizeFeedback.impactOccurred()
            UIView.animate(withDuration: 0.15, delay: 0, options: [.allowUserInteraction, .curveEaseOut]) {
                self.resizeHandleVisual.transform = CGAffineTransform(scaleX: 1.18, y: 1.18)
            }
            updateHandleVisibility()
        case .changed:
            var newSize = CGSize(
                width: max(minSize.width, frame.width + translation.x),
                height: max(minSize.height, frame.height + translation.y)
            )
            if frame.origin.x + newSize.width > container.bounds.width {
                newSize.width = container.bounds.width - frame.origin.x
            }
            if frame.origin.y + newSize.height > container.bounds.height {
                newSize.height = container.bounds.height - frame.origin.y
            }
            frame = CGRect(origin: frame.origin, size: newSize)
            gesture.setTranslation(.zero, in: container)
        case .ended, .cancelled:
            UIView.animate(withDuration: 0.2, delay: 0, options: [.allowUserInteraction, .curveEaseOut]) {
                self.resizeHandleVisual.transform = .identity
            }
            let before = OverlayShapeState(id: id, frame: startFrame, kind: shapeKind, strokeColor: strokeColor, lineWidth: lineWidth)
            let after = OverlayShapeState(id: id, frame: frame, kind: shapeKind, strokeColor: strokeColor, lineWidth: lineWidth)
            if before.frame != after.frame {
                onEndChange?(before, after)
            }
        default:
            break
        }
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard isSelectMode else { return }
        guard let container = superview else { return }
        switch gesture.state {
        case .began:
            pinchStartFrame = frame
            startFrame = frame
            isSelected = true
            onSelect?(id)
            superview?.bringSubviewToFront(self)
            updateHandleVisibility()
        case .changed:
            let scale = gesture.scale
            let center = CGPoint(x: pinchStartFrame.midX, y: pinchStartFrame.midY)
            var newW = max(minSize.width, pinchStartFrame.width * scale)
            var newH = max(minSize.height, pinchStartFrame.height * scale)
            var newX = center.x - newW / 2
            var newY = center.y - newH / 2
            newX = max(0, min(newX, container.bounds.width - newW))
            newY = max(0, min(newY, container.bounds.height - newH))
            newW = min(newW, container.bounds.width - newX)
            newH = min(newH, container.bounds.height - newY)
            newW = max(minSize.width, newW)
            newH = max(minSize.height, newH)
            frame = CGRect(x: newX, y: newY, width: newW, height: newH)
        case .ended, .cancelled:
            let before = OverlayShapeState(id: id, frame: startFrame, kind: shapeKind, strokeColor: strokeColor, lineWidth: lineWidth)
            let after = OverlayShapeState(id: id, frame: frame, kind: shapeKind, strokeColor: strokeColor, lineWidth: lineWidth)
            if before.frame != after.frame {
                onEndChange?(before, after)
            }
        default:
            break
        }
    }
}

extension DrawingPDFView {
    typealias ElementIdentifier = String
    
    func indirectScribbleInteraction(
        _ interaction: UIInteraction,
        isElementFocused elementIdentifier: ElementIdentifier
    ) -> Bool {
        return false
    }
    
    func indirectScribbleInteraction(
        _ interaction: UIInteraction,
        requestElementsIn rect: CGRect,
        completion: @escaping ([ElementIdentifier]) -> Void
    ) {
        guard let document = self.document else {
            completion([])
            return
        }
        
        var elementIDs: [String] = []
        
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            
            for annotation in page.annotations {
                if annotation.widgetFieldType == .text,
                   let fieldName = annotation.fieldName {
                    
                    // Convert annotation bounds to view coordinates
                    let pageBounds = annotation.bounds
                    let viewBounds = self.convert(pageBounds, from: page)
                    
                    if viewBounds.intersects(rect) {
                        elementIDs.append(fieldName)
                    }
                }
            }
        }
        
        completion(elementIDs)
    }
    
    func indirectScribbleInteraction(
        _ interaction: UIInteraction,
        frameForElement elementIdentifier: ElementIdentifier
    ) -> CGRect {
        guard let document = self.document else { return .zero }
        
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            
            for annotation in page.annotations {
                if annotation.fieldName == elementIdentifier {
                    return self.convert(annotation.bounds, from: page)
                }
            }
        }
        return .zero
    }
    
    func indirectScribbleInteraction(
        _ interaction: UIInteraction,
        focusElementIfNeeded elementIdentifier: ElementIdentifier,
        referencePoint focusReferencePoint: CGPoint,
        completion: @escaping ((UIResponder & UITextInput)?) -> Void
    ) {
        guard let document = self.document else {
            completion(nil)
            return
        }
        
        // Find and activate the PDF form field
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            
            for annotation in page.annotations {
                if annotation.fieldName == elementIdentifier {
                    // Use PDFView's built-in mechanism to focus the field
                    self.go(to: annotation.bounds, on: page)
                    
                    // Give PDFView a moment to create the text field, then find it
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        // Walk the view hierarchy to find the active UITextField
                        let textInput = self.findActiveTextInput()
                        completion(textInput)
                    }
                    return
                }
            }
        }
        completion(nil)
    }
    
    // Helper to find the focused UITextField/UITextView in PDFView's hierarchy
    private func findActiveTextInput() -> (UIResponder & UITextInput)? {
        return findTextInput(in: self)
    }
    
    private func findTextInput(in view: UIView) -> (UIResponder & UITextInput)? {
        if let textField = view as? UITextField, textField.isFirstResponder {
            return textField
        }
        if let textView = view as? UITextView, textView.isFirstResponder {
            return textView
        }
        for subview in view.subviews {
            if let found = findTextInput(in: subview) {
                return found
            }
        }
        return nil
    }
}

extension CGPath {
    func forEach(_ body: @escaping (CGPathElement) -> Void) {
        var body = body
        applyWithBlock { elementPointer in
            body(elementPointer.pointee)
        }
    }
}

extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }
}




// MARK: - Preview
#Preview {
    PDFEditorHomeView()
}
