//
//  ImageCropViewController.swift
//  PDFEditorSDK
//

import UIKit

// MARK: - ImageCropViewController

final class ImageCropViewController: UIViewController {

    // MARK: - Handle positions

    private enum Handle {
        case none, move
        case topLeft, topCenter, topRight
        case middleLeft, middleRight
        case bottomLeft, bottomCenter, bottomRight
    }

    // MARK: - Inputs

    private let sourceImage: UIImage
    var onConfirm: ((UIImage) -> Void)?
    var onCancel: (() -> Void)?

    // MARK: - Views

    private let imageContainerView = UIView()
    private let imageView = UIImageView()
    private let overlay = CropOverlayView()

    // MARK: - State

    private var cropRect: CGRect = .zero {
        didSet {
            overlay.cropRect = cropRect
            overlay.setNeedsDisplay()
        }
    }
    private var initialCropRect: CGRect = .zero
    private var didSetInitialLayout = false
    private var activeHandle: Handle = .none
    private let minCropSize: CGFloat = 60

    // MARK: - Init

    init(image: UIImage) {
        self.sourceImage = image.cropVC_normalizedOrientation()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupNavBar()
        setupLayout()
        setupGesture()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !didSetInitialLayout, imageContainerView.bounds.width > 0 else { return }
        didSetInitialLayout = true
        resetCropToImageBounds()
        initialCropRect = cropRect
    }

    // MARK: - Setup

    private func setupNavBar() {
        view.backgroundColor = .black
        overrideUserInterfaceStyle = .dark
        title = "Crop"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Cancel", style: .plain, target: self, action: #selector(cancelTapped)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Use Photo", style: .done, target: self, action: #selector(confirmTapped)
        )
    }

    private func setupLayout() {
        // Image container fills the area above the toolbar
        imageContainerView.clipsToBounds = true
        imageContainerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(imageContainerView)

        // Image view — aspect fit inside the container
        imageView.image = sourceImage
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageContainerView.addSubview(imageView)

        // Overlay drawn on top, gestures handled by imageContainerView
        overlay.isUserInteractionEnabled = false
        overlay.backgroundColor = .clear
        overlay.translatesAutoresizingMaskIntoConstraints = false
        imageContainerView.addSubview(overlay)

        // Bottom toolbar
        let toolbar = buildToolbar()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toolbar)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 56),

            imageContainerView.topAnchor.constraint(equalTo: guide.topAnchor, constant: 8),
            imageContainerView.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 8),
            imageContainerView.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -8),
            imageContainerView.bottomAnchor.constraint(equalTo: toolbar.topAnchor, constant: -8),

            imageView.topAnchor.constraint(equalTo: imageContainerView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: imageContainerView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: imageContainerView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: imageContainerView.bottomAnchor),

            overlay.topAnchor.constraint(equalTo: imageContainerView.topAnchor),
            overlay.leadingAnchor.constraint(equalTo: imageContainerView.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: imageContainerView.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: imageContainerView.bottomAnchor),
        ])
    }

    private func buildToolbar() -> UIView {
        let container = UIView()

        func iconButton(systemName: String, action: Selector) -> UIButton {
            let b = UIButton(type: .system)
            let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)
            b.setImage(UIImage(systemName: systemName, withConfiguration: config), for: .normal)
            b.tintColor = .white
            b.addTarget(self, action: action, for: .touchUpInside)
            return b
        }

        let rotateLeft  = iconButton(systemName: "rotate.left",  action: #selector(rotateLeft))
        let rotateRight = iconButton(systemName: "rotate.right", action: #selector(rotateRight))

        let resetBtn = UIButton(type: .system)
        resetBtn.setTitle("Reset", for: .normal)
        resetBtn.setTitleColor(.white, for: .normal)
        resetBtn.titleLabel?.font = .systemFont(ofSize: 16, weight: .regular)
        resetBtn.addTarget(self, action: #selector(resetCrop), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [rotateLeft, resetBtn, rotateRight])
        stack.axis = .horizontal
        stack.distribution = .equalSpacing
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 60),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -60),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    private func setupGesture() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        imageContainerView.addGestureRecognizer(pan)
    }

    // MARK: - Image Display Rect

    /// Returns the rect (in imageContainerView coordinates) where the image is actually rendered.
    private func imageDisplayRect() -> CGRect {
        let img = imageView.image ?? sourceImage
        let viewSize = imageContainerView.bounds.size
        let imgSize = img.size
        guard viewSize.width > 0, viewSize.height > 0,
              imgSize.width > 0, imgSize.height > 0 else {
            return imageContainerView.bounds
        }
        let scale = min(viewSize.width / imgSize.width, viewSize.height / imgSize.height)
        let w = imgSize.width * scale
        let h = imgSize.height * scale
        return CGRect(
            x: (viewSize.width - w) / 2,
            y: (viewSize.height - h) / 2,
            width: w,
            height: h
        )
    }

    private func resetCropToImageBounds() {
        cropRect = imageDisplayRect()
        initialCropRect = cropRect
    }

    // MARK: - Gesture Handling

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            let location = gesture.location(in: imageContainerView)
            activeHandle = handle(at: location)
            overlay.isDragging = activeHandle != .none
            overlay.setNeedsDisplay()
        case .changed:
            guard activeHandle != .none else { return }
            let t = gesture.translation(in: imageContainerView)
            applyTranslation(t, to: activeHandle)
            gesture.setTranslation(.zero, in: imageContainerView)
        case .ended, .cancelled:
            overlay.isDragging = false
            overlay.setNeedsDisplay()
            activeHandle = .none
        default:
            break
        }
    }

    private func handle(at point: CGPoint) -> Handle {
        let r = cropRect
        let hitRadius: CGFloat = 22

        func near(_ p: CGPoint) -> Bool {
            abs(point.x - p.x) < hitRadius && abs(point.y - p.y) < hitRadius
        }

        if near(CGPoint(x: r.minX, y: r.minY)) { return .topLeft }
        if near(CGPoint(x: r.midX, y: r.minY)) { return .topCenter }
        if near(CGPoint(x: r.maxX, y: r.minY)) { return .topRight }
        if near(CGPoint(x: r.minX, y: r.midY)) { return .middleLeft }
        if near(CGPoint(x: r.maxX, y: r.midY)) { return .middleRight }
        if near(CGPoint(x: r.minX, y: r.maxY)) { return .bottomLeft }
        if near(CGPoint(x: r.midX, y: r.maxY)) { return .bottomCenter }
        if near(CGPoint(x: r.maxX, y: r.maxY)) { return .bottomRight }
        if r.contains(point) { return .move }
        return .none
    }

    private func applyTranslation(_ t: CGPoint, to handle: Handle) {
        let bounds = imageDisplayRect()
        var r = cropRect
        let dx = t.x, dy = t.y

        switch handle {
        case .topLeft:
            r.origin.x += dx; r.size.width  -= dx
            r.origin.y += dy; r.size.height -= dy
        case .topCenter:
            r.origin.y += dy; r.size.height -= dy
        case .topRight:
            r.size.width  += dx
            r.origin.y   += dy; r.size.height -= dy
        case .middleLeft:
            r.origin.x += dx; r.size.width -= dx
        case .middleRight:
            r.size.width += dx
        case .bottomLeft:
            r.origin.x += dx; r.size.width  -= dx
            r.size.height += dy
        case .bottomCenter:
            r.size.height += dy
        case .bottomRight:
            r.size.width  += dx
            r.size.height += dy
        case .move:
            r.origin.x += dx; r.origin.y += dy
        case .none:
            return
        }

        // Enforce minimum size
        if r.size.width  < minCropSize { r.size.width  = minCropSize }
        if r.size.height < minCropSize { r.size.height = minCropSize }

        // Clamp entirely within the image display rect
        r.origin.x = max(r.origin.x, bounds.minX)
        r.origin.y = max(r.origin.y, bounds.minY)
        r.size.width  = min(r.size.width,  bounds.maxX - r.origin.x)
        r.size.height = min(r.size.height, bounds.maxY - r.origin.y)

        cropRect = r
    }

    // MARK: - Actions

    @objc private func confirmTapped() {
        onConfirm?(croppedImage())
    }

    @objc private func cancelTapped() {
        onCancel?()
    }

    @objc private func rotateLeft() {
        applyRotation(-90)
    }

    @objc private func rotateRight() {
        applyRotation(90)
    }

    @objc private func resetCrop() {
        cropRect = initialCropRect
    }

    private func applyRotation(_ degrees: CGFloat) {
        let current = imageView.image ?? sourceImage
        imageView.image = current.cropVC_rotated(byDegrees: degrees)
        resetCropToImageBounds()
    }

    // MARK: - Crop Computation

    private func croppedImage() -> UIImage {
        let img = imageView.image ?? sourceImage
        let displayRect = imageDisplayRect()
        guard displayRect.width > 0, displayRect.height > 0 else { return img }

        // Map cropRect (imageContainerView coords) → image pixel coordinates
        let scaleX = img.size.width  / displayRect.width
        let scaleY = img.size.height / displayRect.height

        let pixelRect = CGRect(
            x: (cropRect.minX - displayRect.minX) * scaleX * img.scale,
            y: (cropRect.minY - displayRect.minY) * scaleY * img.scale,
            width:  cropRect.width  * scaleX * img.scale,
            height: cropRect.height * scaleY * img.scale
        )

        let imageBounds = CGRect(
            origin: .zero,
            size: CGSize(width: img.size.width * img.scale, height: img.size.height * img.scale)
        )
        let clipped = pixelRect.intersection(imageBounds)

        guard !clipped.isEmpty, let cgImg = img.cgImage?.cropping(to: clipped) else {
            return img
        }
        return UIImage(cgImage: cgImg, scale: img.scale, orientation: .up)
    }
}

// MARK: - CropOverlayView

private final class CropOverlayView: UIView {

    var cropRect: CGRect = .zero
    var isDragging: Bool = false

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), cropRect != .zero else { return }

        // Dim outside the crop rect
        ctx.setFillColor(UIColor.black.withAlphaComponent(0.55).cgColor)
        ctx.fill(rect)
        ctx.clear(cropRect)

        // Crop border
        ctx.setStrokeColor(UIColor.white.cgColor)
        ctx.setLineWidth(1.5)
        ctx.stroke(cropRect.insetBy(dx: 0.75, dy: 0.75))

        // Rule-of-thirds grid — only while the user is dragging a handle
        if isDragging {
            ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.3).cgColor)
            ctx.setLineWidth(0.5)
            for i in 1...2 {
                let f = CGFloat(i) / 3
                ctx.move(to: CGPoint(x: cropRect.minX + cropRect.width * f, y: cropRect.minY))
                ctx.addLine(to: CGPoint(x: cropRect.minX + cropRect.width * f, y: cropRect.maxY))
                ctx.move(to: CGPoint(x: cropRect.minX, y: cropRect.minY + cropRect.height * f))
                ctx.addLine(to: CGPoint(x: cropRect.maxX, y: cropRect.minY + cropRect.height * f))
            }
            ctx.strokePath()
        }

        // Corner L-shaped handles
        ctx.setStrokeColor(UIColor.white.cgColor)
        ctx.setLineWidth(3)
        ctx.setLineCap(.square)

        let hl: CGFloat = 22
        let r = cropRect

        // Top-left
        ctx.move(to: CGPoint(x: r.minX, y: r.minY + hl))
        ctx.addLine(to: CGPoint(x: r.minX, y: r.minY))
        ctx.addLine(to: CGPoint(x: r.minX + hl, y: r.minY))
        // Top-right
        ctx.move(to: CGPoint(x: r.maxX - hl, y: r.minY))
        ctx.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        ctx.addLine(to: CGPoint(x: r.maxX, y: r.minY + hl))
        // Bottom-left
        ctx.move(to: CGPoint(x: r.minX, y: r.maxY - hl))
        ctx.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        ctx.addLine(to: CGPoint(x: r.minX + hl, y: r.maxY))
        // Bottom-right
        ctx.move(to: CGPoint(x: r.maxX - hl, y: r.maxY))
        ctx.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        ctx.addLine(to: CGPoint(x: r.maxX, y: r.maxY - hl))
        ctx.strokePath()

        // Edge midpoint handles
        ctx.setLineWidth(2.5)
        let em: CGFloat = 14
        ctx.move(to: CGPoint(x: r.midX - em, y: r.minY)); ctx.addLine(to: CGPoint(x: r.midX + em, y: r.minY))
        ctx.move(to: CGPoint(x: r.midX - em, y: r.maxY)); ctx.addLine(to: CGPoint(x: r.midX + em, y: r.maxY))
        ctx.move(to: CGPoint(x: r.minX, y: r.midY - em)); ctx.addLine(to: CGPoint(x: r.minX, y: r.midY + em))
        ctx.move(to: CGPoint(x: r.maxX, y: r.midY - em)); ctx.addLine(to: CGPoint(x: r.maxX, y: r.midY + em))
        ctx.strokePath()
    }
}

// MARK: - UIImage helpers (file-private, prefixed to avoid collisions)

extension UIImage {

    /// Returns a copy of the image with imageOrientation normalised to .up.
    func cropVC_normalizedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        defer { UIGraphicsEndImageContext() }
        draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext() ?? self
    }

    /// Returns the image rotated by the given degrees (90 / -90 / 180 etc.).
    func cropVC_rotated(byDegrees degrees: CGFloat) -> UIImage {
        let radians = degrees * .pi / 180
        let rotatedBounds = CGRect(origin: .zero, size: size)
            .applying(CGAffineTransform(rotationAngle: radians))
            .integral
        let newSize = CGSize(
            width:  max(rotatedBounds.width,  1),
            height: max(rotatedBounds.height, 1)
        )
        UIGraphicsBeginImageContextWithOptions(newSize, false, scale)
        defer { UIGraphicsEndImageContext() }
        guard let ctx = UIGraphicsGetCurrentContext() else { return self }
        ctx.translateBy(x: newSize.width / 2, y: newSize.height / 2)
        ctx.rotate(by: radians)
        draw(in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
        return UIGraphicsGetImageFromCurrentImageContext() ?? self
    }
}
