//
//  ImageEditorView.swift
//  PDFEditorSDK
//
//  Created by Josh Bourke on 24/3/2026.
//

import SwiftUI
import UIKit

// MARK: - Public Entry Point

public struct ImageEditorView: View {
    @State private var viewModel: ImageEditorViewModel

    public init(
        image: UIImage,
        onSave: ((UIImage) -> Void)? = nil,
        onExport: ((UIImage) -> Void)? = nil
    ) {
        _viewModel = State(initialValue: ImageEditorViewModel(sourceImage: image, onSave: onSave, onExport: onExport))
    }

    public init(
        imageData: Data,
        onSave: ((UIImage) -> Void)? = nil,
        onExport: ((UIImage) -> Void)? = nil
    ) {
        let image = UIImage(data: imageData) ?? UIImage()
        _viewModel = State(initialValue: ImageEditorViewModel(sourceImage: image, onSave: onSave, onExport: onExport))
    }

    public var body: some View {
        ImageFormEditorView(viewModel: viewModel)
    }
}

// MARK: - Image Form Editor View

struct ImageFormEditorView: View {
    @Bindable var viewModel: ImageEditorViewModel
    private let toolbarChipSize = CGSize(width: 56, height: 50)
    @State private var isShowingImagePicker = false
    @State private var imagePickerSource: ImagePickerSource = .photoLibrary
    @State private var isShowingSaveAlert = false
    @State private var isShowingShareSheet = false
    @State private var exportedImage: UIImage?

    var body: some View {
        VStack {
            // Toolbar
            toolbarView

            // Canvas
            DrawingImageViewRepresentable(viewModel: viewModel)
                .background(Color.white)
        }
        .padding()
        .backgroundModifier()
        .navigationTitle("Image Editor")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
                    viewModel.saveImage()
                    isShowingSaveAlert = true
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }

                Button {
                    if let image = viewModel.exportImage() {
                        exportedImage = image
                        isShowingShareSheet = true
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .confirmationDialog(
            "Add Image",
            isPresented: $viewModel.showImageSourceDialog,
            titleVisibility: .visible
        ) {
            Button("Camera") {
                imagePickerSource = .camera
                isShowingImagePicker = true
            }
            Button("Photo Library") {
                imagePickerSource = .photoLibrary
                isShowingImagePicker = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose a source for the image.")
        }
        .sheet(isPresented: $isShowingImagePicker) {
            ImagePicker(sourceType: imagePickerSource.uiSourceType, allowsEditing: true) { image in
                if let image {
                    viewModel.addOverlayImage(image)
                }
            }
        }
        .alert("Save Image", isPresented: $isShowingSaveAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.saveStatus ?? "No status")
        }
        .sheet(isPresented: $isShowingShareSheet) {
            if let exportedImage {
                ActivityView(activityItems: [exportedImage])
            }
        }
        .onChange(of: viewModel.textBoxFontSize) { _, _ in
            viewModel.applyTextStyleToSelected()
        }
        .onChange(of: viewModel.textBoxIsBold) { _, _ in
            viewModel.applyTextStyleToSelected()
        }
        .onChange(of: viewModel.textBoxTextColor) { _, _ in
            viewModel.applyTextStyleToSelected()
        }
        .onChange(of: viewModel.textBoxBackgroundColor) { _, _ in
            viewModel.applyTextStyleToSelected()
        }
        .onChange(of: viewModel.shapeStrokeColor) { _, _ in viewModel.applyShapeStyleToSelected() }
        .onChange(of: viewModel.shapeLineWidth) { _, _ in viewModel.applyShapeStyleToSelected() }
    }

    // MARK: - Toolbar

    private var toolbarView: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {

                    // MARK: Draw Section
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

                    toolbarDivider

                    // MARK: Text Section
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
                                        Button("Clear") { viewModel.textBoxBackgroundColor = UIColor.clear }
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

                    toolbarDivider

                    // MARK: Shape Section
                    imageShapeToolSection

                    toolbarDivider

                    // MARK: Select Section
                    imageSelectToolSection

                    toolbarDivider

                    // MARK: Image Section
                    VStack(spacing: 6) {
                        Text("Image")
                            .font(.caption2)
                            .tracking(0.5)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button {
                                viewModel.showImageSourceDialog = true
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
                            .buttonStyle(.plain)
                        }
                    }

                }//: HSTACK
            }//: SCROLL
        }//: VSTACK
        .contentBackgroundModifier()
    }

    // MARK: - Toolbar Helpers

    private var toolbarDivider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.25))
            .frame(width: 1, height: 36)
            .padding(.top, 14)
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

    private func toolbarSubtoolsRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 8) {
            content()
        }
    }

    private func iconName(for kind: OverlayShapeKind) -> String {
        switch kind {
        case .circle: return "circle"
        case .rectangle: return "rectangle"
        case .triangle: return "triangle"
        }
    }

    private func labelText(for kind: OverlayShapeKind) -> String {
        switch kind {
        case .circle: return "Circle"
        case .rectangle: return "Rect"
        case .triangle: return "Tri"
        }
    }

    // MARK: - Shape Tool Section

    @ViewBuilder private var imageShapeToolSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Shape")
                .font(.caption2).tracking(0.5).fontWeight(.semibold).foregroundStyle(.secondary)
            HStack(alignment: .center, spacing: 8) {
                Button { viewModel.setTool(.shape) } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "square.on.circle")
                            .symbolVariant(viewModel.activeTool == .shape ? .fill : .none)
                            .fontWeight(.semibold)
                        Text("Shape").fontWeight(.semibold)
                    }
                    .foregroundStyle(Color.accentColor)
                    .padding(6)
                    .background(viewModel.activeTool == .shape ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.1), in: .rect(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                if viewModel.isShapeMode {
                    imageShapeSubtoolsRow
                }
            }
            .animation(.linear(duration: 0.2), value: viewModel.isShapeMode)
        }
    }

    @ViewBuilder private var imageShapeSubtoolsRow: some View {
        toolbarSubtoolsRow {
            ForEach([OverlayShapeKind.circle, .rectangle, .triangle], id: \.self) { kind in
                Button { viewModel.activeShapeKind = kind } label: {
                    toolbarChip {
                        Image(systemName: iconName(for: kind)).fontWeight(.semibold)
                        Text(labelText(for: kind)).fontWeight(.semibold)
                    }
                    .foregroundStyle(Color.accentColor)
                    .padding(4)
                    .background(toolbarChipBackground(isActive: viewModel.activeShapeKind == kind))
                }
                .buttonStyle(.plain)
            }
            ColorPicker("", selection: Binding(
                get: { Color(viewModel.shapeStrokeColor) },
                set: { viewModel.shapeStrokeColor = UIColor($0) }
            ))
            .labelsHidden()
            .frame(width: toolbarChipSize.width, height: toolbarChipSize.height)
            Menu {
                Button("Thin (1pt)") { viewModel.shapeLineWidth = 1 }
                Button("Medium (2pt)") { viewModel.shapeLineWidth = 2 }
                Button("Thick (4pt)") { viewModel.shapeLineWidth = 4 }
                Button("Heavy (6pt)") { viewModel.shapeLineWidth = 6 }
            } label: {
                toolbarChip {
                    Image(systemName: "lineweight").fontWeight(.semibold)
                    Text("\(Int(viewModel.shapeLineWidth))pt").fontWeight(.semibold)
                }
                .foregroundStyle(Color.accentColor)
                .padding(4)
                .background(toolbarChipBackground())
            }
        }
    }

    // MARK: - Select Tool Section

    @ViewBuilder private var imageSelectToolSection: some View {
        VStack(spacing: 6) {
            Text("Select")
                .font(.caption2)
                .tracking(0.5)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            HStack(alignment: .center, spacing: 8) {
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

                if viewModel.activeTool == .select && viewModel.selectedOverlayKind == .textBox {
                    imageSelectTextBoxSubtools
                }

                if viewModel.activeTool == .select && viewModel.selectedOverlayKind == .shape {
                    imageSelectShapeSubtools
                }

                if viewModel.hasSelectedOverlayObject {
                    Button {
                        viewModel.deleteSelectedObject()
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
            .animation(.linear(duration: 0.2), value: viewModel.selectedOverlayKind)
        }
    }

    @ViewBuilder private var imageSelectTextBoxSubtools: some View {
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
                        .font(.title3).fontWeight(.semibold)
                        .foregroundStyle(Color(viewModel.textBoxTextColor))
                    Text("Text").fontWeight(.semibold)
                }
                .foregroundStyle(Color.accentColor).padding(4).background(toolbarChipBackground())
            }
            Menu {
                Button("Yellow") { viewModel.textBoxBackgroundColor = UIColor.systemYellow }
                Button("Blue") { viewModel.textBoxBackgroundColor = UIColor.systemBlue }
                Button("Green") { viewModel.textBoxBackgroundColor = UIColor.systemGreen }
                Button("Pink") { viewModel.textBoxBackgroundColor = UIColor.systemPink }
                Button("Clear") { viewModel.textBoxBackgroundColor = UIColor.clear }
            } label: {
                toolbarChip {
                    Image(systemName: "square.fill")
                        .font(.title3).fontWeight(.semibold)
                        .foregroundStyle(Color(viewModel.textBoxBackgroundColor))
                    Text("BG").fontWeight(.semibold)
                }
                .foregroundStyle(Color.accentColor).padding(4).background(toolbarChipBackground())
            }
            Menu {
                Button("Small (12pt)") { viewModel.textBoxFontSize = 12 }
                Button("Medium (14pt)") { viewModel.textBoxFontSize = 14 }
                Button("Large (18pt)") { viewModel.textBoxFontSize = 18 }
                Button("XL (22pt)") { viewModel.textBoxFontSize = 22 }
            } label: {
                toolbarChip {
                    Image(systemName: "textformat.size").font(.title3).fontWeight(.semibold)
                    Text("\(Int(viewModel.textBoxFontSize))pt").fontWeight(.semibold)
                }
                .foregroundStyle(Color.accentColor).padding(4).background(toolbarChipBackground())
            }
            Button { viewModel.textBoxIsBold.toggle() } label: {
                toolbarChip {
                    Image(systemName: "bold").font(.title3).fontWeight(.semibold)
                    Text("Bold").fontWeight(.semibold)
                }
                .foregroundStyle(Color.accentColor).padding(4).background(toolbarChipBackground(isActive: viewModel.textBoxIsBold))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder private var imageSelectShapeSubtools: some View {
        toolbarSubtoolsRow {
            ColorPicker("", selection: Binding(
                get: { Color(viewModel.shapeStrokeColor) },
                set: { viewModel.shapeStrokeColor = UIColor($0) }
            ))
            .labelsHidden()
            .frame(width: toolbarChipSize.width, height: toolbarChipSize.height)
            Menu {
                Button("Thin (1pt)") { viewModel.shapeLineWidth = 1 }
                Button("Medium (2pt)") { viewModel.shapeLineWidth = 2 }
                Button("Thick (4pt)") { viewModel.shapeLineWidth = 4 }
                Button("Heavy (6pt)") { viewModel.shapeLineWidth = 6 }
            } label: {
                toolbarChip {
                    Image(systemName: "lineweight").fontWeight(.semibold)
                    Text("\(Int(viewModel.shapeLineWidth))pt").fontWeight(.semibold)
                }
                .foregroundStyle(Color.accentColor).padding(4).background(toolbarChipBackground())
            }
        }
    }
}

// MARK: - Drawing Image View Representable

struct DrawingImageViewRepresentable: UIViewRepresentable {
    @Bindable var viewModel: ImageEditorViewModel

    func makeUIView(context: Context) -> DrawingImageView {
        let view = DrawingImageView()
        view.viewModel = viewModel
        viewModel.canvasView = view
        view.setSourceImage(viewModel.sourceImage)
        return view
    }

    func updateUIView(_ view: DrawingImageView, context: Context) {
        view.isDrawingMode = viewModel.isDrawingMode
        view.isTextMode = viewModel.isTextMode
        view.isSelectMode = viewModel.isSelectMode
        view.currentInkColor = viewModel.inkColor
        view.currentLineWidth = viewModel.inkLineWidth
        view.isEraserMode = viewModel.isEraserMode
        view.eraserRadius = viewModel.eraserRadius
        view.textBoxBackgroundColor = viewModel.textBoxBackgroundColor
        view.textBoxFontSize = viewModel.textBoxFontSize
        view.textBoxIsBold = viewModel.textBoxIsBold
        view.textBoxTextColor = viewModel.textBoxTextColor
        view.isShapeMode = viewModel.activeTool == .shape
        view.currentShapeKind = viewModel.activeShapeKind
        view.shapeStrokeColor = viewModel.shapeStrokeColor
        view.shapeLineWidth = viewModel.shapeLineWidth
    }
}

// MARK: - View Model

@MainActor
@Observable
class ImageEditorViewModel {
    let sourceImage: UIImage
    var activeTool: EditorTool = .draw
    var inkColor: UIColor = .systemBlue
    var inkLineWidth: CGFloat = 3.0
    var isEraserMode: Bool = false
    var eraserRadius: CGFloat = 9
    var textBoxBackgroundColor: UIColor = .systemYellow
    var textBoxFontSize: CGFloat = 14
    var textBoxIsBold: Bool = false
    var textBoxTextColor: UIColor = .label
    var hasSelectedOverlayObject: Bool = false
    var showImageSourceDialog: Bool = false
    var saveStatus: String?
    var undoStack: [ImageUndoAction] = []
    var redoStack: [ImageUndoAction] = []
    weak var canvasView: DrawingImageView?
    private let onSave: ((UIImage) -> Void)?
    private let onExport: ((UIImage) -> Void)?
    private let maxUndoActions = 50

    var activeShapeKind: OverlayShapeKind = .rectangle
    var shapeStrokeColor: UIColor = .systemRed
    var shapeLineWidth: CGFloat = 2.0
    var selectedOverlayKind: SelectedOverlayKind?

    var isDrawingMode: Bool { activeTool == .draw }
    var isTextMode: Bool { activeTool == .text }
    var isSelectMode: Bool { activeTool == .select }
    var isShapeMode: Bool { activeTool == .shape }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    init(sourceImage: UIImage, onSave: ((UIImage) -> Void)? = nil, onExport: ((UIImage) -> Void)? = nil) {
        self.sourceImage = sourceImage
        self.onSave = onSave
        self.onExport = onExport
    }

    func setTool(_ tool: EditorTool) {
        if tool == .shape {
            activeTool = .shape
            canvasView?.endTextEditing()
            canvasView?.deselectAll()
            isEraserMode = false
            return
        }
        if activeTool == tool, tool != .select {
            activeTool = .select
            canvasView?.endTextEditing()
            isEraserMode = false
            return
        }
        if tool != .text {
            canvasView?.endTextEditing()
        }
        activeTool = tool
        if tool != .draw {
            isEraserMode = false
        }
        if tool != .select {
            canvasView?.deselectAll()
        }
    }

    func applyShapeStyleToSelected() {
        canvasView?.applyShapeStyleToSelected(strokeColor: shapeStrokeColor, lineWidth: shapeLineWidth)
    }

    func addOverlayImage(_ image: UIImage) {
        canvasView?.addOverlayImage(image)
    }

    func deleteSelectedObject() {
        canvasView?.deleteSelected()
    }

    func applyTextStyleToSelected() {
        canvasView?.applyTextStyle(
            fontSize: textBoxFontSize,
            isBold: textBoxIsBold,
            textColor: textBoxTextColor,
            backgroundColor: textBoxBackgroundColor
        )
    }

    func saveImage() {
        guard let image = canvasView?.renderToImage() else {
            saveStatus = "Failed to render image"
            return
        }

        if let onSave {
            onSave(image)
            saveStatus = "Image saved"
            return
        }

        // Default: save as JPEG to Documents/ImageEdits/
        guard let data = image.jpegData(compressionQuality: 0.92) else {
            saveStatus = "Failed to encode image"
            return
        }

        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = documents.appendingPathComponent("ImageEdits", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let fileName = "Image-\(Int(Date().timeIntervalSince1970)).jpg"
            let destination = folder.appendingPathComponent(fileName)
            try data.write(to: destination)
            saveStatus = "Saved to: \(fileName)"
        } catch {
            saveStatus = "Failed to save image"
        }
    }

    @discardableResult
    func exportImage() -> UIImage? {
        guard let image = canvasView?.renderToImage() else { return nil }
        onExport?(image)
        return image
    }

    func didMakeChange(_ action: ImageUndoAction) {
        let resolved = resolveActionIfNeeded(action)
        undoStack.append(resolved)
        if undoStack.count > maxUndoActions {
            undoStack.removeFirst(undoStack.count - maxUndoActions)
        }
        redoStack.removeAll()
    }

    func undo() {
        guard let action = undoStack.popLast() else { return }
        let resolved = resolveActionIfNeeded(action)
        redoStack.append(resolved)
        performUndo(resolved)
    }

    func redo() {
        guard let action = redoStack.popLast() else { return }
        undoStack.append(action)
        performRedo(action)
    }

    private func resolveActionIfNeeded(_ action: ImageUndoAction) -> ImageUndoAction {
        switch action {
        case .textBox(let add, let remove):
            if let add, let current = canvasView?.textBoxState(id: add.id) {
                return .textBox(add: current, remove: remove)
            }
            return action
        case .imageBox(let add, let remove):
            if let add, let current = canvasView?.imageBoxState(id: add.id) {
                return .imageBox(add: current, remove: remove)
            }
            return action
        case .imageShape(let add, let remove):
            if let add, let current = canvasView?.shapeBoxState(id: add.id) {
                return .imageShape(add: current, remove: remove)
            }
            return action
        default:
            return action
        }
    }

    private func performUndo(_ action: ImageUndoAction) {
        switch action {
        case .stroke(let add, let remove):
            if let add {
                canvasView?.removeStroke(id: add.id)
            }
            if let remove {
                canvasView?.addStroke(remove)
            }
        case .eraseSession(let old, let new):
            canvasView?.replaceStrokes(remove: new, add: old)
        case .textBox(let add, let remove):
            if let add {
                canvasView?.removeTextBox(id: add.id)
            }
            if let remove {
                canvasView?.addTextBox(from: remove, beginEditing: false)
            }
        case .imageBox(let add, let remove):
            if let add {
                canvasView?.removeImageBox(id: add.id)
            }
            if let remove {
                canvasView?.addImageBox(from: remove)
            }
        case .imageBoxUpdate(let before, _):
            canvasView?.updateImageBox(from: before)
        case .imageShape(let add, let remove):
            if let add { canvasView?.removeShapeBox(id: add.id) }
            if let remove { canvasView?.addShapeBox(from: remove) }
        case .imageShapeUpdate(let before, _):
            canvasView?.updateShapeBox(from: before)
        }
    }

    private func performRedo(_ action: ImageUndoAction) {
        switch action {
        case .stroke(let add, let remove):
            if let add {
                canvasView?.addStroke(add)
            }
            if let remove {
                canvasView?.removeStroke(id: remove.id)
            }
        case .eraseSession(let old, let new):
            canvasView?.replaceStrokes(remove: old, add: new)
        case .textBox(let add, let remove):
            if let add {
                canvasView?.addTextBox(from: add, beginEditing: false)
            }
            if let remove {
                canvasView?.removeTextBox(id: remove.id)
            }
        case .imageBox(let add, let remove):
            if let add {
                canvasView?.addImageBox(from: add)
            }
            if let remove {
                canvasView?.removeImageBox(id: remove.id)
            }
        case .imageBoxUpdate(_, let after):
            canvasView?.updateImageBox(from: after)
        case .imageShape(let add, let remove):
            if let add { canvasView?.addShapeBox(from: add) }
            if let remove { canvasView?.removeShapeBox(id: remove.id) }
        case .imageShapeUpdate(_, let after):
            canvasView?.updateShapeBox(from: after)
        }
    }
}

// MARK: - ImageUndoAction

enum ImageUndoAction {
    case stroke(add: InkStroke?, remove: InkStroke?)
    case eraseSession(old: [InkStroke], new: [InkStroke])
    case textBox(add: OverlayTextBoxState?, remove: OverlayTextBoxState?)
    case imageBox(add: OverlayImageState?, remove: OverlayImageState?)
    case imageBoxUpdate(before: OverlayImageState, after: OverlayImageState)
    case imageShape(add: OverlayShapeState?, remove: OverlayShapeState?)
    case imageShapeUpdate(before: OverlayShapeState, after: OverlayShapeState)
}

// MARK: - InkStroke

struct InkStroke: Identifiable {
    let id: UUID
    var points: [CGPoint]
    var color: UIColor
    var lineWidth: CGFloat

    init(id: UUID = UUID(), points: [CGPoint], color: UIColor, lineWidth: CGFloat) {
        self.id = id
        self.points = points
        self.color = color
        self.lineWidth = lineWidth
    }
}

// MARK: - InkCanvasView

final class InkCanvasView: UIView {
    var strokes: [InkStroke] = []
    var liveStroke: InkStroke?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isOpaque = false
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let allStrokes = strokes + (liveStroke.map { [$0] } ?? [])
        for stroke in allStrokes {
            guard stroke.points.count >= 2 else {
                // Draw a dot for single-point strokes
                if let point = stroke.points.first {
                    context.setFillColor(stroke.color.cgColor)
                    let dotRadius = stroke.lineWidth / 2
                    context.fillEllipse(in: CGRect(
                        x: point.x - dotRadius,
                        y: point.y - dotRadius,
                        width: stroke.lineWidth,
                        height: stroke.lineWidth
                    ))
                }
                continue
            }
            stroke.color.setStroke()
            context.setLineWidth(stroke.lineWidth)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.beginPath()
            context.move(to: stroke.points[0])
            for point in stroke.points.dropFirst() {
                context.addLine(to: point)
            }
            context.strokePath()
        }
    }
}

// MARK: - DrawingImageView

class DrawingImageView: UIView, PencilDrawingGestureDelegate {

    // MARK: - Subviews
    private let imageView = UIImageView()
    private let inkCanvas = InkCanvasView()
    private let overlayView = UIView()
    private let eraserLayer = CAShapeLayer()
    private let textBoxPreviewLayer = CAShapeLayer()
    private let imageBorderLayer = CAShapeLayer()
    private let inkCanvasMask = CALayer()
    private let overlayViewMask = CALayer()

    // MARK: - Properties
    weak var viewModel: ImageEditorViewModel? {
        didSet {
            imageView.image = viewModel?.sourceImage
        }
    }

    var isDrawingMode = false {
        didSet {
            pencilGesture?.isEnabled = isDrawingMode
            fingerPanGesture?.isEnabled = isDrawingMode
            fingerPinchGesture?.isEnabled = isDrawingMode
            if !isDrawingMode {
                hideEraserCircle()
            }
        }
    }

    var isTextMode = false {
        didSet {
            textBoxPanGesture?.isEnabled = isTextMode
            if !isTextMode {
                textBoxPreviewLayer.isHidden = true
            }
        }
    }

    var isSelectMode = false {
        didSet {
            guard oldValue != isSelectMode else { return }
            textBoxViews.values.forEach { $0.setSelectMode(isSelectMode) }
            imageBoxViews.values.forEach { $0.setSelectMode(isSelectMode) }
            shapeBoxViews.values.forEach { $0.setSelectMode(isSelectMode) }
            if !isSelectMode {
                deselectAll()
            }
        }
    }

    var currentInkColor: UIColor = .systemBlue
    var currentLineWidth: CGFloat = 3.0
    var isEraserMode: Bool = false
    var eraserRadius: CGFloat = 9 {
        didSet { updateEraserCircle() }
    }
    var textBoxBackgroundColor: UIColor = .systemYellow
    var textBoxFontSize: CGFloat = 14
    var textBoxIsBold: Bool = false
    var textBoxTextColor: UIColor = .label

    private(set) var strokes: [InkStroke] = []
    private var currentStrokePoints: [CGPoint] = []
    private var eraserAffectedStrokes: [UUID: (old: InkStroke, new: InkStroke?)] = [:]
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
        }
    }

    private var pencilGesture: PencilDrawingGestureRecognizer?
    private var fingerPanGesture: UIPanGestureRecognizer?
    private var fingerPinchGesture: UIPinchGestureRecognizer?
    private var textBoxPanGesture: UIPanGestureRecognizer?
    private var textBoxStartPoint: CGPoint?
    private var eraserLocation: CGPoint?

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    // MARK: - Setup

    private func setup() {
        backgroundColor = .white

        // 1. Image view
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .white
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(imageView)

        // 2. Ink canvas
        inkCanvas.backgroundColor = .clear
        inkCanvas.isUserInteractionEnabled = false
        inkCanvas.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(inkCanvas)

        // 3. Overlay view
        overlayView.backgroundColor = .clear
        overlayView.isUserInteractionEnabled = true
        overlayView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(overlayView)

        // 4. Eraser layer
        eraserLayer.strokeColor = UIColor.systemBlue.withAlphaComponent(0.8).cgColor
        eraserLayer.fillColor = UIColor.systemBlue.withAlphaComponent(0.08).cgColor
        eraserLayer.lineWidth = 1.5
        eraserLayer.isHidden = true
        layer.addSublayer(eraserLayer)

        // 5. Text box preview layer
        textBoxPreviewLayer.strokeColor = UIColor.systemBlue.withAlphaComponent(0.8).cgColor
        textBoxPreviewLayer.fillColor = UIColor.clear.cgColor
        textBoxPreviewLayer.lineWidth = 1.5
        textBoxPreviewLayer.lineDashPattern = [6, 4]
        textBoxPreviewLayer.isHidden = true
        layer.addSublayer(textBoxPreviewLayer)

        // 6. Image boundary guide — subtle dashed border showing the editable area
        imageBorderLayer.fillColor = UIColor.clear.cgColor
        imageBorderLayer.strokeColor = UIColor.systemBlue.withAlphaComponent(0.25).cgColor
        imageBorderLayer.lineWidth = 1
        imageBorderLayer.lineDashPattern = [5, 4]
        layer.addSublayer(imageBorderLayer)

        // 7. Mask layers — clip ink and overlays to the image content rect
        inkCanvasMask.backgroundColor = UIColor.black.cgColor
        inkCanvas.layer.mask = inkCanvasMask
        overlayViewMask.backgroundColor = UIColor.black.cgColor
        overlayView.layer.mask = overlayViewMask

        setupGestures()
        setupShapePreviewLayer()
        setupShapePanGesture()
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
        pan.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue),
            NSNumber(value: UITouch.TouchType.pencil.rawValue)
        ]
        pan.delegate = self
        pan.isEnabled = false
        addGestureRecognizer(pan)
        shapePanGesture = pan
    }

    private func setupGestures() {
        // Pencil drawing gesture
        let pencil = PencilDrawingGestureRecognizer(target: nil, action: nil)
        pencil.drawingDelegate = self
        pencil.cancelsTouchesInView = true
        pencil.delaysTouchesBegan = true
        pencil.isEnabled = false
        pencil.delegate = self
        addGestureRecognizer(pencil)
        pencilGesture = pencil

        // Finger 2-touch pan (no-op scroll pass-through)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleFingerPan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        pan.delegate = self
        pan.isEnabled = false
        addGestureRecognizer(pan)
        fingerPanGesture = pan

        // Finger pinch (no-op)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handleFingerPinch(_:)))
        pinch.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        pinch.delegate = self
        pinch.isEnabled = false
        addGestureRecognizer(pinch)
        fingerPinchGesture = pinch

        // Text box pan gesture
        let textPan = UIPanGestureRecognizer(target: self, action: #selector(handleTextBoxPan(_:)))
        textPan.cancelsTouchesInView = true
        textPan.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue),
            NSNumber(value: UITouch.TouchType.pencil.rawValue)
        ]
        textPan.delegate = self
        textPan.isEnabled = false
        addGestureRecognizer(textPan)
        textBoxPanGesture = textPan
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
        inkCanvas.frame = bounds
        overlayView.frame = bounds

        // Keep mask layers and border aligned to the actual image content rect
        let imgRect = imageContentRect
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        inkCanvasMask.frame = imgRect
        overlayViewMask.frame = imgRect
        imageBorderLayer.path = UIBezierPath(rect: imgRect).cgPath
        imageBorderLayer.frame = bounds
        CATransaction.commit()

        inkCanvas.strokes = strokes
        inkCanvas.setNeedsDisplay()
    }

    // MARK: - Image Content Rect

    /// The rect (in self's coordinate space) that the source image actually occupies,
    /// accounting for aspect-fit letterboxing.
    var imageContentRect: CGRect {
        guard let image = imageView.image,
              image.size.width > 0, image.size.height > 0,
              bounds.width > 0, bounds.height > 0 else {
            return bounds
        }
        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let w = image.size.width * scale
        let h = image.size.height * scale
        return CGRect(
            x: (bounds.width - w) / 2,
            y: (bounds.height - h) / 2,
            width: w,
            height: h
        )
    }

    // MARK: - Source Image

    func setSourceImage(_ image: UIImage) {
        imageView.image = image
    }

    // MARK: - Finger Gesture Handlers (no-op)

    @objc private func handleFingerPan(_ gesture: UIPanGestureRecognizer) {
        // no-op: finger pan is enabled to allow 2-finger scroll pass-through but
        // the image editor view is not scrollable; gesture is consumed silently.
    }

    @objc private func handleFingerPinch(_ gesture: UIPinchGestureRecognizer) {
        // no-op
    }

    // MARK: - PencilDrawingGestureDelegate

    func pencilTouchBegan(_ touch: UITouch, with event: UIEvent?) {
        guard isDrawingMode else { return }
        let point = touch.location(in: self)
        guard imageContentRect.contains(point) else { return }
        if isEraserMode {
            eraserAffectedStrokes.removeAll()
            showEraserCircle(at: point)
            eraseAt(point)
        } else {
            currentStrokePoints = [point]
            showLiveStroke()
        }
    }

    func pencilTouchMoved(_ touch: UITouch, with event: UIEvent?) {
        guard isDrawingMode else { return }
        let coalescedTouches = event?.coalescedTouches(for: touch) ?? [touch]
        for coalescedTouch in coalescedTouches {
            let point = coalescedTouch.location(in: self)
            if isEraserMode {
                showEraserCircle(at: point)
                eraseAt(point)
            } else {
                currentStrokePoints.append(point)
            }
        }
        if !isEraserMode {
            showLiveStroke()
        }
    }

    func pencilTouchEnded(_ touch: UITouch, with event: UIEvent?) {
        guard isDrawingMode else { return }
        if isEraserMode {
            let point = touch.location(in: self)
            eraseAt(point)
            commitErase()
            hideEraserCircle()
        } else {
            let point = touch.location(in: self)
            currentStrokePoints.append(point)
            commitStroke()
        }
    }

    func pencilTouchCancelled(with event: UIEvent?) {
        guard isDrawingMode else { return }
        if isEraserMode {
            commitErase()
            hideEraserCircle()
        } else {
            commitStroke()
        }
    }

    // MARK: - Stroke Rendering

    private func showLiveStroke() {
        guard !currentStrokePoints.isEmpty else { return }
        inkCanvas.liveStroke = InkStroke(
            points: currentStrokePoints,
            color: currentInkColor,
            lineWidth: currentLineWidth
        )
        inkCanvas.setNeedsDisplay()
    }

    private func commitStroke() {
        guard currentStrokePoints.count >= 2 else {
            currentStrokePoints = []
            inkCanvas.liveStroke = nil
            inkCanvas.setNeedsDisplay()
            return
        }
        let stroke = InkStroke(
            points: currentStrokePoints,
            color: currentInkColor,
            lineWidth: currentLineWidth
        )
        strokes.append(stroke)
        inkCanvas.liveStroke = nil
        inkCanvas.strokes = strokes
        inkCanvas.setNeedsDisplay()
        currentStrokePoints = []
        viewModel?.didMakeChange(.stroke(add: stroke, remove: nil))
    }

    // MARK: - Eraser

    private func eraseAt(_ point: CGPoint) {
        var newStrokes: [InkStroke] = []
        for stroke in strokes {
            var segments: [[CGPoint]] = []
            var current: [CGPoint] = []
            var didErase = false

            for p in stroke.points {
                if hypot(p.x - point.x, p.y - point.y) <= eraserRadius {
                    didErase = true
                    if current.count >= 2 {
                        segments.append(current)
                    }
                    current = []
                } else {
                    current.append(p)
                }
            }
            if current.count >= 2 {
                segments.append(current)
            }

            if didErase {
                // Track original for undo
                if eraserAffectedStrokes[stroke.id] == nil {
                    eraserAffectedStrokes[stroke.id] = (old: stroke, new: nil)
                }
                // Replace with split segments (each becomes a new stroke with a new id)
                for segmentPoints in segments {
                    let newStroke = InkStroke(
                        points: segmentPoints,
                        color: stroke.color,
                        lineWidth: stroke.lineWidth
                    )
                    newStrokes.append(newStroke)
                }
            } else {
                newStrokes.append(stroke)
            }
        }
        strokes = newStrokes
        inkCanvas.strokes = strokes
        inkCanvas.setNeedsDisplay()
    }

    private func commitErase() {
        guard !eraserAffectedStrokes.isEmpty else { return }
        let old = eraserAffectedStrokes.values.map { $0.old }
        let new = strokes
        viewModel?.didMakeChange(.eraseSession(old: old, new: new))
        eraserAffectedStrokes.removeAll()
    }

    // MARK: - Public Stroke Mutation (for undo/redo)

    func addStroke(_ stroke: InkStroke) {
        strokes.append(stroke)
        inkCanvas.strokes = strokes
        inkCanvas.setNeedsDisplay()
    }

    func removeStroke(id: UUID) {
        strokes.removeAll { $0.id == id }
        inkCanvas.strokes = strokes
        inkCanvas.setNeedsDisplay()
    }

    func replaceStrokes(remove: [InkStroke], add: [InkStroke]) {
        let removeIDs = Set(remove.map { $0.id })
        strokes = strokes.filter { !removeIDs.contains($0.id) }
        strokes.append(contentsOf: add)
        inkCanvas.strokes = strokes
        inkCanvas.setNeedsDisplay()
    }

    // MARK: - Text Box Pan

    @objc private func handleTextBoxPan(_ gesture: UIPanGestureRecognizer) {
        guard isTextMode else { return }
        let point = gesture.location(in: self)

        switch gesture.state {
        case .began:
            textBoxStartPoint = point
            updateTextBoxPreview(from: point, to: point)
            textBoxPreviewLayer.isHidden = false
        case .changed:
            guard let start = textBoxStartPoint else { return }
            updateTextBoxPreview(from: start, to: point)
        case .ended, .cancelled:
            guard let start = textBoxStartPoint else { return }
            textBoxPreviewLayer.isHidden = true
            textBoxStartPoint = nil
            let rect = rectFrom(start, to: point).insetBy(dx: -2, dy: -2)
            if rect.width >= 20, rect.height >= 20 {
                createTextBox(in: rect)
            }
        default:
            break
        }
    }

    private func updateTextBoxPreview(from start: CGPoint, to end: CGPoint) {
        let rect = rectFrom(start, to: end)
        textBoxPreviewLayer.path = UIBezierPath(rect: rect).cgPath
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
                createShapeBox(with: rectInView)
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

    private func createShapeBox(with rectInView: CGRect) {
        let normalised = CGRect(
            origin: rectInView.origin,
            size: CGSize(width: max(rectInView.width, 30), height: max(rectInView.height, 30))
        )
        let state = OverlayShapeState(
            id: UUID(),
            frame: normalised,
            kind: currentShapeKind,
            strokeColor: shapeStrokeColor,
            lineWidth: shapeLineWidth
        )
        addShapeBox(from: state)
        viewModel?.didMakeChange(.imageShape(add: state, remove: nil))
    }

    // MARK: - Shape Box Overlay Methods

    func addShapeBox(from state: OverlayShapeState) {
        let box = ShapeBoxView(id: state.id, kind: state.kind, strokeColor: state.strokeColor, lineWidth: state.lineWidth)
        box.frame = state.frame
        box.setSelectMode(isSelectMode)
        box.onSelect = { [weak self] id in self?.selectShapeBox(id: id) }
        box.onEndChange = { [weak self] before, after in
            guard before.frame != after.frame else { return }
            self?.viewModel?.didMakeChange(.imageShapeUpdate(before: before, after: after))
        }
        overlayView.addSubview(box)
        shapeBoxViews[state.id] = box
    }

    func removeShapeBox(id: UUID) {
        shapeBoxViews[id]?.removeFromSuperview()
        shapeBoxViews[id] = nil
        if selectedShapeID == id {
            selectedShapeID = nil
            syncSelection()
        }
    }

    func shapeBoxState(id: UUID) -> OverlayShapeState? {
        guard let box = shapeBoxViews[id] else { return nil }
        return OverlayShapeState(id: id, frame: box.frame, kind: box.shapeKind, strokeColor: box.strokeColor, lineWidth: box.lineWidth)
    }

    func updateShapeBox(from state: OverlayShapeState) {
        guard let box = shapeBoxViews[state.id] else { return }
        box.frame = state.frame
        box.applyStyle(strokeColor: state.strokeColor, lineWidth: state.lineWidth)
    }

    func applyShapeStyleToSelected(strokeColor: UIColor, lineWidth: CGFloat) {
        guard let id = selectedShapeID, let box = shapeBoxViews[id] else { return }
        let before = OverlayShapeState(id: id, frame: box.frame, kind: box.shapeKind, strokeColor: box.strokeColor, lineWidth: box.lineWidth)
        box.applyStyle(strokeColor: strokeColor, lineWidth: lineWidth)
        let after = OverlayShapeState(id: id, frame: box.frame, kind: box.shapeKind, strokeColor: strokeColor, lineWidth: lineWidth)
        if before.strokeColor != after.strokeColor || before.lineWidth != after.lineWidth {
            viewModel?.didMakeChange(.imageShapeUpdate(before: before, after: after))
        }
    }

    private func selectShapeBox(id: UUID) {
        selectedShapeID = id
        selectedTextBoxID = nil
        selectedImageBoxID = nil
        viewModel?.selectedOverlayKind = .shape
        if let box = shapeBoxViews[id] {
            viewModel?.shapeStrokeColor = box.strokeColor
            viewModel?.shapeLineWidth = box.lineWidth
        }
        updateSelectionUI()
        if let box = shapeBoxViews[id] {
            overlayView.bringSubviewToFront(box)
        }
    }

    private func rectFrom(_ start: CGPoint, to end: CGPoint) -> CGRect {
        let origin = CGPoint(x: min(start.x, end.x), y: min(start.y, end.y))
        let size = CGSize(width: abs(end.x - start.x), height: abs(end.y - start.y))
        return CGRect(origin: origin, size: size)
    }

    private func createTextBox(in rect: CGRect) {
        let normalizedRect = CGRect(
            x: rect.origin.x,
            y: rect.origin.y,
            width: max(rect.width, 80),
            height: max(rect.height, 40)
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
        addTextBox(from: state, beginEditing: true)
        viewModel?.didMakeChange(.textBox(add: state, remove: nil))
    }

    // MARK: - Overlay Text Box Methods

    func addTextBox(from state: OverlayTextBoxState, beginEditing: Bool = false) {
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
        overlayView.addSubview(box)
        overlayView.bringSubviewToFront(box)
        textBoxViews[state.id] = box
        if beginEditing {
            box.beginEditing()
        }
    }

    func removeTextBox(id: UUID) {
        if let box = textBoxViews[id] {
            box.removeFromSuperview()
            textBoxViews[id] = nil
        }
        if selectedTextBoxID == id {
            selectedTextBoxID = nil
            syncSelection()
        }
    }

    func textBoxState(id: UUID) -> OverlayTextBoxState? {
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

    func endTextEditing() {
        textBoxViews.values.forEach { $0.endEditingIfNeeded() }
        overlayView.endEditing(true)
    }

    func applyTextStyle(fontSize: CGFloat, isBold: Bool, textColor: UIColor, backgroundColor: UIColor) {
        guard let selectedTextBoxID,
              let box = textBoxViews[selectedTextBoxID] else { return }
        box.applyTextStyle(fontSize: fontSize, isBold: isBold, textColor: textColor)
        box.setBackground(backgroundColor)
    }

    // MARK: - Overlay Image Box Methods

    func addOverlayImage(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        let targetWidth: CGFloat = 220
        let aspect = image.size.height > 0 ? image.size.width / image.size.height : 1.0
        let width = targetWidth
        let height = max(120, targetWidth / max(aspect, 0.1))
        let size = CGSize(width: width, height: height)
        // Centre within the image content area, not the full view
        let imgRect = imageContentRect
        let origin = CGPoint(
            x: imgRect.midX - size.width / 2,
            y: imgRect.midY - size.height / 2
        )
        let frame = CGRect(origin: origin, size: size)
        let state = OverlayImageState(id: UUID(), frame: frame, imageData: data)
        addImageBox(from: state)
        viewModel?.didMakeChange(.imageBox(add: state, remove: nil))
    }

    func addImageBox(from state: OverlayImageState) {
        let box = ImageBoxView(id: state.id, imageData: state.imageData)
        box.frame = state.frame
        box.setSelectMode(isSelectMode)
        box.onSelect = { [weak self] id in
            self?.selectImageBox(id: id)
        }
        box.onEndChange = { [weak self] before, after in
            guard before.frame != after.frame else { return }
            self?.viewModel?.didMakeChange(.imageBoxUpdate(before: before, after: after))
        }
        overlayView.addSubview(box)
        imageBoxViews[state.id] = box
    }

    func removeImageBox(id: UUID) {
        if let box = imageBoxViews[id] {
            box.removeFromSuperview()
            imageBoxViews[id] = nil
        }
        if selectedImageBoxID == id {
            selectedImageBoxID = nil
            syncSelection()
        }
    }

    func imageBoxState(id: UUID) -> OverlayImageState? {
        guard let box = imageBoxViews[id] else { return nil }
        return OverlayImageState(id: id, frame: box.frame, imageData: box.imageData)
    }

    func updateImageBox(from state: OverlayImageState) {
        guard let box = imageBoxViews[state.id] else { return }
        box.frame = state.frame
        box.setImageData(state.imageData)
    }

    // MARK: - Selection

    func selectTextBox(id: UUID) {
        selectedTextBoxID = id
        selectedImageBoxID = nil
        selectedShapeID = nil
        viewModel?.selectedOverlayKind = .textBox
        updateSelectionUI()
        if let box = textBoxViews[id] {
            overlayView.bringSubviewToFront(box)
        }
    }

    func selectImageBox(id: UUID) {
        selectedImageBoxID = id
        selectedTextBoxID = nil
        selectedShapeID = nil
        viewModel?.selectedOverlayKind = .image
        updateSelectionUI()
        if let box = imageBoxViews[id] {
            overlayView.bringSubviewToFront(box)
        }
    }

    func deselectAll() {
        selectedTextBoxID = nil
        selectedImageBoxID = nil
        selectedShapeID = nil
        viewModel?.selectedOverlayKind = nil
        updateSelectionUI()
    }

    func deleteSelected() {
        if let selectedTextBoxID, let state = textBoxState(id: selectedTextBoxID) {
            removeTextBox(id: selectedTextBoxID)
            viewModel?.didMakeChange(.textBox(add: nil, remove: state))
            return
        }
        if let selectedImageBoxID, let state = imageBoxState(id: selectedImageBoxID) {
            removeImageBox(id: selectedImageBoxID)
            viewModel?.didMakeChange(.imageBox(add: nil, remove: state))
            return
        }
        if let selectedShapeID, let state = shapeBoxState(id: selectedShapeID) {
            removeShapeBox(id: selectedShapeID)
            viewModel?.didMakeChange(.imageShape(add: nil, remove: state))
        }
    }

    private func updateSelectionUI() {
        for (id, box) in textBoxViews {
            box.setSelected(id == selectedTextBoxID)
        }
        for (id, box) in imageBoxViews {
            box.setSelected(id == selectedImageBoxID)
        }
        for (id, box) in shapeBoxViews {
            box.setSelected(id == selectedShapeID)
        }
        syncSelection()
    }

    private func syncSelection() {
        viewModel?.hasSelectedOverlayObject = (selectedTextBoxID != nil || selectedImageBoxID != nil || selectedShapeID != nil)
    }

    // MARK: - Eraser Visual

    private func showEraserCircle(at point: CGPoint) {
        eraserLocation = point
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

    // MARK: - Export

    func renderToImage() -> UIImage {
        // Force-hide handles with no implicit CA animations.
        // setSelectMode(false) sets alpha = 0 on move/resize handles immediately,
        // regardless of current selection state, which drawHierarchy would otherwise
        // still capture via the presentation layer.
        UIView.performWithoutAnimation {
            textBoxViews.values.forEach { $0.setSelectMode(false) }
            imageBoxViews.values.forEach { $0.setSelectMode(false) }
            shapeBoxViews.values.forEach { $0.setSelectMode(false) }
            endTextEditing()
        }

        let imgRect = imageContentRect
        guard imgRect.width > 0, imgRect.height > 0 else {
            restoreSelectMode()
            return UIImage()
        }

        // afterScreenUpdates: true ensures the presentation layer reflects the
        // alpha = 0 changes we just made before the snapshot is taken.
        let renderer = UIGraphicsImageRenderer(size: imgRect.size)
        let result = renderer.image { ctx in
            ctx.cgContext.translateBy(x: -imgRect.origin.x, y: -imgRect.origin.y)
            drawHierarchy(in: bounds, afterScreenUpdates: true)
        }

        restoreSelectMode()
        return result
    }

    private func restoreSelectMode() {
        // Restore the current select-mode state on all overlay boxes after export.
        textBoxViews.values.forEach { $0.setSelectMode(isSelectMode) }
        imageBoxViews.values.forEach { $0.setSelectMode(isSelectMode) }
        shapeBoxViews.values.forEach { $0.setSelectMode(isSelectMode) }
        // Re-apply current selection highlight if still in select mode
        if isSelectMode { updateSelectionUI() }
    }

    // MARK: - Gesture Recognizer Delegate

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === textBoxPanGesture {
            guard isTextMode else { return false }
            // Only allow text box creation within the image content area
            let selfPoint = gestureRecognizer.location(in: self)
            guard imageContentRect.contains(selfPoint) else { return false }
            let overlayPoint = gestureRecognizer.location(in: overlayView)
            if let hitView = overlayView.hitTest(overlayPoint, with: nil),
               hitView !== overlayView {
                return false
            }
        }
        if gestureRecognizer === shapePanGesture {
            guard isShapeMode else { return false }
            let selfPoint = gestureRecognizer.location(in: self)
            guard imageContentRect.contains(selfPoint) else { return false }
            let overlayPoint = gestureRecognizer.location(in: overlayView)
            if let hitView = overlayView.hitTest(overlayPoint, with: nil),
               hitView !== overlayView {
                return false
            }
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }
}

// MARK: - UIGestureRecognizerDelegate

extension DrawingImageView: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        let drawGestures: [UIGestureRecognizer?] = [pencilGesture, fingerPanGesture, fingerPinchGesture]
        let isFirst = drawGestures.contains(where: { $0 === gestureRecognizer })
        let isSecond = drawGestures.contains(where: { $0 === otherGestureRecognizer })
        if isFirst && isSecond { return true }
        if isFirst || isSecond { return false }
        return false
    }
}

// MARK: - Preview

#Preview {
    ImageEditorView(image: UIImage(systemName: "photo") ?? UIImage())
}
