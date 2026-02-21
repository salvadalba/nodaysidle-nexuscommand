import AppKit
import os

final class CommandBarPanel: NSPanel {
    private static let logger = Logger(subsystem: "com.nexuscommand", category: "lifecycle")

    override var canBecomeKey: Bool { true }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        // Rounded corners
        if let contentView {
            contentView.wantsLayer = true
            contentView.layer?.cornerRadius = 12
            contentView.layer?.masksToBounds = true
        }

        Self.logger.debug("CommandBarPanel initialized")
    }

    func centerOnScreen() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let screenFrame = screen.visibleFrame
        let panelFrame = frame

        let x = screenFrame.midX - panelFrame.width / 2
        let y = screenFrame.midY + screenFrame.height * 0.15  // Upper third of screen

        setFrameOrigin(NSPoint(x: x, y: y))
    }
}
