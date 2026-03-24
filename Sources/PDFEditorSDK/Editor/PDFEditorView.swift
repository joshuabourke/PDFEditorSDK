//
//  PDFEditorView.swift
//  VideoExamples
//
//  Created by Josh Bourke on 5/1/2026.
//


import SwiftUI
import PDFKit
import UIKit
import UniformTypeIdentifiers
import CoreText

// MARK: - Main App View
struct PDFEditorHomeView: View {
    @State private var viewModel = PDFFormViewModel()
    @State private var path: [EditorRoute] = []
    
    var body: some View {
        NavigationStack(path: $path) {
            PDFBrowseView(
                viewModel: viewModel,
                onOpen: { path.append(.editor) },
                onCreate: {
                    if viewModel.loadPDF() {
                        path.append(.editor)
                    }
                }
            )
            .navigationDestination(for: EditorRoute.self) { route in
                switch route {
                case .editor:
                    PDFFormEditorView(
                        viewModel: viewModel,
                        showsDismissButton: true,
                        onSaveNavigate: { path.removeAll() }
                    )
                }
            }
        }
    }
}

enum EditorRoute: Hashable {
    case editor
}

struct PDFFormEditorView: View {
    @Bindable var viewModel: PDFFormViewModel
    var showsDismissButton = false
    var onSaveNavigate: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    private let toolbarChipSize = CGSize(width: 56, height: 50)
    @State private var isShowingImporter = false
    @State private var isShowingSaveAlert = false
    @State private var isShowingExportAlert = false
    @State private var isShowingOpenAlert = false
    @State private var isShowingImagePicker = false
    @State private var imagePickerSource: ImagePickerSource = .photoLibrary
    @State private var isShowingShareSheet = false
    @State private var exportURL: URL?
    @State private var isShowingInsertPageSheet = false
    @State private var insertPageIndex = 0
    
    var body: some View {
        VStack {
            // Toolbar
            toolbarView
            
            // PDF View
            if viewModel.pdfDocument != nil {
                ZStack {
                    SimplePDFView(viewModel: viewModel)
                    if viewModel.isThumbnailOverlayVisible {
                        VStack {
                            Spacer()
                            PDFThumbnailStrip(viewModel: viewModel)
                                .padding(.horizontal, 12)
                                .padding(.bottom, 12)
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "No PDF Loaded",
                    systemImage: "doc.fill",
                    description: Text("The PDF form could not be loaded")
                )
            }
        }//: VSTACK
        .padding()
        .backgroundModifier()
        .navigationTitle("PDF Form Editor")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
                if showsDismissButton {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            dismiss()
                        } label: {
                            Label("Documents", systemImage: "doc.text")
                        }
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        viewModel.undo()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(!viewModel.canUndo)
                    
                    Button {
                        viewModel.redo()
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                    }
                    .disabled(!viewModel.canRedo)
                    
                    Button {
                        isShowingImporter = true
                    } label: {
                        Image(systemName: "folder")
                    }
                    
                    Button {
                        viewModel.savePDF()
                        isShowingSaveAlert = true
                        onSaveNavigate?()
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    
                    Button {
                        exportURL = viewModel.exportFlattenedPDF()
                        if exportURL != nil {
                            isShowingShareSheet = true
                        } else {
                            isShowingExportAlert = true
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        .fileImporter(
            isPresented: $isShowingImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                if !viewModel.loadPDF(from: url) {
                    isShowingOpenAlert = true
                }
            case .failure:
                break
            }
        }
        .alert("Save PDF", isPresented: $isShowingSaveAlert, actions: {
            Button("OK", role: .cancel) { }
        }, message: {
            Text(viewModel.saveStatus ?? "No status")
        })
        .alert("Export PDF", isPresented: $isShowingExportAlert, actions: {
            Button("OK", role: .cancel) { }
        }, message: {
            Text(viewModel.exportStatus ?? "No status")
        })
        .alert("Open PDF", isPresented: $isShowingOpenAlert, actions: {
            Button("OK", role: .cancel) { }
        }, message: {
            Text(viewModel.openStatus ?? "Failed to open PDF")
        })
        .confirmationDialog(
            "Add image to form field",
            isPresented: $viewModel.showFormWidgetImageSourceDialog,
            titleVisibility: .visible
        ) {
            Button("Take Photo") {
                viewModel.beginFormWidgetImagePickFromCamera()
                imagePickerSource = .camera
                isShowingImagePicker = true
            }
            Button("Photo Library") {
                viewModel.beginFormWidgetImagePickFromLibrary()
                imagePickerSource = .photoLibrary
                isShowingImagePicker = true
            }
            Button("Cancel", role: .cancel) {
                viewModel.cancelPendingFormWidgetImagePick()
            }
        } message: {
            Text("Choose a source for this field.")
        }
        .sheet(isPresented: $isShowingImagePicker) {
            ImagePicker(sourceType: imagePickerSource.uiSourceType, allowsEditing: true) { image in
                viewModel.handleImagePickedFromSheet(image)
            }
        }
        .sheet(isPresented: $isShowingShareSheet) {
            if let exportURL {
                ActivityView(activityItems: [exportURL])
            }
        }
        .sheet(isPresented: $isShowingInsertPageSheet) {
            NavigationStack {
                Form {
                    Picker("Insert Position", selection: $insertPageIndex) {
                        ForEach(0...max(viewModel.pageCount, 0), id: \.self) { index in
                            Text(insertPageLabel(for: index))
                                .tag(index)
                        }
                    }
                    .pickerStyle(.wheel)
                }
                .navigationTitle("Insert Page")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            isShowingInsertPageSheet = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Insert") {
                            viewModel.addBlankPage(at: insertPageIndex)
                            isShowingInsertPageSheet = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .onChange(of: viewModel.textBoxFontSize) { _, _ in
            viewModel.applyTextStyleToSelectedTextBox()
        }
        .onChange(of: viewModel.textBoxIsBold) { _, _ in
            viewModel.applyTextStyleToSelectedTextBox()
        }
        .onChange(of: viewModel.textBoxTextColor) { _, _ in
            viewModel.applyTextStyleToSelectedTextBox()
        }
        .onChange(of: viewModel.textBoxBackgroundColor) { _, _ in
            viewModel.applyTextStyleToSelectedTextBox()
        }
    }
    
    private var toolbarView: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 6) {
                        Text("Form")
                            .font(.caption2)
                            .tracking(0.5)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button {
                                viewModel.setTool(.form)
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: "text.document")
                                        .symbolVariant(viewModel.activeTool == .form ? .fill : .none)
                                        .fontWeight(.semibold)
                                    Text("Form")
                                        .fontWeight(.semibold)
                                }
                                .foregroundStyle(Color.accentColor)
                                .padding(6)
                                .background(viewModel.activeTool == .form ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.1), in: .rect(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            
                            Button {
                                viewModel.highlightSelectedText()
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: "highlighter")
                                        .fontWeight(.semibold)
                                    Text("Highlight")
                                        .fontWeight(.semibold)
                                }
                                .foregroundStyle(viewModel.hasTextSelection ? Color.accentColor : .secondary.opacity(0.3))
                                .padding(6)
                                .background(Color.secondary.opacity(0.1), in: .rect(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .disabled(!viewModel.hasTextSelection)
                            
                            Button {
                                viewModel.toggleScrollLock()
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: "lock")
                                        .symbolVariant(viewModel.pageScrollLocked ? .fill : .none)
                                        .fontWeight(.semibold)
                                    Text("Lock")
                                        .fontWeight(.semibold)
                                }
                                .foregroundStyle(Color.accentColor)
                                .padding(6)
                                .background(viewModel.pageScrollLocked ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.1), in: .rect(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 1, height: 36)
                        .padding(.top, 14)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Draw")
                            .font(.caption2)
                            .tracking(0.5)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        HStack(alignment: .center, spacing: 8) {
                            Button {
                                viewModel.setTool(.draw)
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: "pencil.and.scribble")
                                        .symbolVariant(viewModel.activeTool == .draw ? .fill : .none)
                                        .fontWeight(.semibold)
                                    Text("Draw")
                                        .fontWeight(.semibold)
                                }
                                .foregroundStyle(Color.accentColor)
                                .padding(6)
                                .background(viewModel.activeTool == .draw ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.1), in: .rect(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)

                            if viewModel.isDrawingMode {
                                toolbarSubtoolsRow {
                                    Menu {
                                        Button("Fine (1pt)") { viewModel.inkLineWidth = 1.0 }
                                        Button("Medium (3pt)") { viewModel.inkLineWidth = 3.0 }
                                        Button("Thick (6pt)") { viewModel.inkLineWidth = 6.0 }
                                    } label: {
                                        toolbarChip {
                                            Image(systemName: "lineweight")
                                                .fontWeight(.semibold)
                                            Text("\(Int(viewModel.inkLineWidth))pt")
                                                .fontWeight(.semibold)
                                        }
                                        .foregroundStyle(Color.accentColor)
                                        .padding(4)
                                        .background(toolbarChipBackground())
                                    }
                                    
                                    ColorPicker("", selection: Binding(
                                        get: { Color(viewModel.inkColor) },
                                        set: { viewModel.inkColor = UIColor($0) }
                                    ))
                                    .labelsHidden()
                                    .frame(width: toolbarChipSize.width, height: toolbarChipSize.height)

                                    Button {
                                        viewModel.isEraserMode.toggle()
                                    } label: {
                                        toolbarChip {
                                            Image(systemName: viewModel.isEraserMode ? "eraser.fill" : "eraser")
                                                .fontWeight(.semibold)
                                            Text("Erase")
                                                .fontWeight(.semibold)
                                        }
                                        .foregroundStyle(Color.accentColor)
                                        .padding(4)
                                        .background(toolbarChipBackground(isActive: viewModel.isEraserMode))
                                    }
                                    .buttonStyle(.plain)

                                    Menu {
                                        Button("Small (12pt)") { viewModel.eraserRadius = 6 }
                                        Button("Medium (18pt)") { viewModel.eraserRadius = 9 }
                                        Button("Large (26pt)") { viewModel.eraserRadius = 13 }
                                        Button("XL (36pt)") { viewModel.eraserRadius = 18 }
                                        Button("XXL (48pt)") { viewModel.eraserRadius = 24 }
                                    } label: {
                                        toolbarChip {
                                            Image(systemName: "circle.dashed")
                                                .fontWeight(.semibold)
                                            Text("\(Int(viewModel.eraserRadius * 2))pt")
                                                .fontWeight(.semibold)
                                        }
                                        .foregroundStyle(Color.accentColor)
                                        .padding(4)
                                        .background(toolbarChipBackground())
                                    }
                                }
                            }
                        }
                        .animation(.linear(duration: 0.2), value: viewModel.isDrawingMode)
                    }
                    
                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 1, height: 36)
                        .padding(.top, 14)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Text")
                            .font(.caption2)
                            .tracking(0.5)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        HStack(alignment: .center, spacing: 8) {
                            Button {
                                viewModel.setTool(.text)
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: "character.cursor.ibeam")
                                        .symbolVariant(viewModel.activeTool == .text ? .fill : .none)
                                        .fontWeight(.semibold)
                                    Text("Text")
                                        .fontWeight(.semibold)
                                }
                                .foregroundStyle(Color.accentColor)
                                .padding(6)
                                .background(viewModel.activeTool == .text ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.1), in: .rect(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)

                            if viewModel.isTextMode {
                                toolbarSubtoolsRow {

                                    Menu {
                                        Button("Black") { viewModel.textBoxTextColor = .label }
                                        Button("White") { viewModel.textBoxTextColor = .white }
                                        Button("Blue") { viewModel.textBoxTextColor = .systemBlue }
                                        Button("Red") { viewModel.textBoxTextColor = .systemRed }
                                        Button("Green") { viewModel.textBoxTextColor = .systemGreen }
                                    } label: {
                                        toolbarChip {
                                            Image(systemName: "square.fill")
                                                .font(.title3)
                                                .fontWeight(.semibold)
                                                .foregroundStyle(Color(viewModel.textBoxTextColor))
                                            Text("Text")
                                                .fontWeight(.semibold)
                                        }
                                        .foregroundStyle(Color.accentColor)
                                        .padding(4)
                                        .background(toolbarChipBackground())
                                    }
                                    
                                    Menu {
                                        Button("Yellow") { viewModel.textBoxBackgroundColor = UIColor.systemYellow }
                                        Button("Blue") { viewModel.textBoxBackgroundColor = UIColor.systemBlue }
                                        Button("Green") { viewModel.textBoxBackgroundColor = UIColor.systemGreen }
                                        Button("Pink") { viewModel.textBoxBackgroundColor = UIColor.systemPink }
                                    } label: {
                                        toolbarChip {
                                            Image(systemName: "square.fill")
                                                .font(.title3)
                                                .fontWeight(.semibold)
                                                .foregroundStyle(Color(viewModel.textBoxBackgroundColor))
                                            Text("BG")
                                                .fontWeight(.semibold)
                                        }
                                        .foregroundStyle(Color.accentColor)
                                        .padding(4)
                                        .background(toolbarChipBackground())
                                    }

                                    Menu {
                                        Button("Small (12pt)") { viewModel.textBoxFontSize = 12 }
                                        Button("Medium (14pt)") { viewModel.textBoxFontSize = 14 }
                                        Button("Large (18pt)") { viewModel.textBoxFontSize = 18 }
                                        Button("XL (22pt)") { viewModel.textBoxFontSize = 22 }
                                    } label: {
                                        toolbarChip {
                                            Image(systemName: "textformat.size")
                                                .font(.title3)
                                                .fontWeight(.semibold)
                                            Text("\(Int(viewModel.textBoxFontSize))pt")
                                                .fontWeight(.semibold)
                                        }
                                        .foregroundStyle(Color.accentColor)
                                        .padding(4)
                                        .background(toolbarChipBackground())
                                    }

                                    Button {
                                        viewModel.textBoxIsBold.toggle()
                                    } label: {
                                        toolbarChip {
                                            Image(systemName: "bold")
                                                .font(.title3)
                                                .fontWeight(.semibold)
                                            Text("Bold")
                                                .fontWeight(.semibold)
                                        }
                                        .foregroundStyle(Color.accentColor)
                                        .padding(4)
                                        .background(toolbarChipBackground(isActive: viewModel.textBoxIsBold))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .animation(.linear(duration: 0.2), value: viewModel.isTextMode)
                    }
                    
                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 1, height: 36)
                        .padding(.top, 14)
                    
                    VStack(spacing: 6) {
                        Text("Select")
                            .font(.caption2)
                            .tracking(0.5)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button {
                                viewModel.setTool(.select)
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: "cursorarrow.rays")
                                        .symbolVariant(viewModel.activeTool == .select ? .fill : .none)
                                        .fontWeight(.semibold)
                                    Text("Select")
                                        .fontWeight(.semibold)
                                }
                                .foregroundStyle(Color.accentColor)
                                .padding(6)
                                .background(viewModel.activeTool == .select ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.1), in: .rect(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            
                            if viewModel.hasSelectedInkAnnotation || viewModel.hasSelectedOverlayObject {
                                Button {
                                    viewModel.deleteSelectedSelection()
                                } label: {
                                    VStack(spacing: 4) {
                                        Image(systemName: "trash")
                                            .fontWeight(.semibold)
                                        Text("Delete")
                                            .fontWeight(.semibold)
                                    }
                                    .foregroundStyle(.red)
                                    .padding(6)
                                    .background(Color.red.opacity(0.1), in: .rect(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    
                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 1, height: 36)
                        .padding(.top, 14)
                    
                    VStack(spacing: 6) {
                        Text("Image")
                            .font(.caption2)
                            .tracking(0.5)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        HStack {
                            Menu {
                                Button("Camera") {
                                    viewModel.imagePickIsForFormWidget = false
                                    imagePickerSource = .camera
                                    isShowingImagePicker = true
                                }
                                Button("Photo Library") {
                                    viewModel.imagePickIsForFormWidget = false
                                    imagePickerSource = .photoLibrary
                                    isShowingImagePicker = true
                                }
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: "photo.on.rectangle")
                                        .fontWeight(.semibold)
                                    Text("Image")
                                        .fontWeight(.semibold)
                                }
                                .foregroundStyle(Color.accentColor)
                                .padding(6)
                                .background(Color.secondary.opacity(0.1), in: .rect(cornerRadius: 8))
                            }
                        }
                    }
                    
                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 1, height: 36)
                        .padding(.top, 14)
                    
                    VStack(spacing: 6) {
                        Text("Pages")
                            .font(.caption2)
                            .tracking(0.5)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        HStack {
                                    Button {
                                        insertPageIndex = min(viewModel.currentPageIndex + 1, viewModel.pageCount)
                                        isShowingInsertPageSheet = true
                                    } label: {
                                        VStack(spacing: 4) {
                                            Image(systemName: "doc.badge.plus")
                                                .fontWeight(.semibold)
                                    Text("Add Page")
                                        .fontWeight(.semibold)
                                }
                                .foregroundStyle(Color.accentColor)
                                .padding(6)
                                .background(Color.secondary.opacity(0.1), in: .rect(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            
                            Button {
                                viewModel.isThumbnailOverlayVisible.toggle()
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: viewModel.isThumbnailOverlayVisible ? "inset.filled.bottomthird.rectangle.portrait" : "rectangle.portrait")
                                        .fontWeight(.semibold)
                                    Text("Preview")
                                        .fontWeight(.semibold)
                                }
                                .foregroundStyle(Color.accentColor)
                                .padding(6)
                                .background(viewModel.isThumbnailOverlayVisible ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.1), in: .rect(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }//: HSTACK

            }//: SCROLL
        }//: VSTACK
        .contentBackgroundModifier()
    }
    
    private func toolbarChip<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 4) {
            content()
        }
        .frame(width: toolbarChipSize.width, height: toolbarChipSize.height, alignment: .top)
        .multilineTextAlignment(.center)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }

    private func toolbarChipBackground(isActive: Bool = false) -> some View {
        Color.clear
            .background(isActive ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.1), in: .rect(cornerRadius: 8))
    }

    /// Draw/Text subtools in a plain row so chips match the rest of the toolbar (no separate capsule).
    private func toolbarSubtoolsRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 8) {
            content()
        }
    }
    
    private func insertPageLabel(for index: Int) -> String {
        let pageNumber = index + 1
        if index == 0 {
            return "Before Page 1"
        }
        if index == viewModel.pageCount {
            return "After Page \(viewModel.pageCount)"
        }
        return "Before Page \(pageNumber)"
    }
}

enum ImagePickerSource {
    case camera
    case photoLibrary
    
    var uiSourceType: UIImagePickerController.SourceType {
        switch self {
        case .camera:
            return UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        case .photoLibrary:
            return .photoLibrary
        }
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let allowsEditing: Bool
    let onImagePicked: (UIImage?) -> Void
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.allowsEditing = allowsEditing
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onImagePicked: onImagePicked)
    }
    
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImagePicked: (UIImage?) -> Void
        
        init(onImagePicked: @escaping (UIImage?) -> Void) {
            self.onImagePicked = onImagePicked
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage
            onImagePicked(image)
            picker.dismiss(animated: true)
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onImagePicked(nil)
            picker.dismiss(animated: true)
        }
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - View Model
@MainActor
@Observable
class PDFFormViewModel {
    var pdfDocument: PDFDocument?
    var activeTool: EditorTool = .form
    var undoStack: [UndoAction] = []
    var redoStack: [UndoAction] = []
    var pageScrollLocked: Bool = false
    var hasTextSelection: Bool = false
    var hasSelectedInkAnnotation: Bool = false
    var hasSelectedOverlayObject: Bool = false
    weak var pdfView: DrawingPDFView?
    var inkColor: UIColor = .systemBlue
    var inkLineWidth: CGFloat = 2.0
    var isEraserMode: Bool = false
    var eraserRadius: CGFloat = 9
    var textBoxBackgroundColor: UIColor = UIColor.systemYellow
    var textBoxFontSize: CGFloat = 14
    var textBoxIsBold: Bool = false
    var textBoxTextColor: UIColor = .label
    var isThumbnailOverlayVisible: Bool = true
    var saveStatus: String?
    var exportStatus: String?
    var openStatus: String?
    var currentDocumentURL: URL?
    var lastSavedURL: URL?
    private let maxUndoActions = 50
    private var didLoadOverlayMetadata = false
    var needsOverlayRestore = false
    var currentPageIndex: Int = 0
    var pageCount: Int = 0
    
    /// When true, the image picker result is placed into the tapped PDF form widget instead of a free overlay.
    var imagePickIsForFormWidget = false
    var showFormWidgetImageSourceDialog = false
    private var pendingFormWidgetPageIndex: Int?
    private var pendingFormWidgetAnnotation: PDFAnnotation?
    private let editableSaveHandler: PDFEditorFileHandler?
    private let flattenedExportHandler: PDFEditorFileHandler?
    
    init(
        documentURL: URL? = nil,
        editableSaveHandler: PDFEditorFileHandler? = nil,
        flattenedExportHandler: PDFEditorFileHandler? = nil
    ) {
        self.editableSaveHandler = editableSaveHandler
        self.flattenedExportHandler = flattenedExportHandler
        if let documentURL {
            _ = loadPDF(from: documentURL)
        } else {
            _ = loadPDF()
        }
    }
    
    var isDrawingMode: Bool { activeTool == .draw }
    var isTextMode: Bool { activeTool == .text }
    var isSelectMode: Bool { activeTool == .select }
    
    @discardableResult
    func loadPDF() -> Bool {
        if let url = Bundle.main.url(forResource: "SampleForm", withExtension: "pdf") {
            currentDocumentURL = url
            pdfDocument = PDFDocument(url: url)
        } else {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let pdfURL = documentsPath.appendingPathComponent("SampleForm.pdf")
            currentDocumentURL = pdfURL
            pdfDocument = PDFDocument(url: pdfURL)
        }
        guard pdfDocument != nil else {
            openStatus = "Failed to load template PDF"
            return false
        }
        didLoadOverlayMetadata = false
        needsOverlayRestore = true
        updatePageMetrics()
        return true
    }
    
    @discardableResult
    func loadPDF(from url: URL) -> Bool {
        currentDocumentURL = url
        pdfDocument = PDFDocument(url: url)
        guard pdfDocument != nil else {
            openStatus = "Failed to open PDF"
            return false
        }
        didLoadOverlayMetadata = false
        needsOverlayRestore = true
        updatePageMetrics()
        return true
    }
    
    func setTool(_ tool: EditorTool) {
        if activeTool == tool, tool != .select {
            activeTool = .select
            pdfView?.endOverlayTextEditing()
            isEraserMode = false
            return
        }
        if tool != .text {
            pdfView?.endOverlayTextEditing()
        }
        activeTool = tool
        if tool != .draw {
            isEraserMode = false
        }
        if tool != .select {
            hasSelectedInkAnnotation = false
            pdfView?.deselectInkAnnotation()
        }
    }
    
    func toggleScrollLock() {
        pageScrollLocked.toggle()
    }
    
    func highlightSelectedText() {
        pdfView?.highlightCurrentSelection()
    }
    
    func addAnnotation(_ annotation: PDFAnnotation) {
        didMakeChange(.annotation(annotation))
    }
    
    func recordFormFieldChange(annotation: PDFAnnotation, previousValue: String?, newValue: String?) {
        didMakeChange(.formFieldChange(annotation: annotation, previousValue: previousValue, newValue: newValue))
    }
    
    func addImage(_ image: UIImage) {
        pdfView?.addOverlayImage(image)
    }
    
    func presentFormWidgetImageSourceChoice(pageIndex: Int, annotation: PDFAnnotation) {
        pendingFormWidgetPageIndex = pageIndex
        pendingFormWidgetAnnotation = annotation
        showFormWidgetImageSourceDialog = true
    }
    
    func cancelPendingFormWidgetImagePick() {
        pendingFormWidgetPageIndex = nil
        pendingFormWidgetAnnotation = nil
        imagePickIsForFormWidget = false
    }
    
    func beginFormWidgetImagePickFromCamera() {
        imagePickIsForFormWidget = true
        showFormWidgetImageSourceDialog = false
    }
    
    func beginFormWidgetImagePickFromLibrary() {
        imagePickIsForFormWidget = true
        showFormWidgetImageSourceDialog = false
    }
    
    func handleImagePickedFromSheet(_ image: UIImage?) {
        if imagePickIsForFormWidget {
            let pageIndex = pendingFormWidgetPageIndex
            let annotation = pendingFormWidgetAnnotation
            imagePickIsForFormWidget = false
            pendingFormWidgetPageIndex = nil
            pendingFormWidgetAnnotation = nil
            guard let image,
                  let pageIndex,
                  let annotation,
                  let page = pdfDocument?.page(at: pageIndex) else { return }
            pdfView?.addOverlayImage(image, forFormWidget: annotation, on: page)
            return
        }
        if let image {
            addImage(image)
        }
    }
    
    func applyTextStyleToSelectedTextBox() {
        pdfView?.applyTextStyleToSelectedTextBox(
            fontSize: textBoxFontSize,
            isBold: textBoxIsBold,
            textColor: textBoxTextColor,
            backgroundColor: textBoxBackgroundColor
        )
    }
    
    func updatePageMetrics() {
        pageCount = pdfDocument?.pageCount ?? 0
        if let page = pdfView?.currentPage, let document = pdfDocument {
            currentPageIndex = document.index(for: page)
        } else {
            currentPageIndex = 0
        }
    }
    
    func goToPage(index: Int) {
        guard let document = pdfDocument, index >= 0, index < document.pageCount else { return }
        if let page = document.page(at: index) {
            pdfView?.go(to: page)
            currentPageIndex = index
        }
    }
    
    func goToNextPage() {
        goToPage(index: currentPageIndex + 1)
    }
    
    func goToPreviousPage() {
        goToPage(index: currentPageIndex - 1)
    }
    
    func addBlankPage(at insertIndex: Int) {
        guard let document = pdfDocument else { return }
        let pageSize = pdfView?.currentPage?.bounds(for: .mediaBox).size ?? CGSize(width: 612, height: 792)
        let renderer = UIGraphicsImageRenderer(size: pageSize)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: pageSize))
        }
        guard let page = PDFPage(image: image) else { return }
        let safeInsertIndex = max(0, min(insertIndex, document.pageCount))
        document.insert(page, at: safeInsertIndex)
        updatePageMetrics()
        goToPage(index: safeInsertIndex)
    }
    
    func restoreOverlaysIfNeeded() {
        guard !didLoadOverlayMetadata else { return }
        pdfView?.readOverlayMetadata()
        didLoadOverlayMetadata = true
    }
    
    func undo() {
        guard let action = undoStack.popLast() else { return }
        let resolved = resolveOverlayStateIfNeeded(action)
        redoStack.append(resolved)
        performUndoAction(resolved)
    }
    
    func redo() {
            guard let action = redoStack.popLast() else { return }
            undoStack.append(action)
            
            performRedoAction(action)
        }

    private func resolveOverlayStateIfNeeded(_ action: UndoAction) -> UndoAction {
        switch action {
        case .overlayTextBox(let add, let remove):
            if let add, let current = pdfView?.overlayTextBoxState(id: add.id) {
                return .overlayTextBox(add: current, remove: remove)
            }
            return action
        case .overlayImage(let add, let remove):
            if let add, let current = pdfView?.overlayImageState(id: add.id) {
                return .overlayImage(add: current, remove: remove)
            }
            return action
        default:
            return action
        }
    }
    
    private func performUndoAction(_ action: UndoAction) {
            switch action {
            case .annotation(let ann):
                ann.page?.removeAnnotation(ann)
            case .formFieldChange(let ann, let prev, _):
                ann.widgetStringValue = prev
            case .drawingSession(let page, let old, let new):
                if let sel = pdfView?.selectedInkAnnotation, new.contains(where: { $0 === sel }) {
                    pdfView?.deselectInkAnnotation()
                }
                new.forEach { page.removeAnnotation($0) }
                old.forEach { page.addAnnotation($0) }
            case .overlayTextBox(let add, let remove):
                if let add {
                    pdfView?.removeOverlayTextBox(id: add.id)
                }
                if let remove {
                    pdfView?.addOverlayTextBox(from: remove)
                }
            case .moveAnnotation(let ann, let from, _):
                pdfView?.suppressGoTo = true
                ann.bounds = from
                pdfView?.suppressGoTo = false
                if pdfView?.selectedInkAnnotation === ann {
                    pdfView?.deselectInkAnnotation()
                }
            case .overlayImage(let add, let remove):
                if let add {
                    pdfView?.removeOverlayImage(id: add.id)
                }
                if let remove {
                    pdfView?.addOverlayImage(from: remove)
                }
            case .overlayImageUpdate(let before, _):
                pdfView?.updateOverlayImage(from: before)
            case .deleteInkAnnotation(let ann, let page):
                page.addAnnotation(ann)
            }
        }
    
    private func performRedoAction(_ action: UndoAction) {
            switch action {
            case .annotation(let ann):
                ann.page?.addAnnotation(ann)
            case .formFieldChange(let ann, _, let newValue):
                ann.widgetStringValue = newValue
            case .drawingSession(let page, let old, let new):
                old.forEach { page.removeAnnotation($0) }
                new.forEach { page.addAnnotation($0) }
            case .overlayTextBox(let add, let remove):
                if let add {
                    pdfView?.addOverlayTextBox(from: add)
                }
                if let remove {
                    pdfView?.removeOverlayTextBox(id: remove.id)
                }
            case .moveAnnotation(let ann, _, let to):
                pdfView?.suppressGoTo = true
                ann.bounds = to
                pdfView?.suppressGoTo = false
                if pdfView?.selectedInkAnnotation === ann {
                    pdfView?.deselectInkAnnotation()
                }
            case .overlayImage(let add, let remove):
                if let add {
                    pdfView?.addOverlayImage(from: add)
                }
                if let remove {
                    pdfView?.removeOverlayImage(id: remove.id)
                }
            case .overlayImageUpdate(_, let after):
                pdfView?.updateOverlayImage(from: after)
            case .deleteInkAnnotation(let ann, let page):
                page.removeAnnotation(ann)
                if pdfView?.selectedInkAnnotation === ann {
                    pdfView?.deselectInkAnnotation()
                }
            }
        }
    
    
    // Call this whenever a fresh change is made to clear the redo stack
    func didMakeChange(_ action: UndoAction) {
        undoStack.append(action)
        if undoStack.count > maxUndoActions {
            undoStack.removeFirst(undoStack.count - maxUndoActions)
        }
        redoStack.removeAll()
    }
    
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    
    func deleteSelectedSelection() {
        if hasSelectedInkAnnotation {
            deleteSelectedInkAnnotation()
        } else {
            pdfView?.deleteSelectedOverlayObject()
        }
    }
    
    func deleteSelectedInkAnnotation() {
        guard let pdfView, let annotation = pdfView.selectedInkAnnotation,
              let page = annotation.page else { return }
        page.removeAnnotation(annotation) 
        pdfView.deselectInkAnnotation()
        didMakeChange(.deleteInkAnnotation(annotation: annotation, page: page))
    }
    
    @discardableResult
    func savePDF() -> URL? {
        guard let document = pdfDocument else { return nil }
        
        pdfView?.writeOverlayMetadata()

        let fileName = defaultFileName(for: .editable)
        let stagingURL = stagingURL(fileName: fileName)
        try? FileManager.default.createDirectory(
            at: stagingURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )

        guard document.write(to: stagingURL) else {
            saveStatus = "Failed to save PDF"
            return nil
        }

        do {
            let finalURL = try finalizeGeneratedFile(
                at: stagingURL,
                request: PDFEditorFileRequest(
                    kind: .editable,
                    sourceURL: currentDocumentURL,
                    temporaryURL: stagingURL,
                    suggestedFileName: fileName
                ),
                handler: editableSaveHandler
            )
            currentDocumentURL = finalURL
            lastSavedURL = finalURL
            saveStatus = "Saved to: \(finalURL.lastPathComponent)"
            return finalURL
        } catch {
            saveStatus = "Failed to save PDF"
            return nil
        }
    }
    
    func exportFlattenedPDF() -> URL? {
        guard let document = pdfDocument else {
            exportStatus = "No overlays to export"
            return nil
        }
        guard let metadata = pdfView?.overlayMetadataSnapshot() else {
            exportStatus = "No overlays to export"
            return nil
        }

        let fileName = defaultFileName(for: .flattened)
        let stagingURL = stagingURL(fileName: fileName)
        try? FileManager.default.createDirectory(
            at: stagingURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )

        guard renderFlattenedPDF(document: document, metadata: metadata, destinationURL: stagingURL) else {
            exportStatus = "Failed to export PDF"
            return nil
        }

        do {
            let finalURL = try finalizeGeneratedFile(
                at: stagingURL,
                request: PDFEditorFileRequest(
                    kind: .flattened,
                    sourceURL: currentDocumentURL,
                    temporaryURL: stagingURL,
                    suggestedFileName: fileName
                ),
                handler: flattenedExportHandler
            )
            exportStatus = "Exported to: \(finalURL.lastPathComponent)"
            return finalURL
        } catch {
            exportStatus = "Failed to export PDF"
            return nil
        }
    }
    
    private func renderFlattenedPDF(
        document: PDFDocument,
        metadata: OverlayDocumentMetadata,
        destinationURL: URL
    ) -> Bool {
        guard document.pageCount > 0 else { return false }
        let firstBounds = document.page(at: 0)?.bounds(for: .mediaBox) ?? CGRect(x: 0, y: 0, width: 612, height: 792)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfDocumentInfo(from: document)
        let renderer = UIGraphicsPDFRenderer(bounds: firstBounds, format: format)
        
        do {
            try renderer.writePDF(to: destinationURL) { context in
                for pageIndex in 0..<document.pageCount {
                    guard let page = document.page(at: pageIndex) else { continue }
                    let bounds = page.bounds(for: .mediaBox)
                    context.beginPage(withBounds: bounds, pageInfo: [:])
                    
                    let cg = context.cgContext
                    cg.saveGState()
                    cg.translateBy(x: 0, y: bounds.height)
                    cg.scaleBy(x: 1, y: -1)
                    
                    let removedWidgetAnnotations = removeWidgetAnnotations(from: page)
                    page.draw(with: .mediaBox, to: cg)
                    restoreWidgetAnnotations(removedWidgetAnnotations, to: page)
                    
                    let textItems = metadata.textBoxes.filter { $0.pageIndex == pageIndex }
                    for item in textItems {
                        let rect = item.rect.cgRect
                        let textCornerRadius: CGFloat = 6
                        let textPadding = UIEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
                        let roundedTextRect = UIBezierPath(roundedRect: rect, cornerRadius: textCornerRadius)
                        cg.saveGState()
                        cg.addPath(roundedTextRect.cgPath)
                        cg.setFillColor(item.background.uiColor.cgColor)
                        cg.fillPath()
                        cg.restoreGState()
                        
                        drawText(
                            item.text,
                            in: rect.inset(by: textPadding),
                            fontSize: item.fontSize ?? 14,
                            isBold: item.isBold ?? false,
                            textColor: (item.textColor?.uiColor) ?? .label,
                            context: cg
                        )
                    }
                    
                    let imageItems = metadata.images.filter { $0.pageIndex == pageIndex }
                    for item in imageItems {
                        if let data = Data(base64Encoded: item.imageBase64),
                           let image = UIImage(data: data)?.cgImage {
                            let rect = item.rect.cgRect
                            let imageCornerRadius: CGFloat = 6
                            let roundedImageRect = UIBezierPath(roundedRect: rect, cornerRadius: imageCornerRadius)
                            cg.saveGState()
                            cg.addPath(roundedImageRect.cgPath)
                            cg.clip()
                            let fittedRect = aspectFitRect(for: image, in: rect)
                            cg.draw(image, in: fittedRect)
                            cg.restoreGState()
                        }
                    }
                    
                    cg.restoreGState()
                }
            }
            return true
        } catch {
            return false
        }
    }
    
    private func drawText(_ text: String, in rect: CGRect, fontSize: CGFloat, isBold: Bool, textColor: UIColor, context: CGContext) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineBreakMode = .byWordWrapping
        let font = isBold ? UIFont.boldSystemFont(ofSize: fontSize) : UIFont.systemFont(ofSize: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraph
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        
        context.saveGState()
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: rect, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, attributed.length), path, nil)
        CTFrameDraw(frame, context)
        context.restoreGState()
    }

    private func aspectFitRect(for image: CGImage, in rect: CGRect) -> CGRect {
        let imageSize = CGSize(width: image.width, height: image.height)
        guard imageSize.width > 0, imageSize.height > 0 else { return rect }
        let scale = min(rect.width / imageSize.width, rect.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2
        )
        return CGRect(origin: origin, size: size)
    }

    private func removeWidgetAnnotations(from page: PDFPage) -> [PDFAnnotation] {
        let widgets = page.annotations.filter {
            $0.type == PDFAnnotationSubtype.widget.rawValue || !$0.widgetFieldType.rawValue.isEmpty
        }
        for annotation in widgets {
            page.removeAnnotation(annotation)
        }
        return widgets
    }
    
    private func restoreWidgetAnnotations(_ widgets: [PDFAnnotation], to page: PDFPage) {
        for annotation in widgets {
            page.addAnnotation(annotation)
        }
    }

    private func defaultFileName(for kind: PDFEditorDocumentKind) -> String {
        let baseName = currentDocumentURL?.deletingPathExtension().lastPathComponent ?? "Document"
        switch kind {
        case .editable:
            return "\(baseName)-Editable.pdf"
        case .flattened:
            return "\(baseName)-Flattened.pdf"
        }
    }

    private func stagingURL(fileName: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(fileName)
    }

    private func finalizeGeneratedFile(
        at generatedURL: URL,
        request: PDFEditorFileRequest,
        handler: PDFEditorFileHandler?
    ) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: generatedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )

        if let handler {
            let finalURL = try handler(request)
            if finalURL != generatedURL, fileManager.fileExists(atPath: generatedURL.path) {
                try? fileManager.removeItem(at: generatedURL)
            }
            return finalURL
        }

        let folderURL = defaultFolderURL(for: request.kind)
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)
        let destinationURL = uniqueDestinationURL(
            for: request.suggestedFileName,
            in: folderURL
        )
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: generatedURL, to: destinationURL)
        return destinationURL
    }

    private func defaultFolderURL(for kind: PDFEditorDocumentKind) -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        switch kind {
        case .editable:
            return documentsPath.appendingPathComponent("PDFEdits", isDirectory: true)
        case .flattened:
            return documentsPath.appendingPathComponent("PDFExports", isDirectory: true)
        }
    }

    private func uniqueDestinationURL(for fileName: String, in folderURL: URL) -> URL {
        let baseName = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        let ext = URL(fileURLWithPath: fileName).pathExtension.isEmpty ? "pdf" : URL(fileURLWithPath: fileName).pathExtension
        var candidate = folderURL.appendingPathComponent("\(baseName).\(ext)")
        var counter = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folderURL.appendingPathComponent("\(baseName)-\(counter).\(ext)")
            counter += 1
        }
        return candidate
    }

    private func pdfDocumentInfo(from document: PDFDocument) -> [String: Any] {
        guard let attributes = document.documentAttributes else { return [:] }
        var info: [String: Any] = [:]

        if let title = attributes[PDFDocumentAttribute.titleAttribute] as? String, !title.isEmpty {
            info[kCGPDFContextTitle as String] = title
        }
        if let author = attributes[PDFDocumentAttribute.authorAttribute] as? String, !author.isEmpty {
            info[kCGPDFContextAuthor as String] = author
        }
        if let subject = attributes[PDFDocumentAttribute.subjectAttribute] as? String, !subject.isEmpty {
            info[kCGPDFContextSubject as String] = subject
        }
        if let creator = attributes[PDFDocumentAttribute.creatorAttribute] as? String, !creator.isEmpty {
            info[kCGPDFContextCreator as String] = creator
        }
        if let keywords = attributes[PDFDocumentAttribute.keywordsAttribute] {
            if let keywordString = keywords as? String, !keywordString.isEmpty {
                info[kCGPDFContextKeywords as String] = keywordString
            } else if let keywordList = keywords as? [String], !keywordList.isEmpty {
                info[kCGPDFContextKeywords as String] = keywordList
            }
        }

        return info
    }
}


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
}

enum EditorTool {
    case select
    case form
    case draw
    case text
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
}

struct OverlayDocumentMetadata: Codable {
    var textBoxes: [OverlayTextBoxMeta]
    var images: [OverlayImageMeta]
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
    
    var uiColor: UIColor {
        UIColor(red: r, green: g, blue: b, alpha: a)
    }
}

// MARK: - Simple PDF View
struct SimplePDFView: UIViewRepresentable {
    @Bindable var viewModel: PDFFormViewModel
    
    func makeUIView(context: Context) -> DrawingPDFView {
        let pdfView = DrawingPDFView()
        pdfView.document = viewModel.pdfDocument
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .systemGroupedBackground
        pdfView.setFormFieldEntryEnabled(true)
        pdfView.formViewModel = viewModel
        
        
        // Set reference for committing drawings
        viewModel.pdfView = pdfView
        
        return pdfView
    }
    
    func updateUIView(_ pdfView: DrawingPDFView, context: Context) {
        if pdfView.document !== viewModel.pdfDocument {
            pdfView.document = viewModel.pdfDocument
            pdfView.goToFirstPage(nil)
        }
        if viewModel.needsOverlayRestore {
            DispatchQueue.main.async {
                viewModel.restoreOverlaysIfNeeded()
                viewModel.needsOverlayRestore = false
            }
        }
        pdfView.isDrawingMode = viewModel.isDrawingMode
        pdfView.isTextMode = viewModel.isTextMode
        pdfView.isSelectMode = viewModel.isSelectMode
        pdfView.isFormMode = viewModel.activeTool == .form
        pdfView.currentInkColor = viewModel.inkColor
        pdfView.currentLineWidth = viewModel.inkLineWidth
        pdfView.isEraserMode = viewModel.isEraserMode
        pdfView.eraserRadius = viewModel.eraserRadius
        pdfView.textBoxBackgroundColor = viewModel.textBoxBackgroundColor
        pdfView.textBoxFontSize = viewModel.textBoxFontSize
        pdfView.textBoxIsBold = viewModel.textBoxIsBold
        pdfView.textBoxTextColor = viewModel.textBoxTextColor
        pdfView.setFormFieldEntryEnabled(viewModel.activeTool == .form)
        pdfView.isUserInteractionEnabled = !viewModel.pageScrollLocked
    }
}

struct PDFThumbnailStrip: View {
    @Bindable var viewModel: PDFFormViewModel
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 10) {
                    ForEach(0..<viewModel.pageCount, id: \.self) { index in
                        Button {
                            viewModel.goToPage(index: index)
                        } label: {
                            VStack(spacing: 0) {
                                thumbnailView(for: index)
                                Text("Page \(index + 1)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 4)
                                    .frame(maxWidth: .infinity)
                                    .background(.ultraThinMaterial)
                            }
                            .frame(width: 66)
                            .clipShape(.rect(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(index == viewModel.currentPageIndex ? Color.accentColor : Color.black.opacity(0.08), lineWidth: index == viewModel.currentPageIndex ? 2 : 1)
                            )
                            .shadow(color: Color.black.opacity(0.08), radius: 4, y: 2)
                        }
                        .buttonStyle(.plain)
                        .id(index)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .frame(height: 118)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 16))
            .onAppear {
                proxy.scrollTo(viewModel.currentPageIndex, anchor: .center)
            }
            .onChange(of: viewModel.currentPageIndex) { _, newValue in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }
    
    @ViewBuilder
    private func thumbnailView(for index: Int) -> some View {
        if let page = viewModel.pdfDocument?.page(at: index) {
            let image = page.thumbnail(of: CGSize(width: 66, height: 86), for: .mediaBox)
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 66, height: 86)
                .background(Color.white)
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.12))
                .frame(width: 66, height: 86)
        }
    }
}

struct PDFBrowseView: View {
    @Bindable var viewModel: PDFFormViewModel
    @State private var files: [URL] = []
    var onOpen: (() -> Void)?
    var onCreate: (() -> Void)?
    @State private var isShowingOpenAlert = false
    @State private var isShowingFileImporter = false
    
    var body: some View {
        List {
            Section("Create") {
                Button {
                    onCreate?()
                } label: {
                    Label("New From Template", systemImage: "doc.badge.plus")
                }
                
                Button {
                    isShowingFileImporter = true
                } label: {
                    Label("Open From Files", systemImage: "folder")
                }
            }
            
            if files.isEmpty {
                ContentUnavailableView(
                    "No Saved PDFs",
                    systemImage: "doc",
                    description: Text("Save a PDF to see it here.")
                )
            } else {
                Section("Saved") {
                    ForEach(files, id: \.self) { url in
                        Button {
                            if viewModel.loadPDF(from: url) {
                                onOpen?()
                            } else {
                                isShowingOpenAlert = true
                            }
                        } label: {
                            HStack {
                                Image(systemName: "doc.richtext")
                                    .foregroundStyle(.secondary)
                                Text(url.lastPathComponent)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Browse Documents")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadFiles)
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                openImportedFile(url)
            case .failure:
                viewModel.openStatus = "Failed to open file from Files."
                isShowingOpenAlert = true
            }
        }
        .alert("Open PDF", isPresented: $isShowingOpenAlert, actions: {
            Button("OK", role: .cancel) { }
        }, message: {
            Text(viewModel.openStatus ?? "Failed to open PDF")
        })
    }
    
    private func loadFiles() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folderURL = documentsPath.appendingPathComponent("PDFEdits", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
        self.files = files.sorted { lhs, rhs in
            let leftDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rightDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return leftDate > rightDate
        }
    }
    
    private func openImportedFile(_ url: URL) {
        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart { url.stopAccessingSecurityScopedResource() }
        }
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folderURL = documentsPath.appendingPathComponent("PDFEdits", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            let destinationURL = uniqueDestinationURL(for: url, in: folderURL)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: url, to: destinationURL)
            
            if viewModel.loadPDF(from: destinationURL) {
                loadFiles()
                onOpen?()
            } else {
                isShowingOpenAlert = true
            }
        } catch {
            viewModel.openStatus = "Failed to import PDF from Files."
            isShowingOpenAlert = true
        }
    }
    
    private func uniqueDestinationURL(for sourceURL: URL, in folderURL: URL) -> URL {
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension.isEmpty ? "pdf" : sourceURL.pathExtension
        var candidate = folderURL.appendingPathComponent("\(baseName).\(ext)")
        var counter = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folderURL.appendingPathComponent("\(baseName)-\(counter).\(ext)")
            counter += 1
        }
        return candidate
    }
}

// MARK: - Pencil Drawing Gesture Recognizer

@MainActor
protocol PencilDrawingGestureDelegate: AnyObject {
    func pencilTouchBegan(_ touch: UITouch, with event: UIEvent?)
    func pencilTouchMoved(_ touch: UITouch, with event: UIEvent?)
    func pencilTouchEnded(_ touch: UITouch, with event: UIEvent?)
    func pencilTouchCancelled(with event: UIEvent?)
}

class PencilDrawingGestureRecognizer: UIGestureRecognizer {
    weak var drawingDelegate: PencilDrawingGestureDelegate?
    
    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first, touch.type == .pencil else {
            for touch in touches { ignore(touch, for: event) }
            return
        }
        state = .began
        drawingDelegate?.pencilTouchBegan(touch, with: event)
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first, touch.type == .pencil else { return }
        state = .changed
        drawingDelegate?.pencilTouchMoved(touch, with: event)
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first, touch.type == .pencil else { return }
        state = .ended
        drawingDelegate?.pencilTouchEnded(touch, with: event)
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .cancelled
        drawingDelegate?.pencilTouchCancelled(with: event)
    }
}

// MARK: - Drawing PDF View
class DrawingPDFView: PDFView, @preconcurrency UIIndirectScribbleInteractionDelegate, PencilDrawingGestureDelegate {
    
    // MARK: - Properties
    weak var formViewModel: PDFFormViewModel?
    
    var isDrawingMode = false {
        didSet {
            if isDrawingMode || isTextMode {
                disableTextSelection()
                if let scribble = scribbleInteraction { removeInteraction(scribble) }
            } else {
                enableTextSelection()
                if let scribble = scribbleInteraction { addInteraction(scribble) }
            }
            
            if !isDrawingMode {
                hideEraserCircle()
            } else {
                deselectInkAnnotation()
            }
            pencilDrawingGesture?.isEnabled = isDrawingMode
            fingerPanGesture?.isEnabled = isDrawingMode
            fingerPinchGesture?.isEnabled = isDrawingMode
        }
    }
    
    var isTextMode = false {
        didSet {
            textBoxPanGesture?.isEnabled = isTextMode
            if isTextMode {
                if let scribble = scribbleInteraction { removeInteraction(scribble) }
            } else if !isDrawingMode {
                if let scribble = scribbleInteraction { addInteraction(scribble) }
            }
            
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
        }
    }
    
    var isSelectMode = false {
        didSet {
            guard oldValue != isSelectMode else { return }
            textBoxViews.values.forEach { $0.setSelectMode(isSelectMode) }
            imageBoxViews.values.forEach { $0.setSelectMode(isSelectMode) }
            inkSelectTapGesture?.isEnabled = isSelectMode
            if !isSelectMode {
                deselectInkAnnotation()
                deselectOverlaySelection()
            }
        }
    }
    
    var suppressGoTo = false
    
    var isFormMode = false {
        didSet {
            textBoxOverlayView.isUserInteractionEnabled = !isFormMode
            if isFormMode {
                enableTextSelection()
            } else if !isDrawingMode && !isTextMode {
                enableTextSelection()
            }
            updateFormFieldHighlights()
        }
    }

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
        // Remove PDFView's built-in gesture recognizers that handle text selection
        gestureRecognizers?.forEach { gesture in
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
        gestureRecognizers?.forEach { gesture in
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
    
    var currentInkColor: UIColor = .systemBlue
    var currentLineWidth: CGFloat = 2.0
    var isEraserMode: Bool = false
    var eraserRadius: CGFloat = 9 {
        didSet { updateEraserCircle() }
    }
    var textBoxBackgroundColor: UIColor = UIColor.systemYellow
    var textBoxFontSize: CGFloat = 14
    var textBoxIsBold: Bool = false
    var textBoxTextColor: UIColor = .label
    
    private var pencilDrawingGesture: PencilDrawingGestureRecognizer?
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
    private let textBoxOverlayView = UIView()
    /// Sits above PDF page tiles (below `textBoxOverlayView`) so field highlights show through opaque widget appearances.
    private let formFieldHighlightHostView = UIView()
    private let formFieldHighlightLayer = CAShapeLayer()
    private var textBoxViews: [UUID: TextBoxView] = [:]
    private var imageBoxViews: [UUID: ImageBoxView] = [:]
    private var selectedTextBoxID: UUID?
    private var selectedImageBoxID: UUID?
    private var movingInkAnnotation: PDFAnnotation?
    private var movingInkStartBounds: CGRect?
    private var movingInkOffset: CGPoint?
    private var lockedInkDragContentOffset: CGPoint?
    
    private(set) var selectedInkAnnotation: PDFAnnotation?
    private var selectedInkPage: PDFPage?
    private let inkSelectionOverlayView = UIView()
    private let inkSelectionBorderLayer = CAShapeLayer()
    private var inkSelectTapGesture: UITapGestureRecognizer?
    
    private let overlayMetadataPrefix = "OVERLAY_META_V1:"
    private let overlayMetadataPartPrefix = "OVERLAY_META_V1_PART:"
    
    // Form field tracking
    private var formFieldStates: [String: String?] = [:]
    
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
            textBoxOverlayView.isUserInteractionEnabled = true
            docView.addSubview(textBoxOverlayView)
            docView.bringSubviewToFront(textBoxOverlayView)
            if inkSelectionOverlayView.superview != nil {
                docView.bringSubviewToFront(inkSelectionOverlayView)
            }
        } else if let docView = documentView {
            docView.bringSubviewToFront(textBoxOverlayView)
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
        guard isDrawingMode, let sv = scrollView else { return }
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
        guard isDrawingMode else { return }
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

    private func updateFormFieldHighlights() {
        guard isFormMode, let document, documentView != nil else {
            formFieldHighlightLayer.isHidden = true
            return
        }
        formFieldHighlightLayer.isHidden = false
        formFieldHighlightLayer.frame = formFieldHighlightHostView.bounds
        let path = UIBezierPath()
        var didFindWidgets = false
        let widgetSubtype = PDFAnnotationSubtype.widget.rawValue
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            for annotation in page.annotations {
                let isWidgetSubtype = annotation.type == widgetSubtype
                let hasFieldName = annotation.fieldName != nil
                let hasWidgetFieldKind = !annotation.widgetFieldType.rawValue.isEmpty
                guard isWidgetSubtype || hasFieldName || hasWidgetFieldKind else { continue }
                guard annotation.bounds.width > 0, annotation.bounds.height > 0 else { continue }
                didFindWidgets = true
                let rectInView = convert(annotation.bounds, from: page)
                let rectInHost = formFieldHighlightHostView.convert(rectInView, from: self)
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
        pan.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue),
            NSNumber(value: UITouch.TouchType.pencil.rawValue)
        ]
        pan.delegate = self
        addGestureRecognizer(pan)
        textBoxPanGesture = pan
        textBoxPanGesture?.isEnabled = false
    }
    
    // MARK: - Pencil Touch Handlers (called by PencilDrawingGestureRecognizer)
    
    func pencilTouchBegan(_ touch: UITouch, with event: UIEvent?) {
        guard isDrawingMode else { return }
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
        guard isDrawingMode,
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
        guard isDrawingMode,
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
    
    private func buildInkAnnotation(from points: [CGPoint], color: UIColor, lineWidth: CGFloat) -> PDFAnnotation {
        
        // Handle single point — draw a dot
        let resolvedPoints: [CGPoint]
        if points.count == 1 {
            let p = points[0]
            resolvedPoints = [p, CGPoint(x: p.x + 0.5, y: p.y + 0.5)]
        } else {
            resolvedPoints = points
        }
        
        let path = UIBezierPath()
        path.move(to: resolvedPoints[0])
        for point in resolvedPoints.dropFirst() {
            path.addLine(to: point)
        }
        path.lineWidth = lineWidth
        
        // Round caps make strokes look much smoother
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
        
        let shifted = UIBezierPath()
        shifted.move(to: CGPoint(
            x: resolvedPoints[0].x - bounds.origin.x,
            y: resolvedPoints[0].y - bounds.origin.y
        ))
        for point in resolvedPoints.dropFirst() {
            shifted.addLine(to: CGPoint(
                x: point.x - bounds.origin.x,
                y: point.y - bounds.origin.y
            ))
        }
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
            updateTextBoxPreview(from: viewPoint, to: viewPoint)
            textBoxLayer.isHidden = false
        case .changed:
            guard let start = textBoxStartPoint else { return }
            updateTextBoxPreview(from: start, to: viewPoint)
        case .ended, .cancelled:
            guard let start = textBoxStartPoint else { return }
            textBoxLayer.isHidden = true
            textBoxStartPoint = nil
            let rectInView = rectFrom(start, to: viewPoint).insetBy(dx: -2, dy: -2)
            if rectInView.width >= 20, rectInView.height >= 20 {
                createOverlayTextBox(with: rectInView)
            }
        default:
            break
        }
    }
    
    private func updateTextBoxPreview(from start: CGPoint, to end: CGPoint) {
        let rect = rectFrom(start, to: end)
        textBoxLayer.path = UIBezierPath(rect: rect).cgPath
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
            textColor: textBoxTextColor
        )
        addOverlayTextBox(from: state, beginEditing: true)
        formViewModel?.didMakeChange(.overlayTextBox(add: state, remove: nil))
    }
    
    func addOverlayTextBox(from state: OverlayTextBoxState, beginEditing: Bool = false) {
        let box = TextBoxView(id: state.id)
        box.frame = state.frame
        box.setText(state.text)
        box.setBackground(state.backgroundColor)
        box.setFontSize(state.fontSize, isBold: state.isBold)
        box.setTextColor(state.textColor)
        box.onSelect = { [weak self] id in
            self?.selectTextBox(id: id)
        }
        box.setSelectMode(isSelectMode)
        textBoxOverlayView.addSubview(box)
        textBoxOverlayView.bringSubviewToFront(box)
        textBoxViews[state.id] = box
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
            textColor: box.currentTextColor
        )
    }
    
    func applyTextStyleToSelectedTextBox(fontSize: CGFloat, isBold: Bool, textColor: UIColor, backgroundColor: UIColor) {
        guard let selectedTextBoxID,
              let box = textBoxViews[selectedTextBoxID] else { return }
        box.applyTextStyle(fontSize: fontSize, isBold: isBold, textColor: textColor)
        box.setBackground(backgroundColor)
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
        
        let state = OverlayImageState(id: UUID(), frame: docRect, imageData: data)
        addOverlayImage(from: state)
        formViewModel?.didMakeChange(.overlayImage(add: state, remove: removed))
    }
    
    func addOverlayImage(from state: OverlayImageState) {
        let box = ImageBoxView(id: state.id, imageData: state.imageData)
        box.frame = state.frame
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
            imageData: box.imageData
        )
    }

    func deleteSelectedOverlayObject() {
        if let selectedTextBoxID, let state = overlayTextBoxState(id: selectedTextBoxID) {
            removeOverlayTextBox(id: selectedTextBoxID)
            formViewModel?.didMakeChange(.overlayTextBox(add: nil, remove: state))
            return
        }
        if let selectedImageBoxID, let state = overlayImageState(id: selectedImageBoxID) {
            removeOverlayImage(id: selectedImageBoxID)
            formViewModel?.didMakeChange(.overlayImage(add: nil, remove: state))
        }
    }

    func endOverlayTextEditing() {
        textBoxViews.values.forEach { $0.endEditingIfNeeded() }
        textBoxOverlayView.endEditing(true)
    }

    private func selectTextBox(id: UUID) {
        selectedTextBoxID = id
        selectedImageBoxID = nil
        deselectInkAnnotation()
        updateOverlaySelectionUI()
        if let box = textBoxViews[id] {
            textBoxOverlayView.bringSubviewToFront(box)
        }
    }

    private func selectImageBox(id: UUID) {
        selectedImageBoxID = id
        selectedTextBoxID = nil
        deselectInkAnnotation()
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
        syncOverlaySelectionState()
    }

    private func syncOverlaySelectionState() {
        formViewModel?.hasSelectedOverlayObject = (selectedTextBoxID != nil || selectedImageBoxID != nil)
    }

    func deselectOverlaySelection() {
        selectedTextBoxID = nil
        selectedImageBoxID = nil
        updateOverlaySelectionUI()
    }

    func writeOverlayMetadata() {
        guard let document else { return }
        
        let metadata = overlayMetadataSnapshot()
        let isEmpty = metadata.textBoxes.isEmpty && metadata.images.isEmpty
        
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
                textColor: RGBAColor(box.currentTextColor)
            )
            textMetas.append(meta)
        }
        
        for (id, box) in imageBoxViews {
            guard let pageInfo = pageRect(fromDocRect: box.frame) else { continue }
            let meta = OverlayImageMeta(
                id: id,
                pageIndex: pageInfo.pageIndex,
                rect: RectCodable(pageInfo.pageRect),
                imageBase64: box.imageData.base64EncodedString()
            )
            imageMetas.append(meta)
        }
        
        return OverlayDocumentMetadata(textBoxes: textMetas, images: imageMetas)
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
                textColor: (text.textColor?.uiColor) ?? .label
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
                imageData: data
            )
            addOverlayImage(from: state)
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
        return OverlayImageState(id: UUID(), frame: frameInDoc, imageData: data)
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
            let color = annotation.color ?? .systemBlue
            
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
    
    @objc private func handleTextSelectionChanged() {
        let hasSelection = currentSelection != nil && !(currentSelection?.string?.isEmpty ?? true)
        formViewModel?.hasTextSelection = hasSelection
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
    }
    
    @objc private func keyboardWillShow(_ notification: Notification) {
        captureFormFieldStates()
    }
    
    @objc private func keyboardDidHide(_ notification: Notification) {
        recordFormFieldChanges()
        formFieldStates.removeAll()
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
        guard let document = self.document else { return }
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            for annotation in page.annotations {
                if let fieldName = annotation.fieldName,
                   let previousValue = formFieldStates[fieldName],
                   let currentValue = annotation.widgetStringValue,
                   previousValue != currentValue {
                    formViewModel?.recordFormFieldChange(
                        annotation: annotation,
                        previousValue: previousValue,
                        newValue: currentValue
                    )
                }
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isDrawingMode || suppressGoTo { return }
        super.touchesBegan(touches, with: event)
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isDrawingMode || suppressGoTo { return }
        super.touchesMoved(touches, with: event)
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isDrawingMode || suppressGoTo { return }
        super.touchesEnded(touches, with: event)
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isDrawingMode || suppressGoTo { return }
        super.touchesCancelled(touches, with: event)
    }
    
    override func go(to page: PDFPage) { 
        if isDrawingMode || suppressGoTo { return }
        super.go(to: page)
    }
    
    override func go(to destination: PDFDestination) {
        if isDrawingMode || suppressGoTo { return }
        super.go(to: destination)
    }
    
    override func go(to rect: CGRect, on page: PDFPage) {
        if isDrawingMode || suppressGoTo { return }
        super.go(to: rect, on: page)
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isDrawingMode || suppressGoTo else {
            return super.hitTest(point, with: event)
        }
        return self
    }
    
    override func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        if gestureRecognizer === inkDragPanGesture || otherGestureRecognizer === inkDragPanGesture {
            return false
        }
        let drawGestures: [UIGestureRecognizer?] = [pencilDrawingGesture, fingerPanGesture, fingerPinchGesture]
        let isFirst = drawGestures.contains(where: { $0 === gestureRecognizer })
        let isSecond = drawGestures.contains(where: { $0 === otherGestureRecognizer })
        if isFirst && isSecond { return true }
        if isFirst || isSecond { return false }
        return super.gestureRecognizer(gestureRecognizer, shouldRecognizeSimultaneouslyWith: otherGestureRecognizer)
    }
    
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === textBoxPanGesture {
            guard isTextMode else { return false }
            let point = gestureRecognizer.location(in: textBoxOverlayView)
            if let hitView = textBoxOverlayView.hitTest(point, with: nil),
               hitView !== textBoxOverlayView {
                return false
            }
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }
}

final class TextBoxView: UIView, UITextViewDelegate {
    private let textView = UITextView()
    private let padding = UIEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
    private let moveHandle = UIView()
    private let moveIcon = UIImageView()
    private let resizeHandle = UIView()
    private let resizeIcon = UIImageView()
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
    var onSelect: ((UUID) -> Void)?
    let id: UUID
    private var startFrame: CGRect = .zero
    private var bodyMovePan: UIPanGestureRecognizer?
    private var moveHandlePan: UIPanGestureRecognizer?
    private var resizeHandlePan: UIPanGestureRecognizer?
    
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
        layer.borderWidth = 1
        layer.borderColor = UIColor.systemGray4.cgColor
        
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
        
        resizeHandle.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.12)
        resizeHandle.layer.cornerRadius = 6
        resizeHandle.layer.borderWidth = 1
        resizeHandle.layer.borderColor = UIColor.systemOrange.cgColor
        resizeIcon.image = UIImage(systemName: "arrow.up.left.and.down.right")
        resizeIcon.tintColor = UIColor.systemOrange
        resizeIcon.contentMode = .scaleAspectFit
        resizeHandle.addSubview(resizeIcon)
        addSubview(resizeHandle)
        
        let movePan = UIPanGestureRecognizer(target: self, action: #selector(handleMovePan(_:)))
        moveHandle.addGestureRecognizer(movePan)
        moveHandle.isUserInteractionEnabled = true
        moveHandlePan = movePan
        
        let bodyMovePan = UIPanGestureRecognizer(target: self, action: #selector(handleBodyMovePan(_:)))
        bodyMovePan.cancelsTouchesInView = false
        addGestureRecognizer(bodyMovePan)
        self.bodyMovePan = bodyMovePan
        
        let resizePan = UIPanGestureRecognizer(target: self, action: #selector(handleResizePan(_:)))
        resizeHandle.addGestureRecognizer(resizePan)
        resizeHandle.isUserInteractionEnabled = true
        resizeHandlePan = resizePan
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleSelect))
        addGestureRecognizer(tap)
        
        isSelected = true
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        textView.frame = bounds.inset(by: padding)
        
        let handleSize: CGFloat = 16
        moveHandle.frame = CGRect(x: -6, y: -6, width: handleSize, height: handleSize)
        moveIcon.frame = moveHandle.bounds.insetBy(dx: 2, dy: 2)
        resizeHandle.frame = CGRect(
            x: bounds.width - handleSize + 6,
            y: bounds.height - handleSize + 6,
            width: handleSize,
            height: handleSize
        )
        resizeIcon.frame = resizeHandle.bounds.insetBy(dx: 2, dy: 2)
    }
    
    func setText(_ text: String) {
        textView.text = text
    }
    
    func setBackground(_ color: UIColor) {
        backgroundColor = color
    }
    
    func setFontSize(_ size: CGFloat, isBold: Bool = false) {
        textView.font = isBold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size)
    }
    
    func setTextColor(_ color: UIColor) {
        textView.textColor = color
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
        if !enabled { isSelected = false }
        updateSelectionUI()
    }
    
    private func updateSelectionUI() {
        let alpha: CGFloat = (isSelectMode && isSelected) ? 1.0 : 0.0
        moveHandle.alpha = alpha
        resizeHandle.alpha = alpha
        if isSelectMode && isSelected {
            layer.borderColor = UIColor.systemBlue.cgColor
        } else if isSelected {
            layer.borderColor = UIColor.systemBlue.withAlphaComponent(0.45).cgColor
        } else {
            layer.borderColor = UIColor.systemGray4.cgColor
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
    }
    
    func textViewDidBeginEditing(_ textView: UITextView) {
        isSelected = true
        onSelect?(id)
    }
}

/// Expands the tappable region beyond the visible resize knob (UIKit hit-testing uses `point(inside:with:)`).
private final class ResizeHandleHitTargetView: UIView {
    static let expansion: CGFloat = 12
    
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
    private let resizeVisualSize: CGFloat = 22
    private var pinchStartFrame: CGRect = .zero
    
    let id: UUID
    var imageData: Data
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
        layer.borderWidth = 1
        layer.borderColor = UIColor.systemGray4.cgColor
        clipsToBounds = true
        
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
        layer.borderColor = ((enabled && isSelected) ? UIColor.systemBlue : UIColor.systemGray4).cgColor
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
            let before = OverlayImageState(id: id, frame: startFrame, imageData: imageData)
            let after = OverlayImageState(id: id, frame: frame, imageData: imageData)
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
            let before = OverlayImageState(id: id, frame: startFrame, imageData: imageData)
            let after = OverlayImageState(id: id, frame: frame, imageData: imageData)
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
            let before = OverlayImageState(id: id, frame: startFrame, imageData: imageData)
            let after = OverlayImageState(id: id, frame: frame, imageData: imageData)
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
            let before = OverlayImageState(id: id, frame: startFrame, imageData: imageData)
            let after = OverlayImageState(id: id, frame: frame, imageData: imageData)
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

private extension CGPath {
    func forEach(_ body: @escaping (CGPathElement) -> Void) {
        var body = body
        applyWithBlock { elementPointer in
            body(elementPointer.pointee)
        }
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }
}




// MARK: - Preview
#Preview {
    PDFEditorHomeView()
}
