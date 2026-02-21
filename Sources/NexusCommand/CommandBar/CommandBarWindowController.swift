import AppKit
import SwiftUI
import os

@MainActor
final class CommandBarWindowController {
    private static let logger = Logger(subsystem: "com.nexuscommand", category: "lifecycle")
    private static let signposter = OSSignposter(subsystem: "com.nexuscommand", category: "hotkey")

    private var panel: CommandBarPanel?
    private let viewModel: CommandBarViewModel
    private let shaderService: ShaderService
    private var commandBarWidth: CGFloat = 680

    var isVisible: Bool { panel?.isVisible ?? false }

    init(viewModel: CommandBarViewModel, shaderService: ShaderService) {
        self.viewModel = viewModel
        self.shaderService = shaderService
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        let signpostID = Self.signposter.makeSignpostID()
        let state = Self.signposter.beginInterval("HotkeyActivation", id: signpostID)

        if panel == nil {
            createPanel()
        }

        guard let panel else { return }

        panel.centerOnScreen()
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()

        // Focus the text field
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            panel.makeFirstResponder(panel.contentView)
        }

        Self.signposter.endInterval("HotkeyActivation", state)
        Self.logger.info("Command bar shown")
    }

    func hide() {
        panel?.orderOut(nil)
        viewModel.clearState()
        Self.logger.info("Command bar hidden")
    }

    func updateWidth(_ width: CGFloat) {
        commandBarWidth = width
        if let panel {
            var frame = panel.frame
            frame.size.width = width
            panel.setFrame(frame, display: true)
            panel.centerOnScreen()
        }
    }

    // MARK: - Private

    private func createPanel() {
        let panelRect = NSRect(x: 0, y: 0, width: commandBarWidth, height: 420)
        let newPanel = CommandBarPanel(contentRect: panelRect)

        let commandBarView = CommandBarView(viewModel: viewModel, shaderService: shaderService) {
            self.hide()
        }

        let hostingView = NSHostingView(rootView: commandBarView)
        hostingView.frame = panelRect
        newPanel.contentView = hostingView

        self.panel = newPanel
    }
}
