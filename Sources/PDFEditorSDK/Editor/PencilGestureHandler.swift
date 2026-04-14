//
//  PencilGestureHandler.swift
//  PDFEditorSDK
//

import UIKit

// MARK: - Pencil Gesture Handler Protocol

/// Implemented by both ViewModels. Called by the canvas UIView when a
/// UIPencilInteraction fires. Always called on the MainActor.
@MainActor
protocol PencilGestureHandler: AnyObject {
    var activeTool: EditorTool { get set }
    var previousTool: EditorTool? { get set }
    var pencilDoubleTapAction: PencilGestureAction { get }
    var pencilSqueezeAction: PencilGestureAction { get }
    var pencilDoubleSqueezeAction: PencilGestureAction { get }
    func undo()
    func redo()
    func setTool(_ tool: EditorTool)
}

extension PencilGestureHandler {
    func perform(_ action: PencilGestureAction) {
        switch action {
        case .noAction:
            break

        // Eraser toggle — switches between eraser and draw (the classic Pencil 2 behaviour)
        case .toggleEraser:
            setTool(activeTool == .erase ? .draw : .erase)

        // History
        case .undo:
            undo()
        case .redo:
            redo()

        // Navigation
        case .switchToLastTool:
            if let prev = previousTool { setTool(prev) }

        // Direct tool activation
        case .activateSelect:
            setTool(.select)
        case .activateDraw:
            setTool(.draw)
        case .activateEraser:
            setTool(.erase)
        case .activateText:
            setTool(.text)
        case .activateShape:
            setTool(.shape)
        }
    }
}
