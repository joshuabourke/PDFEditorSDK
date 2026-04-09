//
//  ToolOptionsViews.swift
//  PDFEditorSDK
//

import SwiftUI

// MARK: - Draw Tool Options

struct DrawToolOptionsView: View {
    @Binding var inkColor: Color
    @Binding var inkLineWidth: CGFloat

    var body: some View {
        ToolOptionsContainer(title: "Draw Settings") {
            HStack {
                Label("Color", systemImage: "paintbrush.tip")
                    .fontWeight(.medium)
                Spacer()
                ColorPicker("", selection: $inkColor)
                    .labelsHidden()
            }
            .toolOptionRow()

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Line Width")
                    .font(.subheadline)
                    .fontWeight(.medium)
                SegmentedOptionRow(
                    options: [(1.0, "Fine"), (3.0, "Medium"), (6.0, "Thick")],
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

    var body: some View {
        ToolOptionsContainer(title: "Text Settings") {
            HStack {
                Label("Text Color", systemImage: "character")
                    .fontWeight(.medium)
                Spacer()
                ColorPicker("", selection: $textColor)
                    .labelsHidden()
            }
            .toolOptionRow()

            Divider()

            HStack {
                Label("Background", systemImage: "rectangle.fill")
                    .fontWeight(.medium)
                Spacer()
                ColorPicker("", selection: $backgroundColor, supportsOpacity: true)
                    .labelsHidden()
            }
            .toolOptionRow()

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Font Size")
                    .font(.subheadline)
                    .fontWeight(.medium)
                SegmentedOptionRow(
                    options: [(12.0, "12pt"), (14.0, "14pt"), (18.0, "18pt"), (22.0, "22pt")],
                    selected: $fontSize
                )
            }
            .toolOptionRow()

            Divider()

            Toggle(isOn: $isBold) {
                Label("Bold", systemImage: "bold")
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
                    .font(.subheadline)
                    .fontWeight(.medium)
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
                Label("Stroke Color", systemImage: "paintbrush.tip")
                    .fontWeight(.medium)
                Spacer()
                ColorPicker("", selection: $strokeColor)
                    .labelsHidden()
            }
            .toolOptionRow()

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Line Width")
                    .font(.subheadline)
                    .fontWeight(.medium)
                SegmentedOptionRow(
                    options: [(1.0, "1pt"), (2.0, "2pt"), (4.0, "4pt"), (6.0, "6pt")],
                    selected: $lineWidth
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
                    .font(.subheadline)
                    .fontWeight(.medium)
                SegmentedOptionRow(
                    options: [(6.0, "Sm"), (9.0, "Md"), (13.0, "Lg"), (18.0, "XL"), (24.0, "XXL")],
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
        HStack(spacing: 6) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, pair in
                Button(pair.1) {
                    selected = pair.0
                }
                .buttonStyle(.plain)
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
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
                    .font(.title3)
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .frame(width: 72, height: 52)
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
