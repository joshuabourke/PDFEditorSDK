//
//  File.swift
//  PDFEditorSDK
//
//  Created by Josh Bourke on 9/4/2026.
//

import Foundation

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
    
    static let userDefaultsKey = "com.pdfeditor.editorPreferences"
    
    static func load() -> EditorPreferences {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let prefs = try? JSONDecoder().decode(EditorPreferences.self, from: data) else {
            return EditorPreferences()
        }
        return prefs
    }
    
    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: EditorPreferences.userDefaultsKey)
    }
}
