//
//  File.swift
//  PDFEditorSDK
//
//  Created by Josh Bourke on 9/4/2026.
//

import Foundation

/// How line and border thickness is adjusted in tool panels and compact toolbars.
enum LineWidthInputStyle: String, Codable, CaseIterable, Identifiable {
    case presetButtons
    case stepper

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .presetButtons: return "Preset buttons"
        case .stepper: return "Stepper"
        }
    }
}

struct EditorPreferences: Codable {
    //Drawing
    var inkColor: RGBAColor = RGBAColor(r: 0, g: 0.48, b: 1, a: 1) //System Blue
    var inkLineWidth: CGFloat = 3.0

    //Eraser
    var eraserRadius: CGFloat = 9

    // Input Mode
    var drawWithFinger: Bool = false
    var pencilOnlyAnnotations: Bool = false

    // Pencil Gestures
    var pencilDoubleTapAction: PencilGestureAction    = .toggleEraser
    var pencilSqueezeAction: PencilGestureAction      = .noAction
    var pencilDoubleSqueezeAction: PencilGestureAction = .noAction

    //Text
    var textBoxFontSize: CGFloat = 14
    var textBoxIsBold: Bool = false
    var textBoxTextColor: RGBAColor = RGBAColor(r: 0, g: 0, b: 0, a: 1)
    var textBoxBackgroundColor: RGBAColor = RGBAColor(r: 1, g: 0.91, b: 0.25, a: 1)// System Yellow
    var textBoxTextAlignment: Int = 0              // NSTextAlignment.left.rawValue
    var textBoxVerticalAlignment: String = "top"   // TextVerticalAlignment.rawValue
    var textBoxAutoResize: Bool = false

    //Shape
    var activeShapeKind: OverlayShapeKind = .rectangle
    var shapeStrokeColor: RGBAColor = RGBAColor(r: 1, g: 0.23, b: 0.19, a: 1) // System Red
    var shapeLineWidth: CGFloat = 2.0

    //Image Border
    var imageBorderWidth: CGFloat = 0
    var imageBorderColor: RGBAColor = RGBAColor(r: 0, g: 0, b: 0, a: 1)

    //Text Border
    var textBoxBorderWidth: CGFloat = 0
    var textBoxBorderColor: RGBAColor = RGBAColor(r: 0, g: 0, b: 0, a: 1)

    // Thumbnail
    var isThumbnailOverlayVisible: Bool = true

    // Toolbar
    var toolbarCompact: Bool = false

    /// Global UI for draw/shape stroke and image/text border widths.
    var lineWidthInputStyle: LineWidthInputStyle = .presetButtons
    /// Step size in points when using stepper mode (clamped when saving).
    var lineWidthStep: CGFloat = 0.5
    /// Upper bound in points for stepper mode (clamped when saving).
    var lineWidthMax: CGFloat = 24

    static let userDefaultsKey = "com.pdfeditor.editorPreferences"

    private enum CodingKeys: String, CodingKey {
        case inkColor, inkLineWidth, eraserRadius
        case drawWithFinger, pencilOnlyAnnotations
        case pencilDoubleTapAction, pencilSqueezeAction, pencilDoubleSqueezeAction
        case textBoxFontSize, textBoxIsBold, textBoxTextColor, textBoxBackgroundColor
        case textBoxTextAlignment, textBoxVerticalAlignment, textBoxAutoResize
        case activeShapeKind, shapeStrokeColor, shapeLineWidth
        case imageBorderWidth, imageBorderColor
        case textBoxBorderWidth, textBoxBorderColor
        case isThumbnailOverlayVisible
        case toolbarCompact
        case lineWidthInputStyle, lineWidthStep, lineWidthMax
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        inkColor = try c.decodeIfPresent(RGBAColor.self, forKey: .inkColor)
            ?? RGBAColor(r: 0, g: 0.48, b: 1, a: 1)
        inkLineWidth = Self.decodeCGFloat(c, forKey: .inkLineWidth, default: 3)
        eraserRadius = Self.decodeCGFloat(c, forKey: .eraserRadius, default: 9)
        drawWithFinger = try c.decodeIfPresent(Bool.self, forKey: .drawWithFinger) ?? false
        pencilOnlyAnnotations = try c.decodeIfPresent(Bool.self, forKey: .pencilOnlyAnnotations) ?? false
        pencilDoubleTapAction = try c.decodeIfPresent(PencilGestureAction.self, forKey: .pencilDoubleTapAction) ?? .toggleEraser
        pencilSqueezeAction = try c.decodeIfPresent(PencilGestureAction.self, forKey: .pencilSqueezeAction) ?? .noAction
        pencilDoubleSqueezeAction = try c.decodeIfPresent(PencilGestureAction.self, forKey: .pencilDoubleSqueezeAction) ?? .noAction
        textBoxFontSize = Self.decodeCGFloat(c, forKey: .textBoxFontSize, default: 14)
        textBoxIsBold = try c.decodeIfPresent(Bool.self, forKey: .textBoxIsBold) ?? false
        textBoxTextColor = try c.decodeIfPresent(RGBAColor.self, forKey: .textBoxTextColor)
            ?? RGBAColor(r: 0, g: 0, b: 0, a: 1)
        textBoxBackgroundColor = try c.decodeIfPresent(RGBAColor.self, forKey: .textBoxBackgroundColor)
            ?? RGBAColor(r: 1, g: 0.91, b: 0.25, a: 1)
        textBoxTextAlignment = try c.decodeIfPresent(Int.self, forKey: .textBoxTextAlignment) ?? 0
        textBoxVerticalAlignment = try c.decodeIfPresent(String.self, forKey: .textBoxVerticalAlignment) ?? "top"
        textBoxAutoResize = try c.decodeIfPresent(Bool.self, forKey: .textBoxAutoResize) ?? false
        activeShapeKind = try c.decodeIfPresent(OverlayShapeKind.self, forKey: .activeShapeKind) ?? .rectangle
        shapeStrokeColor = try c.decodeIfPresent(RGBAColor.self, forKey: .shapeStrokeColor)
            ?? RGBAColor(r: 1, g: 0.23, b: 0.19, a: 1)
        shapeLineWidth = Self.decodeCGFloat(c, forKey: .shapeLineWidth, default: 2)
        imageBorderWidth = Self.decodeCGFloat(c, forKey: .imageBorderWidth, default: 0)
        imageBorderColor = try c.decodeIfPresent(RGBAColor.self, forKey: .imageBorderColor)
            ?? RGBAColor(r: 0, g: 0, b: 0, a: 1)
        textBoxBorderWidth = Self.decodeCGFloat(c, forKey: .textBoxBorderWidth, default: 0)
        textBoxBorderColor = try c.decodeIfPresent(RGBAColor.self, forKey: .textBoxBorderColor)
            ?? RGBAColor(r: 0, g: 0, b: 0, a: 1)
        isThumbnailOverlayVisible = try c.decodeIfPresent(Bool.self, forKey: .isThumbnailOverlayVisible) ?? true
        toolbarCompact = try c.decodeIfPresent(Bool.self, forKey: .toolbarCompact) ?? false
        lineWidthInputStyle = try c.decodeIfPresent(LineWidthInputStyle.self, forKey: .lineWidthInputStyle) ?? .presetButtons
        lineWidthStep = Self.decodeCGFloat(c, forKey: .lineWidthStep, default: 0.5)
        lineWidthMax = Self.decodeCGFloat(c, forKey: .lineWidthMax, default: 24)
        normalizeLineWidthControlFields()
    }

    func encode(to encoder: Encoder) throws {
        var prefs = self
        prefs.normalizeLineWidthControlFields()
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(prefs.inkColor, forKey: .inkColor)
        try c.encode(Double(prefs.inkLineWidth), forKey: .inkLineWidth)
        try c.encode(Double(prefs.eraserRadius), forKey: .eraserRadius)
        try c.encode(prefs.drawWithFinger, forKey: .drawWithFinger)
        try c.encode(prefs.pencilOnlyAnnotations, forKey: .pencilOnlyAnnotations)
        try c.encode(prefs.pencilDoubleTapAction, forKey: .pencilDoubleTapAction)
        try c.encode(prefs.pencilSqueezeAction, forKey: .pencilSqueezeAction)
        try c.encode(prefs.pencilDoubleSqueezeAction, forKey: .pencilDoubleSqueezeAction)
        try c.encode(Double(prefs.textBoxFontSize), forKey: .textBoxFontSize)
        try c.encode(prefs.textBoxIsBold, forKey: .textBoxIsBold)
        try c.encode(prefs.textBoxTextColor, forKey: .textBoxTextColor)
        try c.encode(prefs.textBoxBackgroundColor, forKey: .textBoxBackgroundColor)
        try c.encode(prefs.textBoxTextAlignment, forKey: .textBoxTextAlignment)
        try c.encode(prefs.textBoxVerticalAlignment, forKey: .textBoxVerticalAlignment)
        try c.encode(prefs.textBoxAutoResize, forKey: .textBoxAutoResize)
        try c.encode(prefs.activeShapeKind, forKey: .activeShapeKind)
        try c.encode(prefs.shapeStrokeColor, forKey: .shapeStrokeColor)
        try c.encode(Double(prefs.shapeLineWidth), forKey: .shapeLineWidth)
        try c.encode(Double(prefs.imageBorderWidth), forKey: .imageBorderWidth)
        try c.encode(prefs.imageBorderColor, forKey: .imageBorderColor)
        try c.encode(Double(prefs.textBoxBorderWidth), forKey: .textBoxBorderWidth)
        try c.encode(prefs.textBoxBorderColor, forKey: .textBoxBorderColor)
        try c.encode(prefs.isThumbnailOverlayVisible, forKey: .isThumbnailOverlayVisible)
        try c.encode(prefs.toolbarCompact, forKey: .toolbarCompact)
        try c.encode(prefs.lineWidthInputStyle, forKey: .lineWidthInputStyle)
        try c.encode(Double(prefs.lineWidthStep), forKey: .lineWidthStep)
        try c.encode(Double(prefs.lineWidthMax), forKey: .lineWidthMax)
    }

    private static func decodeCGFloat(_ c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys, default def: CGFloat) -> CGFloat {
        if let v = try? c.decodeIfPresent(Double.self, forKey: key) {
            return CGFloat(v)
        }
        return def
    }

    mutating func normalizeLineWidthControlFields() {
        let steps: [CGFloat] = [0.25, 0.5, 1]
        lineWidthStep = steps.min { abs($0 - lineWidthStep) < abs($1 - lineWidthStep) } ?? 0.5
        let maxAllowed: [CGFloat] = [12, 24, 36, 48]
        lineWidthMax = maxAllowed.min { abs($0 - lineWidthMax) < abs($1 - lineWidthMax) } ?? 24
    }

    static func load() -> EditorPreferences {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let prefs = try? JSONDecoder().decode(EditorPreferences.self, from: data) else {
            return EditorPreferences()
        }
        return prefs
    }

    func save() {
        var copy = self
        copy.normalizeLineWidthControlFields()
        guard let data = try? JSONEncoder().encode(copy) else { return }
        UserDefaults.standard.set(data, forKey: EditorPreferences.userDefaultsKey)
    }
}

// MARK: - Line width formatting (toolbar labels)

enum LineWidthFormatting {
    static func snap(_ v: CGFloat, step: CGFloat, min minVal: CGFloat, max maxVal: CGFloat) -> CGFloat {
        guard step > 0 else { return Swift.min(Swift.max(v, minVal), maxVal) }
        let stepped = (v / step).rounded() * step
        return Swift.min(Swift.max(stepped, minVal), maxVal)
    }

    /// Short label for toolbar chips (respects stepper fractional widths).
    static func toolbarPointsLabel(_ value: CGFloat, style: LineWidthInputStyle, step: CGFloat) -> String {
        if value <= 0 { return "No Border" }
        if style == .stepper, step < 1 {
            let s = String(format: "%.1f", Double(value))
            return s + "pt"
        }
        return "\(Int(value.rounded()))pt"
    }

    static func shapeStrokeLabel(_ value: CGFloat, style: LineWidthInputStyle, step: CGFloat) -> String {
        if style == .stepper, step < 1 {
            return String(format: "%.1fpt", Double(value))
        }
        return "\(Int(value.rounded()))pt"
    }
}
