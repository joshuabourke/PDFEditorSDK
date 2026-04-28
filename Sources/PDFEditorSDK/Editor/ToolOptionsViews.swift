//
//  ToolOptionsViews.swift
//  PDFEditorSDK
//

import SwiftUI
import UIKit

// MARK: - Scrollable toolbar / menu helpers

/// Vertical scroll for `Menu` content when the action list is taller than available space (e.g. iPad landscape).
struct MenuScrollableActions<Content: View>: View {
    var maxHeight: CGFloat = 340
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
        }
        .frame(maxHeight: maxHeight)
    }
}

/// Many toolbar chips in one row: caps width so the strip scrolls horizontally instead of clipping.
struct ToolbarSubtoolsScrollRow<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ViewBuilder var content: () -> Content

    private var maxStripWidth: CGFloat {
        horizontalSizeClass == .compact ? 300 : 540
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(alignment: .center, spacing: 8) {
                content()
            }
        }
        .frame(maxWidth: maxStripWidth)
    }
}

// MARK: - Draw Tool Options

struct DrawToolOptionsView: View {
    @Binding var inkColor: Color
    @Binding var inkLineWidth: CGFloat
    var lineWidthInputStyle: LineWidthInputStyle
    var lineWidthStep: CGFloat
    var lineWidthMax: CGFloat

    var body: some View {
        ToolOptionsContainer(title: "Draw Settings") {
            HStack {
                Label("Color", systemImage: "paintbrush.pointed")
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                ColorPicker("", selection: $inkColor)
                    .labelsHidden()
            }
            .toolOptionRow()

            Divider()

            LineWidthInputRow(
                title: "Line Width",
                value: $inkLineWidth,
                style: lineWidthInputStyle,
                step: lineWidthStep,
                max: lineWidthMax,
                allowsZero: false,
                presetOptions: [(1.0, "1pt"), (3.0, "3pt"), (6.0, "6pt")]
            )
            .toolOptionRow()
        }
    }
}

// MARK: - Text Tool Options

struct TextToolOptionsView: View {
    @Binding var textColor: Color
    @Binding var backgroundColor: Color
    @Binding var fontSize: CGFloat
    @Binding var isBold: Bool
    @Binding var textAlignment: NSTextAlignment
    @Binding var verticalAlignment: TextVerticalAlignment
    @Binding var autoResize: Bool
    @Binding var borderWidth: CGFloat
    @Binding var borderColor: Color
    var lineWidthInputStyle: LineWidthInputStyle
    var lineWidthStep: CGFloat
    var lineWidthMax: CGFloat

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// Long-press Text tool popover: cap scroll area so the sheet fits in compact vertical space (e.g. iPhone / iPad landscape).
    private var textOptionsScrollMaxHeight: CGFloat {
        verticalSizeClass == .compact ? 280 : 420
    }

    var body: some View {
        ToolOptionsContainer(title: "Text Settings") {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Text Color", systemImage: "character")
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                ColorPicker("", selection: $textColor)
                    .labelsHidden()
            }
            .toolOptionRow()

            Divider()

            HStack {
                Label("Background", systemImage: "rectangle.fill")
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                ColorPicker("", selection: $backgroundColor, supportsOpacity: true)
                    .labelsHidden()
            }
            .toolOptionRow()

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Font Size")
                    .font(.caption)
                    .fontWeight(.semibold)
                SegmentedOptionRow(
                    options: [(12.0, "12pt"), (14.0, "14pt"), (18.0, "18pt"), (22.0, "22pt")],
                    selected: $fontSize
                )
            }
            .toolOptionRow()

            Divider()

            Toggle(isOn: $isBold) {
                Label("Bold", systemImage: "bold")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .toolOptionRow()

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Horizontal Alignment")
                    .font(.caption)
                    .fontWeight(.semibold)
                HStack(spacing: 4) {
                    ForEach([
                        (NSTextAlignment.left,   "text.alignleft",   "Leading"),
                        (.center,                "text.aligncenter", "Center"),
                        (.right,                 "text.alignright",  "Trailing"),
                    ] as [(NSTextAlignment, String, String)], id: \.2) { alignment, icon, label in
                        Button {
                            textAlignment = alignment
                        } label: {
                            VStack(spacing: 3) {
                                Image(systemName: icon)
                                    .font(.callout).fontWeight(.semibold)
                                Text(label)
                                    .font(.caption2).fontWeight(.medium)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(
                                textAlignment == alignment
                                    ? Color.accentColor
                                    : Color.secondary.opacity(0.15),
                                in: .rect(cornerRadius: 8)
                            )
                            .foregroundStyle(textAlignment == alignment ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .toolOptionRow()

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Vertical Alignment")
                    .font(.caption)
                    .fontWeight(.semibold)
                HStack(spacing: 4) {
                    ForEach([
                        (TextVerticalAlignment.top,    "arrow.up.to.line",     "Top"),
                        (.middle,                      "arrow.up.and.down",    "Middle"),
                        (.bottom,                      "arrow.down.to.line",   "Bottom"),
                    ] as [(TextVerticalAlignment, String, String)], id: \.2) { alignment, icon, label in
                        Button {
                            verticalAlignment = alignment
                        } label: {
                            VStack(spacing: 3) {
                                Image(systemName: icon)
                                    .font(.callout).fontWeight(.semibold)
                                Text(label)
                                    .font(.caption2).fontWeight(.medium)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(
                                verticalAlignment == alignment
                                    ? Color.accentColor
                                    : Color.secondary.opacity(0.15),
                                in: .rect(cornerRadius: 8)
                            )
                            .foregroundStyle(verticalAlignment == alignment ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .toolOptionRow()

            Divider()

            Toggle(isOn: $autoResize) {
                Label("Auto Size to Text", systemImage: "arrow.up.and.down")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .toolOptionRow()

            Divider()

            HStack {
                Label("Border Color", systemImage: "square.dashed")
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                ColorPicker("", selection: $borderColor)
                    .labelsHidden()
            }
            .toolOptionRow()

            Divider()

            LineWidthInputRow(
                title: "Border Width",
                value: $borderWidth,
                style: lineWidthInputStyle,
                step: lineWidthStep,
                max: lineWidthMax,
                allowsZero: true,
                presetOptions: [(0.0, "None"), (1.0, "1pt"), (2.0, "2pt"), (4.0, "4pt"), (6.0, "6pt")]
            )
            .toolOptionRow()
                }
            }
            .frame(maxHeight: textOptionsScrollMaxHeight)
        }
    }
}

// MARK: - Shape Tool Options

struct ShapeToolOptionsView: View {
    @Binding var shapeKind: OverlayShapeKind
    @Binding var strokeColor: Color
    @Binding var lineWidth: CGFloat
    var lineWidthInputStyle: LineWidthInputStyle
    var lineWidthStep: CGFloat
    var lineWidthMax: CGFloat

    var body: some View {
        ToolOptionsContainer(title: "Shape Settings") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Shape")
                    .font(.caption)
                    .fontWeight(.semibold)
                HStack(spacing: 8) {
                    ForEach([OverlayShapeKind.circle, .rectangle, .triangle], id: \.self) { kind in
                        ShapeKindButton(kind: kind, isSelected: shapeKind == kind) {
                            shapeKind = kind
                        }
                    }
                }
            }
            .toolOptionRow()

            Divider()

            HStack {
                Label("Stroke Color", systemImage: "paintbrush.pointed")
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                ColorPicker("", selection: $strokeColor)
                    .labelsHidden()
            }
            .toolOptionRow()

            Divider()

            LineWidthInputRow(
                title: "Line Width",
                value: $lineWidth,
                style: lineWidthInputStyle,
                step: lineWidthStep,
                max: lineWidthMax,
                allowsZero: false,
                presetOptions: [(1.0, "1pt"), (2.0, "2pt"), (4.0, "4pt"), (6.0, "6pt")]
            )
            .toolOptionRow()
        }
    }
}

// MARK: - Image Border Defaults (toolbar long-press popover)

struct ImageBorderToolOptionsView: View {
    @Binding var borderWidth: CGFloat
    @Binding var borderColor: Color
    var lineWidthInputStyle: LineWidthInputStyle
    var lineWidthStep: CGFloat
    var lineWidthMax: CGFloat

    var body: some View {
        ToolOptionsContainer(title: "Image Border") {
            HStack {
                Label("Border Color", systemImage: "paintbrush.pointed")
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                ColorPicker("", selection: $borderColor)
                    .labelsHidden()
            }
            .toolOptionRow()

            Divider()

            LineWidthInputRow(
                title: "Default width",
                value: $borderWidth,
                style: lineWidthInputStyle,
                step: lineWidthStep,
                max: lineWidthMax,
                allowsZero: true,
                presetOptions: [(0.0, "None"), (1.0, "1pt"), (2.0, "2pt"), (4.0, "4pt"), (6.0, "6pt")]
            )
            .toolOptionRow()
        }
    }
}

// MARK: - Eraser Tool Options

struct EraserToolOptionsView: View {
    @Binding var eraserRadius: CGFloat

    var body: some View {
        ToolOptionsContainer(title: "Eraser Settings") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Size")
                    .font(.caption)
                    .fontWeight(.semibold)
                SegmentedOptionRow(
                    options: [
                        (6.0, "6pt"),
                        (9.0, "9pt"),
                        (13.0, "13pt"),
                        (18.0, "18pt"),
                        (24.0, "24pt"),
                    ],
                    selected: $eraserRadius
                )
            }
            .toolOptionRow()
        }
    }
}

// MARK: - Shared Helpers

private struct ToolOptionsContainer<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)

            Divider()

            content()
        }
        .frame(width: 300)
        .padding(.bottom, 4)
    }
}

struct SegmentedOptionRow<T: Equatable>: View {
    let options: [(T, String)]
    @Binding var selected: T

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, pair in
                Button(pair.1) {
                    selected = pair.0
                }
                .buttonStyle(.plain)
                .font(.caption2)
                .fontWeight(.medium)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .background(
                    selected == pair.0
                        ? Color.accentColor
                        : Color.secondary.opacity(0.15),
                    in: .rect(cornerRadius: 8)
                )
                .foregroundStyle(selected == pair.0 ? Color.white : Color.primary)
            }
        }
    }
}

// MARK: - Line width (preset vs stepper)

private struct LineWidthStepperControl: View {
    @Binding var value: CGFloat
    let step: CGFloat
    let max: CGFloat
    let allowsZero: Bool

    @State private var editingText = ""
    @FocusState private var isFieldFocused: Bool

    private var minWidth: CGFloat { allowsZero ? 0 : 0.25 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if allowsZero || isFieldFocused {
                HStack(spacing: 8) {
                    if allowsZero {
                        Button("None") {
                            value = 0
                            editingText = "0"
                            isFieldFocused = false
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                        .controlSize(.small)
                    }
                    Spacer(minLength: 0)
                    if isFieldFocused {
                        Button("Done") {
                            commitEditing()
                            isFieldFocused = false
                        }
                        .font(.caption)
                        .fontWeight(.semibold)
                    }
                }
            }

            Stepper(
                value: Binding(
                    get: { Double(value) },
                    set: { newVal in
                        value = LineWidthFormatting.snap(CGFloat(newVal), step: step, min: minWidth, max: max)
                        syncTextFromValue()
                    }
                ),
                in: Double(minWidth)...Double(max),
                step: Double(step)
            ) {
                HStack(spacing: 8) {
                    TextField("Width", text: $editingText)
                        .keyboardType(.decimalPad)
                        .focused($isFieldFocused)
                        .multilineTextAlignment(.trailing)
                        .font(.body.monospacedDigit())
                        .frame(minWidth: 48, maxWidth: 88)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Width in points")
                    Text("pt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            syncTextFromValue()
        }
        .onChange(of: value) { _, _ in
            if !isFieldFocused {
                syncTextFromValue()
            }
        }
        .onChange(of: isFieldFocused) { _, focused in
            if !focused {
                commitEditing()
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                HStack {
                    Spacer(minLength: 0)
                    Button("Done") {
                        commitEditing()
                        isFieldFocused = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func syncTextFromValue() {
        editingText = formattedNumber(for: value)
    }

    /// Numeric string for the text field (no "pt" suffix).
    private func formattedNumber(for v: CGFloat) -> String {
        if allowsZero && v <= 0 { return "0" }
        if step < 1 {
            return String(format: "%.1f", Double(v))
        }
        return "\(Int(v.rounded()))"
    }

    private func commitEditing() {
        let trimmed = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            syncTextFromValue()
            return
        }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let parsed = Double(normalized) else {
            syncTextFromValue()
            return
        }
        if allowsZero && parsed <= 0 {
            value = 0
            editingText = "0"
            return
        }
        let snapped = LineWidthFormatting.snap(CGFloat(parsed), step: step, min: minWidth, max: max)
        value = snapped
        syncTextFromValue()
    }
}

struct LineWidthInputRow: View {
    var title: String?
    @Binding var value: CGFloat
    let style: LineWidthInputStyle
    let step: CGFloat
    let max: CGFloat
    let allowsZero: Bool
    let presetOptions: [(CGFloat, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            if style == .presetButtons {
                SegmentedOptionRow(options: presetOptions, selected: $value)
            } else {
                LineWidthStepperControl(value: $value, step: step, max: max, allowsZero: allowsZero)
            }
        }
    }
}

/// Stepper-only panel for compact toolbar popovers when line width style is stepper.
struct ToolbarLineWidthStepperPanel: View {
    @Binding var width: CGFloat
    let step: CGFloat
    let max: CGFloat
    let allowsZero: Bool
    var title: String = "Width"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            LineWidthStepperControl(value: $width, step: step, max: max, allowsZero: allowsZero)
        }
        .padding(16)
        .frame(width: 280)
    }
}

private struct ShapeKindButton: View {
    let kind: OverlayShapeKind
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: iconName)
                    .fontWeight(.semibold)
                    .font(.callout)
                Text(label)
                    .font(.caption2)
                    .fontWeight(.medium)
            }
            .frame(width: 68, height: 48)
            .background(
                isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1),
                in: .rect(cornerRadius: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
            .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
    }

    private var iconName: String {
        switch kind {
        case .circle: return "circle"
        case .rectangle: return "rectangle"
        case .triangle: return "triangle"
        }
    }

    private var label: String {
        switch kind {
        case .circle: return "Circle"
        case .rectangle: return "Rect"
        case .triangle: return "Triangle"
        }
    }
}

// MARK: - View Extension

extension View {
    func toolOptionRow() -> some View {
        self.padding(.horizontal, 16).padding(.vertical, 12)
    }
}
