import SwiftUI

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

    public init(
        url: URL,
        showsDismissButton: Bool = false,
        onSaveEditable: PDFEditorFileHandler? = nil,
        onExportFlattened: PDFEditorFileHandler? = nil
    ) {
        _viewModel = State(
            initialValue: PDFFormViewModel(
                documentURL: url,
                editableSaveHandler: onSaveEditable,
                flattenedExportHandler: onExportFlattened
            )
        )
        self.showsDismissButton = showsDismissButton
    }

    public var body: some View {
        PDFFormEditorView(
            viewModel: viewModel,
            showsDismissButton: showsDismissButton
        )
    }
}
