//
//  EditorModels.swift
//  PDFEditorSDK
//
//  Extracted from PDFEditorView.swift
//

import SwiftUI
import PDFKit
import UIKit

// MARK: - Undo Action Types
enum UndoAction {
    case annotation(PDFAnnotation)
    case formFieldChange(annotation: PDFAnnotation, previousValue: String?, newValue: String?)
    case drawingSession(page: PDFPage, oldAnnotations: [PDFAnnotation], newAnnotations: [PDFAnnotation])
    case overlayTextBox(add: OverlayTextBoxState?, remove: OverlayTextBoxState?)
    case moveAnnotation(annotation: PDFAnnotation, from: CGRect, to: CGRect)
    case overlayImage(add: OverlayImageState?, remove: OverlayImageState?)
    case overlayImageUpdate(before: OverlayImageState, after: OverlayImageState)
    case deleteInkAnnotation(annotation: PDFAnnotation, page: PDFPage)
    case overlayShape(add: OverlayShapeState?, remove: OverlayShapeState?)
    case overlayShapeUpdate(before: OverlayShapeState, after: OverlayShapeState)
    case addPage(page: PDFPage, at: Int)
    case removePage(page: PDFPage, at: Int)
}

enum EditorTool {
    case select
    case form
    case draw
    case erase
    case text
    case shape
    case pencilKit
}

enum OverlayShapeKind: String, Codable {
    case circle
    case rectangle
    case triangle
}

enum SelectedOverlayKind {
    case textBox, image, shape
}

struct OverlayTextBoxState: Identifiable {
    let id: UUID
    var frame: CGRect
    var text: String
    var backgroundColor: UIColor
    var fontSize: CGFloat
    var isBold: Bool
    var textColor: UIColor
}

struct OverlayImageState: Identifiable {
    let id: UUID
    var frame: CGRect
    var imageData: Data
    var borderWidth: CGFloat = 0
    var borderColor: UIColor = .black
}

struct OverlayShapeState: Identifiable {
    let id: UUID
    var frame: CGRect
    var kind: OverlayShapeKind
    var strokeColor: UIColor
    var lineWidth: CGFloat
}

struct OverlayDocumentMetadata: Codable {
    var textBoxes: [OverlayTextBoxMeta]
    var images: [OverlayImageMeta]
    var shapes: [OverlayShapeMeta]

    init(textBoxes: [OverlayTextBoxMeta] = [], images: [OverlayImageMeta] = [], shapes: [OverlayShapeMeta] = []) {
        self.textBoxes = textBoxes
        self.images = images
        self.shapes = shapes
    }

    // Backward-compat decode: shapes defaults to [] if absent
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        textBoxes = try container.decodeIfPresent([OverlayTextBoxMeta].self, forKey: .textBoxes) ?? []
        images = try container.decodeIfPresent([OverlayImageMeta].self, forKey: .images) ?? []
        shapes = try container.decodeIfPresent([OverlayShapeMeta].self, forKey: .shapes) ?? []
    }
}

struct OverlayTextBoxMeta: Codable {
    var id: UUID
    var pageIndex: Int
    var rect: RectCodable
    var text: String
    var background: RGBAColor
    var fontSize: CGFloat?
    var isBold: Bool?
    var textColor: RGBAColor?
}

struct OverlayImageMeta: Codable {
    var id: UUID
    var pageIndex: Int
    var rect: RectCodable
    var imageBase64: String
    var borderWidth: CGFloat?
    var borderColor: RGBAColor?
}

struct OverlayShapeMeta: Codable {
    var id: UUID
    var pageIndex: Int
    var rect: RectCodable
    var kindRaw: String
    var strokeColor: RGBAColor
    var lineWidth: CGFloat
}

struct RectCodable: Codable {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat
    
    init(_ rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.size.width
        height = rect.size.height
    }
    
    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

struct RGBAColor: Codable {
    var r: CGFloat
    var g: CGFloat
    var b: CGFloat
    var a: CGFloat
    
    init(_ color: UIColor) {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }
    
    init(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }
    
    var uiColor: UIColor {
        UIColor(red: r, green: g, blue: b, alpha: a)
    }
}
