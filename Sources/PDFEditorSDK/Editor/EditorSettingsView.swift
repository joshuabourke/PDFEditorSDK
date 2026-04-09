//
//  EditorSettingsView.swift
//  PDFEditorSDK
//

import SwiftUI

// MARK: - Editor Settings View

/// A popover panel that lets the user configure annotation input behaviour.
/// Presented from a settings button in both the PDF and Image editor toolbars.
struct EditorSettingsView: View {
    @Binding var drawWithFinger: Bool
    @Binding var pencilOnlyAnnotations: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Input Settings")
                .font(.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)

            Divider()

            // MARK: Pencil Only
            Toggle(isOn: $pencilOnlyAnnotations) {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Pencil Only", systemImage: "pencil.tip")
                        .fontWeight(.medium)
                    Text("Finger navigates freely. Apple Pencil annotates.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: pencilOnlyAnnotations) { _, newValue in
                // Pencil-only and draw-with-finger are mutually exclusive
                if newValue { drawWithFinger = false }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // MARK: Draw with Finger
            Toggle(isOn: $drawWithFinger) {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Draw with Finger", systemImage: "hand.draw")
                        .fontWeight(.medium)
                    Text("Single finger draws. Two fingers navigate.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: drawWithFinger) { _, newValue in
                if newValue { pencilOnlyAnnotations = false }
            }
            .disabled(pencilOnlyAnnotations)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 300)
        .padding(.bottom, 4)
    }
}
