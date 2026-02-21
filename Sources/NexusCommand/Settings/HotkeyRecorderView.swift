import AppKit
import SwiftUI

struct HotkeyRecorderView: View {
    @Binding var keyCode: Int
    @Binding var modifiers: Int
    @State private var isRecording = false
    @State private var displayText = ""

    var body: some View {
        Button(action: { isRecording.toggle() }) {
            Text(isRecording ? "Press keys..." : currentDisplayString)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isRecording ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isRecording ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .background(
            HotkeyRecorderRepresentable(
                isRecording: $isRecording,
                keyCode: $keyCode,
                modifiers: $modifiers
            )
            .frame(width: 0, height: 0)
        )
        .onAppear {
            updateDisplayText()
        }
        .onChange(of: keyCode) { _, _ in updateDisplayText() }
        .onChange(of: modifiers) { _, _ in updateDisplayText() }
    }

    private var currentDisplayString: String {
        displayText.isEmpty ? "Click to record" : displayText
    }

    private func updateDisplayText() {
        let combo = HotkeyCombo(keyCode: UInt16(keyCode), modifiers: UInt(modifiers))
        displayText = combo.displayString
    }
}

// MARK: - NSView for Key Capture

struct HotkeyRecorderRepresentable: NSViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var keyCode: Int
    @Binding var modifiers: Int

    func makeNSView(context: Context) -> HotkeyCapturerView {
        let view = HotkeyCapturerView()
        view.onKeyCapture = { code, mods in
            self.keyCode = Int(code)
            self.modifiers = Int(mods.rawValue)
            self.isRecording = false
        }
        return view
    }

    func updateNSView(_ nsView: HotkeyCapturerView, context: Context) {
        nsView.isCapturing = isRecording
    }
}

final class HotkeyCapturerView: NSView {
    var isCapturing = false
    var onKeyCapture: ((UInt16, NSEvent.ModifierFlags) -> Void)?

    private var monitor: Any?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isCapturing else {
            super.keyDown(with: event)
            return
        }

        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !mods.isEmpty else { return } // Require at least one modifier

        onKeyCapture?(event.keyCode, mods)
    }
}
