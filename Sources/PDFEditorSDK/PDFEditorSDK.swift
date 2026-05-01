import SwiftUI

/// Describes a PDF form field, used to determine whether it should receive a blue highlight overlay.
public struct PDFFormFieldInfo: Sendable {
    /// The internal field name (`/T` key in the PDF dictionary), if present.
    public let fieldName: String?
    /// True when the field's `/Ff` flags have the ReadOnly bit set (bit 0, value 1).
    public let isReadOnly: Bool
    /// True when the annotation's `/F` flags have the Locked bit set (bit 8, value 128).
    /// Some PDF authoring tools use this to prevent the field from being repositioned or edited by users.
    public let isAnnotationLocked: Bool
}

public enum PDFEditorDocumentKind: Sendable {
    case editable
    case flattened
}

public struct PDFEditorFileRequest: Sendable {
    public let kind: PDFEditorDocumentKind
    public let sourceURL: URL?
    public let temporaryURL: URL
    public let suggestedFileName: String

    public init(
        kind: PDFEditorDocumentKind,
        sourceURL: URL?,
        temporaryURL: URL,
        suggestedFileName: String
    ) {
        self.kind = kind
        self.sourceURL = sourceURL
        self.temporaryURL = temporaryURL
        self.suggestedFileName = suggestedFileName
    }
}

public typealias PDFEditorFileHandler = (PDFEditorFileRequest) throws -> URL

public struct PDFEditorView: View {
    @State private var viewModel: PDFFormViewModel
    private let showsDismissButton: Bool
    private let showsHighlightButton: Bool
    private let showsLockButton: Bool
    private let showsPencilButton: Bool

    /// - Parameters:
    ///   - url: The PDF document to open.
    ///   - showsDismissButton: Whether to show a leading Close button in the navigation bar.
    ///   - onSaveEditable: Called when the user saves the editable PDF.
    ///   - onExportFlattened: Called when the user exports a flattened PDF.
    ///   - showsHighlightButton: Whether to show the selected-text highlight button.
    ///   - showsLockButton: Whether to show the page scroll lock button.
    ///   - showsPencilButton: Whether to show the PencilKit button.
    ///   - shouldHighlightFormField: Return `true` to show the blue highlight overlay for a field,
    ///     `false` to hide it. When `nil` (default), fields are highlighted unless they are
    ///     read-only (`isReadOnly`) or annotation-locked (`isAnnotationLocked`).
    public init(
        url: URL,
        showsDismissButton: Bool = false,
        onSaveEditable: PDFEditorFileHandler? = nil,
        onExportFlattened: PDFEditorFileHandler? = nil,
        showsHighlightButton: Bool = true,
        showsLockButton: Bool = true,
        showsPencilButton: Bool = true,
        shouldHighlightFormField: ((PDFFormFieldInfo) -> Bool)? = nil
    ) {
        _viewModel = State(
            initialValue: PDFFormViewModel(
                documentURL: url,
                editableSaveHandler: onSaveEditable,
                flattenedExportHandler: onExportFlattened,
                shouldHighlightFormField: shouldHighlightFormField
            )
        )
        self.showsDismissButton = showsDismissButton
        self.showsHighlightButton = showsHighlightButton
        self.showsLockButton = showsLockButton
        self.showsPencilButton = showsPencilButton
    }

    public var body: some View {
        PDFFormEditorView(
            viewModel: viewModel,
            showsDismissButton: showsDismissButton,
            showsHighlightButton: showsHighlightButton,
            showsLockButton: showsLockButton,
            showsPencilButton: showsPencilButton
        )
    }
}
