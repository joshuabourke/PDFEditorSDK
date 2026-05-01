//
//  PDFEditorView.swift
//  PDFEditorSDK
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
    @State private var path: [EditorRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            PDFBrowseView(
                onOpen: { url in path.append(.editor(url)) }
            )
            .navigationDestination(for: EditorRoute.self) { route in
                switch route {
                case .editor(let url):
                    PDFEditorHomeContainer(
                        url: url,
                        showsDismissButton: true,
                        onSaveNavigate: { path.removeAll() }
                    )
                }
            }
        }
    }
}

enum EditorRoute: Hashable {
    case editor(URL)
}

private struct PDFEditorHomeContainer: View {
    @State private var viewModel: PDFFormViewModel
    let showsDismissButton: Bool
    let onSaveNavigate: (() -> Void)?

    init(url: URL, showsDismissButton: Bool = false, onSaveNavigate: (() -> Void)? = nil) {
        _viewModel = State(initialValue: PDFFormViewModel(documentURL: url))
        self.showsDismissButton = showsDismissButton
        self.onSaveNavigate = onSaveNavigate
    }

    var body: some View {
        PDFFormEditorView(
            viewModel: viewModel,
            showsDismissButton: showsDismissButton,
            onSaveNavigate: onSaveNavigate
        )
    }
}

struct PDFFormEditorView: View {
    @Bindable var viewModel: PDFFormViewModel
    var showsDismissButton = false
    var showsHighlightButton = true
    var showsLockButton = true
    var showsPencilButton = true
    var onSaveNavigate: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    private var toolbarChipSize: CGSize {
        viewModel.toolbarCompact ? CGSize(width: 44, height: 40) : CGSize(width: 56, height: 50)
    }
    private var toolbarButtonPadding: CGFloat {
        viewModel.toolbarCompact ? 8 : 6
    }
    private var toolbarDividerHeight: CGFloat {
        viewModel.toolbarCompact ? 30 : 36
    }
    private var toolbarDividerTopPadding: CGFloat {
        viewModel.toolbarCompact ? 12 : 14
    }
    private let selectEditToolbarChipSize = CGSize(width: 36, height: 36)
    @State private var isShowingSaveAlert = false
    @State private var isShowingExportAlert = false
    @State private var isShowingImagePicker = false
    @State private var imagePickerSource: ImagePickerSource = .photoLibrary
    /// Wraps the exported URL in an Identifiable so `.sheet(item:)` always
    /// creates a fresh sheet — even when the user shares multiple times.
    /// Using a plain Bool + URL pair causes the ActivityViewController to reuse
    /// its cached items whenever `isPresented` stays `true` across dismissals.
    @State private var shareItem: ShareableURL?
    @State private var isShowingInsertPageSheet = false
    @State private var insertPageIndex = 0
    @State private var isShowingRemovePageAlert = false
    @State private var showEditorSettings = false
    @State private var showDrawOptions = false
    @State private var showTextOptions = false
    @State private var showShapeOptions = false
    @State private var showEraserOptions = false
    @State private var showAddImageSourceDialog = false
    @State private var showImageBorderOptions = false
    @State private var showSelectShapeLineWidthPopover = false
    @State private var showSelectImageBorderWidthPopover = false
    @State private var showSelectTextBorderWidthPopover = false

    ///This is tracking to see if the user has made changes to a document, this is used to display an alert if they attempt to exit without saving.
    @State private var changesNotSaved: Bool = false
    
    var body: some View {
        coreEditorView
            .fullScreenCover(isPresented: $isShowingImagePicker) {
                ImagePicker(sourceType: imagePickerSource.uiSourceType, allowsEditing: true) { image in
                    viewModel.handleImagePickedFromSheet(image)
                }
            }
            .sheet(item: $shareItem) { item in
                ActivityView(activityItems: [item.url])
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
                            Button("Cancel") { isShowingInsertPageSheet = false }
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
            .onChange(of: viewModel.textBoxFontSize) { _, _ in viewModel.applyTextStyleToSelectedTextBox() }
            .onChange(of: viewModel.textBoxIsBold) { _, _ in viewModel.applyTextStyleToSelectedTextBox() }
            .onChange(of: viewModel.textBoxTextColor) { _, _ in viewModel.applyTextStyleToSelectedTextBox() }
            .onChange(of: viewModel.textBoxBackgroundColor) { _, _ in viewModel.applyTextStyleToSelectedTextBox() }
            .onChange(of: viewModel.textBoxTextAlignment) { _, _ in viewModel.applyTextStyleToSelectedTextBox() }
            .onChange(of: viewModel.textBoxVerticalAlignment) { _, _ in viewModel.applyTextStyleToSelectedTextBox() }
            .onChange(of: viewModel.activeShapeKind) { _, _ in viewModel.applyShapeStyleToSelected() }
            .onChange(of: viewModel.shapeStrokeColor) { _, _ in viewModel.applyShapeStyleToSelected() }
            .onChange(of: viewModel.shapeLineWidth) { _, _ in viewModel.applyShapeStyleToSelected() }
            .alert("Unsaved Changes", isPresented: $changesNotSaved) {
                Button("Save Changes") {
                    viewModel.savePDF()
                    if let onSaveNavigate {
                        onSaveNavigate()
                    } else {
                        dismiss()
                    }
                }
                Button("Discard & Close", role: .destructive) {
                    dismiss()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("You have unsaved changes. Would you like to save before closing?")
            }
    }

    private var coreEditorView: some View {
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
                        if !viewModel.undoStack.isEmpty {
                            changesNotSaved.toggle()
                        } else {
                            dismiss()
                        }
                    } label: {
                        Text("Close")
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
                    viewModel.savePDF()
                    isShowingSaveAlert = true
                    onSaveNavigate?()
                } label: {
                    Text("Save")
                }

                Button {
                    if let url = viewModel.exportFlattenedPDF() {
                        shareItem = ShareableURL(url: url)
                    } else {
                        isShowingExportAlert = true
                    }
                } label: {
                    Text("Share")
                }
            }
        }
        .alert("Save PDF", isPresented: $isShowingSaveAlert, actions: {
            Button("OK", role: .cancel) { }
        }, message: {
            Text(viewModel.saveStatus ?? "No status")
        })
        .alert("Remove Page \(viewModel.currentPageIndex + 1)?", isPresented: $isShowingRemovePageAlert, actions: {
            Button("Remove", role: .destructive) {
                viewModel.removeCurrentPage()
            }
            Button("Cancel", role: .cancel) { }
        }, message: {
            Text("This page will be removed from the document. You can undo this action.")
        })
        .alert("Export PDF", isPresented: $isShowingExportAlert, actions: {
            Button("OK", role: .cancel) { }
        }, message: {
            Text(viewModel.exportStatus ?? "No status")
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
    }
    
    private var toolbarView: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    selectToolSection

                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 1, height: toolbarDividerHeight)
                        .padding(.top, toolbarDividerTopPadding)

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
                                toolbarButtonContent("Form") {
                                    Image(systemName: "text.document")
                                        .symbolVariant(viewModel.activeTool == .form ? .fill : .none)
                                        .fontWeight(.semibold)
                                }
                                .foregroundStyle(Color.accentColor)
                                .padding(toolbarButtonPadding)
                                .background(viewModel.activeTool == .form ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.1), in: .rect(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            
                            if showsHighlightButton {
                                Button {
                                    viewModel.highlightSelectedText()
                                } label: {
                                    toolbarButtonContent("Highlight") {
                                        Image(systemName: "highlighter")
                                            .fontWeight(.semibold)
                                    }
                                    .foregroundStyle(viewModel.hasTextSelection ? Color.accentColor : .secondary.opacity(0.3))
                                    .padding(toolbarButtonPadding)
                                    .background(Color.secondary.opacity(0.1), in: .rect(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                                .disabled(!viewModel.hasTextSelection)
                            }
                            
                            if showsLockButton {
                                Button {
                                    viewModel.toggleScrollLock()
                                } label: {
                                    toolbarButtonContent("Lock") {
                                        Image(systemName: "lock")
                                            .symbolVariant(viewModel.pageScrollLocked ? .fill : .none)
                                            .fontWeight(.semibold)
                                    }
                                    .foregroundStyle(Color.accentColor)
                                    .padding(toolbarButtonPadding)
                                    .background(viewModel.pageScrollLocked ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.1), in: .rect(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    
                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 1, height: toolbarDividerHeight)
                        .padding(.top, toolbarDividerTopPadding)
                    
                    // MARK: Draw
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Draw")
                            .font(.caption2)
                            .tracking(0.5)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        toolbarButtonContent("Draw") {
                            Image(systemName: "pencil.and.scribble")
                                .symbolVariant(viewModel.isDrawingMode && !viewModel.isEraserMode ? .fill : .none)
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(Color.accentColor)
                        .padding(toolbarButtonPadding)
                        .background(
                            viewModel.isDrawingMode && !viewModel.isEraserMode
                                ? Color.accentColor.opacity(0.3)
                                : Color.secondary.opacity(0.1),
                            in: .rect(cornerRadius: 8)
                        )
                        .contentShape(Rectangle())
                        .gesture(
                            ExclusiveGesture(
                                LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                                    if !viewModel.isDrawingMode { viewModel.setTool(.draw) }
                                    showDrawOptions = true
                                },
                                TapGesture().onEnded {
                                    viewModel.setTool(.draw)
                                }
                            )
                        )
                        .popover(isPresented: $showDrawOptions, arrowEdge: .top) {
                            DrawToolOptionsView(
                                inkColor: Binding(
                                    get: { Color(viewModel.inkColor) },
                                    set: { viewModel.inkColor = UIColor($0) }
                                ),
                                inkLineWidth: $viewModel.inkLineWidth,
                                lineWidthInputStyle: viewModel.lineWidthInputStyle,
                                lineWidthStep: viewModel.lineWidthStep,
                                lineWidthMax: viewModel.lineWidthMax
                            )
                        }
                    }

                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 1, height: toolbarDividerHeight)
                        .padding(.top, toolbarDividerTopPadding)

                    // MARK: Erase
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Erase")
                            .font(.caption2)
                            .tracking(0.5)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        toolbarButtonContent("Erase") {
                            Image(systemName: "eraser")
                                .symbolVariant(viewModel.isEraserMode ? .fill : .none)
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(Color.accentColor)
                        .padding(toolbarButtonPadding)
                        .background(
                            viewModel.isEraserMode
                                ? Color.accentColor.opacity(0.3)
                                : Color.secondary.opacity(0.1),
                            in: .rect(cornerRadius: 8)
                        )
                        .contentShape(Rectangle())
                        .gesture(
                            ExclusiveGesture(
                                LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                                    viewModel.setTool(.erase)
                                    showEraserOptions = true
                                },
                                TapGesture().onEnded {
                                    viewModel.setTool(.erase)
                                }
                            )
                        )
                        .popover(isPresented: $showEraserOptions, arrowEdge: .top) {
                            EraserToolOptionsView(eraserRadius: $viewModel.eraserRadius)
                        }
                    }

                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 1, height: toolbarDividerHeight)
                        .padding(.top, toolbarDividerTopPadding)

                    // MARK: Text
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Text")
                            .font(.caption2)
                            .tracking(0.5)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        toolbarButtonContent("Text") {
                            Image(systemName: "character.cursor.ibeam")
                                .symbolVariant(viewModel.isTextMode ? .fill : .none)
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(Color.accentColor)
                        .padding(toolbarButtonPadding)
                        .background(viewModel.isTextMode ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.1), in: .rect(cornerRadius: 8))
                        .contentShape(Rectangle())
                        .gesture(
                            ExclusiveGesture(
                                LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                                    if !viewModel.isTextMode { viewModel.setTool(.text) }
                                    showTextOptions = true
                                },
                                TapGesture().onEnded { viewModel.setTool(.text) }
                            )
                        )
                        .popover(isPresented: $showTextOptions, arrowEdge: .top) {
                            TextToolOptionsView(
                                textColor: Binding(
                                    get: { Color(viewModel.textBoxTextColor) },
                                    set: { viewModel.textBoxTextColor = UIColor($0) }
                                ),
                                backgroundColor: Binding(
                                    get: { Color(viewModel.textBoxBackgroundColor) },
                                    set: { viewModel.textBoxBackgroundColor = UIColor($0) }
                                ),
                                fontSize: $viewModel.textBoxFontSize,
                                isBold: $viewModel.textBoxIsBold,
                                textAlignment: $viewModel.textBoxTextAlignment,
                                verticalAlignment: $viewModel.textBoxVerticalAlignment,
                                autoResize: $viewModel.textBoxAutoResize,
                                borderWidth: $viewModel.textBoxBorderWidth,
                                borderColor: Binding(
                                    get: { Color(viewModel.textBoxBorderColor) },
                                    set: { viewModel.textBoxBorderColor = UIColor($0) }
                                ),
                                lineWidthInputStyle: viewModel.lineWidthInputStyle,
                                lineWidthStep: viewModel.lineWidthStep,
                                lineWidthMax: viewModel.lineWidthMax
                            )
                        }
                    }
                    
                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 1, height: toolbarDividerHeight)
                        .padding(.top, toolbarDividerTopPadding)

                    shapeToolSection

                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 1, height: toolbarDividerHeight)
                        .padding(.top, toolbarDividerTopPadding)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Image")
                            .font(.caption2)
                            .tracking(0.5)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        toolbarButtonContent("Image") {
                            Image(systemName: "photo.on.rectangle")
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(Color.accentColor)
                        .padding(toolbarButtonPadding)
                        .background(Color.secondary.opacity(0.1), in: .rect(cornerRadius: 8))
                        .contentShape(Rectangle())
                        .gesture(
                            ExclusiveGesture(
                                LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                                    showImageBorderOptions = true
                                },
                                TapGesture().onEnded {
                                    showAddImageSourceDialog = true
                                }
                            )
                        )
                        .popover(isPresented: $showImageBorderOptions, arrowEdge: .top) {
                            ImageBorderToolOptionsView(
                                borderWidth: Binding(
                                    get: { viewModel.imageBorderWidth },
                                    set: { viewModel.commitImageBorderWidth($0) }
                                ),
                                borderColor: Binding(
                                    get: { Color(viewModel.imageBorderColor) },
                                    set: { viewModel.commitImageBorderColor(UIColor($0)) }
                                ),
                                lineWidthInputStyle: viewModel.lineWidthInputStyle,
                                lineWidthStep: viewModel.lineWidthStep,
                                lineWidthMax: viewModel.lineWidthMax
                            )
                        }
                        .confirmationDialog(
                            "Add Image",
                            isPresented: $showAddImageSourceDialog,
                            titleVisibility: .visible
                        ) {
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
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("Choose a source for the image.")
                        }
                    }

                    if showsPencilButton {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.25))
                            .frame(width: 1, height: toolbarDividerHeight)
                            .padding(.top, toolbarDividerTopPadding)

                        VStack(spacing: 6) {
                            Text("Pencil")
                                .font(.caption2)
                                .tracking(0.5)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                            Button {
                                viewModel.setTool(.pencilKit)
                            } label: {
                                toolbarButtonContent("Pencil") {
                                    Image(systemName: "pencil.and.outline")
                                        .symbolVariant(viewModel.activeTool == .pencilKit ? .fill : .none)
                                        .fontWeight(.semibold)
                                }
                                .foregroundStyle(Color.accentColor)
                                .padding(toolbarButtonPadding)
                                .background(viewModel.activeTool == .pencilKit ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.1), in: .rect(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 1, height: toolbarDividerHeight)
                        .padding(.top, toolbarDividerTopPadding)

                    // MARK: Settings Section
                    VStack(spacing: 6) {
                        Text("Settings")
                            .font(.caption2)
                            .tracking(0.5)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        Button {
                            showEditorSettings.toggle()
                        } label: {
                            toolbarButtonContent("Settings") {
                                Image(systemName: "slider.horizontal.3")
                                    .symbolVariant(showEditorSettings ? .fill : .none)
                                    .fontWeight(.semibold)
                            }
                            .foregroundStyle(Color.accentColor)
                            .padding(toolbarButtonPadding)
                            .background(showEditorSettings ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.1), in: .rect(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showEditorSettings, arrowEdge: .top) {
                            EditorSettingsView(
                                drawWithFinger: $viewModel.drawWithFinger,
                                pencilOnlyAnnotations: $viewModel.pencilOnlyAnnotations,
                                pencilDoubleTapAction: $viewModel.pencilDoubleTapAction,
                                pencilSqueezeAction: $viewModel.pencilSqueezeAction,
                                pencilDoubleSqueezeAction: $viewModel.pencilDoubleSqueezeAction,
                                toolbarCompact: $viewModel.toolbarCompact,
                                lineWidthInputStyle: $viewModel.lineWidthInputStyle,
                                lineWidthStep: $viewModel.lineWidthStep,
                                lineWidthMax: $viewModel.lineWidthMax
                            )
                        }
                    }

                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 1, height: toolbarDividerHeight)
                        .padding(.top, toolbarDividerTopPadding)

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
                                        toolbarButtonContent("Add") {
                                            Image(systemName: "doc.badge.plus")
                                                .fontWeight(.semibold)
                                }
                                .foregroundStyle(Color.accentColor)
                                .padding(toolbarButtonPadding)
                                .background(Color.secondary.opacity(0.1), in: .rect(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)

                            Button {
                                isShowingRemovePageAlert = true
                            } label: {
                                toolbarButtonContent("Remove") {
                                    Image(systemName: "doc")
                                        .fontWeight(.semibold)
                                }
                                .foregroundStyle(viewModel.pageCount > 1 ? Color.red : Color.secondary)
                                .padding(toolbarButtonPadding)
                                .background(Color.secondary.opacity(0.1), in: .rect(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.pageCount <= 1)
                            
                            Button {
                                viewModel.isThumbnailOverlayVisible.toggle()
                            } label: {
                                toolbarButtonContent("Preview") {
                                    Image(systemName: viewModel.isThumbnailOverlayVisible ? "inset.filled.bottomthird.rectangle.portrait" : "rectangle.portrait")
                                        .fontWeight(.semibold)
                                }
                                .foregroundStyle(Color.accentColor)
                                .padding(toolbarButtonPadding)
                                .background(viewModel.isThumbnailOverlayVisible ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.1), in: .rect(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }//: HSTACK

            }//: SCROLL

            if showsSelectEditToolbar {
                selectEditToolbar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }//: VSTACK
        .animation(.easeInOut(duration: 0.2), value: showsSelectEditToolbar)
        .animation(.easeInOut(duration: 0.2), value: viewModel.selectedOverlayKind)
        .contentBackgroundModifier()
    }
    
    @ViewBuilder
    private var shapeToolSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Shape")
                .font(.caption2).tracking(0.5).fontWeight(.semibold).foregroundStyle(.secondary)
            toolbarButtonContent("Shape") {
                Image(systemName: iconName(for: viewModel.activeShapeKind))
                    .symbolVariant(viewModel.isShapeMode ? .fill : .none)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(Color.accentColor)
            .padding(toolbarButtonPadding)
            .background(viewModel.isShapeMode ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.1), in: .rect(cornerRadius: 8))
            .contentShape(Rectangle())
            .gesture(
                ExclusiveGesture(
                    LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                        if !viewModel.isShapeMode { viewModel.setTool(.shape) }
                        showShapeOptions = true
                    },
                    TapGesture().onEnded { viewModel.setTool(.shape) }
                )
            )
            .popover(isPresented: $showShapeOptions, arrowEdge: .top) {
                ShapeToolOptionsView(
                    shapeKind: $viewModel.activeShapeKind,
                    strokeColor: Binding(
                        get: { Color(viewModel.shapeStrokeColor) },
                        set: { viewModel.shapeStrokeColor = UIColor($0) }
                    ),
                    lineWidth: $viewModel.shapeLineWidth,
                    lineWidthInputStyle: viewModel.lineWidthInputStyle,
                    lineWidthStep: viewModel.lineWidthStep,
                    lineWidthMax: viewModel.lineWidthMax
                )
            }
        }
    }

    @ViewBuilder
    private var selectToolSection: some View {
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
                    toolbarButtonContent("Select") {
                        Image(systemName: "cursorarrow.rays")
                            .symbolVariant(viewModel.activeTool == .select ? .fill : .none)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(Color.accentColor)
                    .padding(toolbarButtonPadding)
                    .background(viewModel.activeTool == .select ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.1), in: .rect(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var showsSelectEditToolbar: Bool {
        viewModel.activeTool == .select
            && (viewModel.selectedOverlayKind != nil || viewModel.hasSelectedInkAnnotation || viewModel.hasSelectedOverlayObject)
    }

    @ViewBuilder
    private var selectEditToolbar: some View {
        HStack(alignment: .center, spacing: 8) {
            if viewModel.selectedOverlayKind == .textBox {
                selectTextBoxSubtools
            }

            if viewModel.selectedOverlayKind == .shape {
                selectShapeSubtools
            }

            if viewModel.selectedOverlayKind == .image {
                selectImageSubtools
            }

            if viewModel.hasSelectedInkAnnotation && viewModel.selectedOverlayKind == nil {
                deleteSelectionButton
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 10))
    }

    private var deleteSelectionButton: some View {
        Button {
            viewModel.deleteSelectedSelection()
        } label: {
            selectEditToolbarChip("Delete") {
                Image(systemName: "trash")
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.red)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var selectImageBorderWidthChipLabel: some View {
        selectEditToolbarChip("Image border width", isActive: viewModel.imageBorderWidth > 0) {
            Image(systemName: "square.dashed").fontWeight(.semibold)
            Text(
                LineWidthFormatting.toolbarPointsLabel(
                    viewModel.imageBorderWidth,
                    style: viewModel.lineWidthInputStyle,
                    step: viewModel.lineWidthStep
                )
            )
            .fontWeight(.semibold)
        }
        .foregroundStyle(Color.accentColor)
    }

    @ViewBuilder
    private var selectImageSubtools: some View {
        ToolbarSubtoolsScrollRow {
            ColorPicker("", selection: Binding(
                get: { Color(viewModel.imageBorderColor) },
                set: { viewModel.commitImageBorderColor(UIColor($0)) }
            ))
            .labelsHidden()
            .frame(width: selectEditToolbarChipSize.width, height: selectEditToolbarChipSize.height)
            .background(toolbarChipBackground())

            Group {
                if viewModel.lineWidthInputStyle == .presetButtons {
                    Menu {
                        MenuScrollableActions {
                            Button("None") { viewModel.commitImageBorderWidth(0) }
                            Button("Thin (1pt)") { viewModel.commitImageBorderWidth(1) }
                            Button("Medium (2pt)") { viewModel.commitImageBorderWidth(2) }
                            Button("Thick (4pt)") { viewModel.commitImageBorderWidth(4) }
                            Button("Heavy (6pt)") { viewModel.commitImageBorderWidth(6) }
                        }
                    } label: {
                        selectImageBorderWidthChipLabel
                    }
                } else {
                    Button {
                        showSelectImageBorderWidthPopover = true
                    } label: {
                        selectImageBorderWidthChipLabel
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showSelectImageBorderWidthPopover, arrowEdge: .top) {
                        ToolbarLineWidthStepperPanel(
                            width: Binding(
                                get: { viewModel.imageBorderWidth },
                                set: { viewModel.commitImageBorderWidth($0) }
                            ),
                            step: viewModel.lineWidthStep,
                            max: viewModel.lineWidthMax,
                            allowsZero: true,
                            title: "Border width"
                        )
                    }
                }
            }

            deleteSelectionButton
        }
    }
    
    @ViewBuilder
    private var selectTextBoxBorderWidthChipLabel: some View {
        selectEditToolbarChip("Text box border width", isActive: viewModel.selectedTextBoxBorderWidth > 0) {
            Image(systemName: "square.dashed").fontWeight(.semibold)
            Text(selectedTextBoxBorderWidthLabel)
            .fontWeight(.semibold)
        }
        .foregroundStyle(selectedTextBoxBorderControlColor)
    }

    @ViewBuilder
    private var selectTextBoxSubtools: some View {
        ToolbarSubtoolsScrollRow {
            ColorPicker(selection: Binding(
                get: { Color(viewModel.textBoxTextColor) },
                set: { viewModel.textBoxTextColor = UIColor($0) }
            )) {
                selectEditToolbarChip("Text color") {
                    Image(systemName: "textformat")
                        .fontWeight(.semibold)
                        .foregroundStyle(Color(viewModel.textBoxTextColor))
                }
                .foregroundStyle(Color.accentColor)
            }

            ColorPicker(selection: Binding(
                get: { Color(viewModel.textBoxBackgroundColor) },
                set: { viewModel.textBoxBackgroundColor = UIColor($0) }
            ), supportsOpacity: true) {
                selectEditToolbarChip("Background color") {
                    ZStack {
                        Image(systemName: "rectangle")
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        Image(systemName: "rectangle.fill")
                            .fontWeight(.semibold)
                            .foregroundStyle(Color(viewModel.textBoxBackgroundColor))
                    }
                }
                .foregroundStyle(Color.accentColor)
            }

            Menu {
                MenuScrollableActions {
                    Button("Small (12pt)") { viewModel.textBoxFontSize = 12 }
                    Button("Medium (14pt)") { viewModel.textBoxFontSize = 14 }
                    Button("Large (18pt)") { viewModel.textBoxFontSize = 18 }
                    Button("XL (22pt)") { viewModel.textBoxFontSize = 22 }
                }
            } label: {
                selectEditToolbarChip("Font size") {
                    Image(systemName: "textformat.size").fontWeight(.semibold)
                    Text("\(Int(viewModel.textBoxFontSize))pt")
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(Color.accentColor)
            }
            Button { viewModel.textBoxIsBold.toggle() } label: {
                selectEditToolbarChip("Bold", isActive: viewModel.textBoxIsBold) {
                    Image(systemName: "bold").fontWeight(.semibold)
                }
                .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            Menu {
                MenuScrollableActions {
                    Button {
                        viewModel.textBoxTextAlignment = .left
                    } label: {
                        Label("Leading", systemImage: "text.alignleft")
                    }
                    Button {
                        viewModel.textBoxTextAlignment = .center
                    } label: {
                        Label("Center", systemImage: "text.aligncenter")
                    }
                    Button {
                        viewModel.textBoxTextAlignment = .right
                    } label: {
                        Label("Trailing", systemImage: "text.alignright")
                    }
                }
            } label: {
                selectEditToolbarChip("Text alignment") {
                    Image(systemName: alignmentIcon(for: viewModel.textBoxTextAlignment))
                        .fontWeight(.semibold)
                }
                .foregroundStyle(Color.accentColor)
            }
            Menu {
                MenuScrollableActions {
                    Button {
                        viewModel.textBoxVerticalAlignment = .top
                    } label: {
                        Label("Top", systemImage: "arrow.up.to.line")
                    }
                    Button {
                        viewModel.textBoxVerticalAlignment = .middle
                    } label: {
                        Label("Middle", systemImage: "arrow.up.and.down")
                    }
                    Button {
                        viewModel.textBoxVerticalAlignment = .bottom
                    } label: {
                        Label("Bottom", systemImage: "arrow.down.to.line")
                    }
                }
            } label: {
                selectEditToolbarChip("Vertical alignment") {
                    Image(systemName: verticalAlignmentIcon(for: viewModel.textBoxVerticalAlignment))
                        .fontWeight(.semibold)
                }
                .foregroundStyle(Color.accentColor)
            }

            Button { viewModel.toggleSelectedTextBoxAutoResize() } label: {
                selectEditToolbarChip("Auto size", isActive: viewModel.selectedTextBoxAutoResize) {
                    Image(systemName: "arrow.up.and.down")
                        .fontWeight(.semibold)
                }
                .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)

            Button {
                showSelectTextBorderWidthPopover = true
            } label: {
                selectTextBoxBorderWidthChipLabel
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showSelectTextBorderWidthPopover, arrowEdge: .top) {
                ToolbarBorderWidthColorPanel(
                    width: Binding(
                        get: { viewModel.selectedTextBoxBorderWidth },
                        set: { viewModel.commitSelectedTextBoxBorderWidth($0) }
                    ),
                    color: Binding(
                        get: { Color(viewModel.selectedTextBoxBorderColor) },
                        set: { viewModel.commitSelectedTextBoxBorderColor(UIColor($0)) }
                    ),
                    style: viewModel.lineWidthInputStyle,
                    step: viewModel.lineWidthStep,
                    max: viewModel.lineWidthMax,
                    title: "Text box border"
                )
            }

            deleteSelectionButton
        }
    }

    private func alignmentIcon(for alignment: NSTextAlignment) -> String {
        switch alignment {
        case .center:  return "text.aligncenter"
        case .right:   return "text.alignright"
        default:       return "text.alignleft"
        }
    }

    private func verticalAlignmentIcon(for alignment: TextVerticalAlignment) -> String {
        switch alignment {
        case .top:    return "arrow.up.to.line"
        case .middle: return "arrow.up.and.down"
        case .bottom: return "arrow.down.to.line"
        }
    }

    private var selectedTextBoxBorderWidthLabel: String {
        guard viewModel.selectedTextBoxBorderWidth > 0 else { return "No" }
        return LineWidthFormatting.toolbarPointsLabel(
            viewModel.selectedTextBoxBorderWidth,
            style: viewModel.lineWidthInputStyle,
            step: viewModel.lineWidthStep
        )
    }

    private var selectedTextBoxBorderControlColor: Color {
        viewModel.selectedTextBoxBorderWidth > 0 ? Color(viewModel.selectedTextBoxBorderColor) : Color.accentColor
    }

    @ViewBuilder
    private var selectShapeLineWidthChipLabel: some View {
        selectEditToolbarChip("Stroke width") {
            Image(systemName: "lineweight").fontWeight(.semibold)
            Text(
                LineWidthFormatting.shapeStrokeLabel(
                    viewModel.shapeLineWidth,
                    style: viewModel.lineWidthInputStyle,
                    step: viewModel.lineWidthStep
                )
            )
            .fontWeight(.semibold)
        }
        .foregroundStyle(Color.accentColor)
    }

    @ViewBuilder
    private var selectShapeSubtools: some View {
        ToolbarSubtoolsScrollRow {
            Menu {
                shapeKindMenuActions
            } label: {
                selectEditToolbarChip("Shape kind") {
                    Image(systemName: iconName(for: viewModel.activeShapeKind))
                        .fontWeight(.semibold)
                }
                .foregroundStyle(Color.accentColor)
            }

            ColorPicker("", selection: Binding(
                get: { Color(viewModel.shapeStrokeColor) },
                set: { viewModel.shapeStrokeColor = UIColor($0) }
            ))
            .labelsHidden()
            .frame(width: selectEditToolbarChipSize.width, height: selectEditToolbarChipSize.height)
            .background(toolbarChipBackground())
            Group {
                if viewModel.lineWidthInputStyle == .presetButtons {
                    Menu {
                        MenuScrollableActions {
                            Button("Thin (1pt)") { viewModel.shapeLineWidth = 1 }
                            Button("Medium (2pt)") { viewModel.shapeLineWidth = 2 }
                            Button("Thick (4pt)") { viewModel.shapeLineWidth = 4 }
                            Button("Heavy (6pt)") { viewModel.shapeLineWidth = 6 }
                        }
                    } label: {
                        selectShapeLineWidthChipLabel
                    }
                } else {
                    Button {
                        showSelectShapeLineWidthPopover = true
                    } label: {
                        selectShapeLineWidthChipLabel
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showSelectShapeLineWidthPopover, arrowEdge: .top) {
                        ToolbarLineWidthStepperPanel(
                            width: $viewModel.shapeLineWidth,
                            step: viewModel.lineWidthStep,
                            max: viewModel.lineWidthMax,
                            allowsZero: false,
                            title: "Stroke width"
                        )
                    }
                }
            }

            deleteSelectionButton
        }
    }

    @ViewBuilder
    private var shapeKindMenuActions: some View {
        Button {
            viewModel.activeShapeKind = .circle
        } label: {
            Label("Circle", systemImage: iconName(for: .circle))
        }
        Button {
            viewModel.activeShapeKind = .rectangle
        } label: {
            Label("Rectangle", systemImage: iconName(for: .rectangle))
        }
        Button {
            viewModel.activeShapeKind = .triangle
        } label: {
            Label("Triangle", systemImage: iconName(for: .triangle))
        }
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

    private func selectEditToolbarChip<Content: View>(
        _ accessibilityLabel: String,
        isActive: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 1) {
            content()
        }
        .frame(width: selectEditToolbarChipSize.width, height: selectEditToolbarChipSize.height, alignment: .center)
        .multilineTextAlignment(.center)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .background(toolbarChipBackground(isActive: isActive))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private func toolbarButtonContent<Icon: View>(_ title: String, @ViewBuilder icon: () -> Icon) -> some View {
        VStack(spacing: viewModel.toolbarCompact ? 0 : 4) {
            icon()
            if !viewModel.toolbarCompact {
                Text(title)
                    .fontWeight(.semibold)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
    }

    private func toolbarChipBackground(isActive: Bool = false) -> some View {
        Color.clear
            .background(isActive ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.1), in: .rect(cornerRadius: 8))
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
        picker.allowsEditing = false   // crop is handled by ImageCropViewController
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

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage else {
                onImagePicked(nil)
                picker.dismiss(animated: true)
                return
            }

            // Present the dedicated crop view on top of the picker
            let cropVC = ImageCropViewController(image: image)
            let nav = UINavigationController(rootViewController: cropVC)
            nav.modalPresentationStyle = .fullScreen
            nav.navigationBar.barStyle = .black
            nav.navigationBar.tintColor = .white
            nav.navigationBar.titleTextAttributes = [.foregroundColor: UIColor.white]

            cropVC.onConfirm = { [weak picker] cropped in
                // Dismiss the picker from its presenting VC — closes the entire stack
                picker?.presentingViewController?.dismiss(animated: true)
                self.onImagePicked(cropped)
            }
            cropVC.onCancel = { [weak picker] in
                // Cancel from crop also closes the picker entirely
                picker?.presentingViewController?.dismiss(animated: true)
                self.onImagePicked(nil)
            }

            picker.present(nav, animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onImagePicked(nil)
            picker.dismiss(animated: true)
        }
    }
}

/// Wraps a URL in an Identifiable so `.sheet(item:)` always creates a
/// fresh UIActivityViewController for each export, preventing stale shares.
private struct ShareableURL: Identifiable {
    let id = UUID()
    let url: URL
}

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
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
        pdfView.textBoxTextAlignment = viewModel.textBoxTextAlignment
        pdfView.textBoxVerticalAlignment = viewModel.textBoxVerticalAlignment
        pdfView.textBoxAutoResize = viewModel.textBoxAutoResize
        pdfView.textBoxBorderWidth = viewModel.textBoxBorderWidth
        pdfView.textBoxBorderColor = viewModel.textBoxBorderColor
        pdfView.isShapeMode = viewModel.activeTool == .shape
        pdfView.currentShapeKind = viewModel.activeShapeKind
        pdfView.shapeStrokeColor = viewModel.shapeStrokeColor
        pdfView.shapeLineWidth = viewModel.shapeLineWidth
        pdfView.isPencilKitMode = viewModel.activeTool == .pencilKit
        pdfView.setFormFieldEntryEnabled(viewModel.activeTool == .form)
        pdfView.isUserInteractionEnabled = !viewModel.pageScrollLocked
        pdfView.formFieldHighlightFilter = viewModel.shouldHighlightFormField
        pdfView.drawWithFinger = viewModel.drawWithFinger
        pdfView.pencilOnlyAnnotations = viewModel.pencilOnlyAnnotations
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
    @State private var files: [URL] = []
    var onOpen: ((URL) -> Void)?
    @State private var openError: String?
    @State private var isShowingOpenAlert = false
    @State private var isShowingFileImporter = false

    var body: some View {
        List {
            Section("Create") {
                Button {
                    if let url = templateURL() {
                        onOpen?(url)
                    } else {
                        openError = "Could not find template PDF."
                        isShowingOpenAlert = true
                    }
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
                            onOpen?(url)
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
                openError = "Failed to open file from Files."
                isShowingOpenAlert = true
            }
        }
        .alert("Open PDF", isPresented: $isShowingOpenAlert, actions: {
            Button("OK", role: .cancel) { }
        }, message: {
            Text(openError ?? "Failed to open PDF")
        })
    }

    private func templateURL() -> URL? {
        if let url = Bundle.main.url(forResource: "SampleForm", withExtension: "pdf") {
            return url
        }
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = documentsPath.appendingPathComponent("SampleForm.pdf")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
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
            loadFiles()
            onOpen?(destinationURL)
        } catch {
            openError = "Failed to import PDF from Files."
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
