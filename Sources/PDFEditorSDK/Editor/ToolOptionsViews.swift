//
//  ToolOptionsViews.swift
//  PDFEditorSDK
//

import SwiftUI
import UIKit

// MARK: - Draw Tool Options

struct DrawToolOptionsView: View {
    @Binding var inkColor: Color
    @Binding var inkLineWidth: CGFloat

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

            VStack(alignment: .leading, spacing: 8) {
                Text("Line Width")
                    .font(.caption)
                    .fontWeight(.semibold)
                SegmentedOptionRow(
                    options: [(1.0, "1pt"), (3.0, "3pt"), (6.0, "6pt")],
                    selected: $inkLineWidth
                )
            }
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

    var body: some View {
        ToolOptionsContainer(title: "Text Settings") {
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
        }
    }
}

// MARK: - Shape Tool Options

struct ShapeToolOptionsView: View {
    @Binding var shapeKind: OverlayShapeKind
    @Binding var strokeColor: Color
    @Binding var lineWidth: CGFloat

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

            VStack(alignment: .leading, spacing: 8) {
                Text("Line Width")
                    .font(.caption)
                    .fontWeight(.semibold)
                SegmentedOptionRow(
                    options: [(1.0, "1pt"), (2.0, "2pt"), (4.0, "4pt"), (6.0, "6pt")],
                    selected: $lineWidth
                )
            }
            .toolOptionRow()
        }
    }
}

// MARK: - Image Border Defaults (toolbar long-press popover)

struct ImageBorderToolOptionsView: View {
    @Binding var borderWidth: CGFloat
    @Binding var borderColor: Color

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

            VStack(alignment: .leading, spacing: 8) {
                Text("Default width")
                    .font(.caption)
                    .fontWeight(.semibold)
                SegmentedOptionRow(
                    options: [(0.0, "None"), (1.0, "1pt"), (2.0, "2pt"), (4.0, "4pt"), (6.0, "6pt")],
                    selected: $borderWidth
                )
            }
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
