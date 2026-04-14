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
    @Binding var pencilDoubleTapAction: PencilGestureAction
    @Binding var pencilSqueezeAction: PencilGestureAction
    @Binding var pencilDoubleSqueezeAction: PencilGestureAction

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // MARK: - Input Mode

                Text("Input Mode")
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                Divider()

                // Pencil Only
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
                    if newValue { drawWithFinger = false }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()

                // Draw with Finger
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

                // MARK: - Pencil Gestures

                Divider()

                Text("Pencil Gestures")
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                Divider()

                // Double Tap
                GesturePickerRow(
                    label: "Double Tap",
                    icon: "hand.tap",
                    subtitle: "Apple Pencil 2 and Apple Pencil Pro.",
                    selection: $pencilDoubleTapAction,
                    otherSelections: [pencilSqueezeAction, pencilDoubleSqueezeAction]
                )
                .onChange(of: pencilDoubleTapAction) { _, newValue in
                    clearConflictsForDoubleTap(newValue)
                }

                Divider()

                // Single Squeeze
                GesturePickerRow(
                    label: "Single Squeeze",
                    icon: "hand.point.up.left",
                    subtitle: "Apple Pencil Pro only.",
                    selection: $pencilSqueezeAction,
                    otherSelections: [pencilDoubleTapAction, pencilDoubleSqueezeAction]
                )
                .onChange(of: pencilSqueezeAction) { _, newValue in
                    clearConflictsForSqueeze(newValue)
                }

                Divider()

                // Double Squeeze
                GesturePickerRow(
                    label: "Double Squeeze",
                    icon: "hand.point.up.left.fill",
                    subtitle: "Apple Pencil Pro only.",
                    selection: $pencilDoubleSqueezeAction,
                    otherSelections: [pencilDoubleTapAction, pencilSqueezeAction]
                )
                .onChange(of: pencilDoubleSqueezeAction) { _, newValue in
                    clearConflictsForDoubleSqueeze(newValue)
                }
            }
        }
        .frame(width: 300)
        .frame(maxHeight: 560)
    }

    // MARK: - Conflict Resolution

    /// When a gesture is set to an exclusive action, automatically clear the same
    /// action from the other two gestures so no two map to the same thing.
    private func clearConflictsForDoubleTap(_ newValue: PencilGestureAction) {
        guard newValue.isExclusive else { return }
        if pencilSqueezeAction       == newValue { pencilSqueezeAction       = .noAction }
        if pencilDoubleSqueezeAction == newValue { pencilDoubleSqueezeAction = .noAction }
    }

    private func clearConflictsForSqueeze(_ newValue: PencilGestureAction) {
        guard newValue.isExclusive else { return }
        if pencilDoubleTapAction     == newValue { pencilDoubleTapAction     = .noAction }
        if pencilDoubleSqueezeAction == newValue { pencilDoubleSqueezeAction = .noAction }
    }

    private func clearConflictsForDoubleSqueeze(_ newValue: PencilGestureAction) {
        guard newValue.isExclusive else { return }
        if pencilDoubleTapAction == newValue { pencilDoubleTapAction = .noAction }
        if pencilSqueezeAction   == newValue { pencilSqueezeAction   = .noAction }
    }
}

// MARK: - Gesture Picker Row

/// A self-contained row showing a gesture label + subtitle + action menu picker.
/// Options already assigned to other gestures are marked with a checkmark on
/// those gestures and shown dimmed in this picker, guiding the user toward
/// conflict-free selections.
private struct GesturePickerRow: View {
    let label: String
    let icon: String
    let subtitle: String
    @Binding var selection: PencilGestureAction
    /// Actions currently assigned to the other two gestures (for visual feedback).
    let otherSelections: [PencilGestureAction]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(label, systemImage: icon)
                .fontWeight(.medium)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)

        Picker(label, selection: $selection) {
            ForEach(PencilGestureAction.allCases) { action in
                let takenByOther = action.isExclusive && otherSelections.contains(action)
                Label(
                    takenByOther ? "\(action.displayName) (in use)" : action.displayName,
                    systemImage: action.systemImage
                )
                .foregroundStyle(takenByOther ? .secondary : .primary)
                .tag(action)
            }
        }
        .pickerStyle(.menu)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}
