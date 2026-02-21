import AppKit
import SwiftUI

struct NexusMenuBarExtra: View {
    @Bindable var viewModel: MenuBarViewModel
    var onOpenCommandBar: () -> Void
    var onOpenSettings: () -> Void
    var onQuit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Open Command Bar
            Button(action: onOpenCommandBar) {
                Label("Open Command Bar", systemImage: "command.square.fill")
            }
            .keyboardShortcut("o", modifiers: .command)

            Divider()

            // Recent Commands
            if viewModel.recentCommands.isEmpty {
                Text("No recent commands")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .padding(.vertical, 4)
            } else {
                ForEach(viewModel.recentCommands, id: \.id) { record in
                    Button(record.query) {
                        onOpenCommandBar()
                    }
                }
            }

            Divider()

            // Indexing Status
            if viewModel.isIndexing {
                HStack {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Indexing files...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                Divider()
            } else if viewModel.indexedFileCount > 0 {
                Text("\(viewModel.indexedFileCount) files indexed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)

                Divider()
            }

            // Non-recoverable error banner
            if let criticalError = viewModel.criticalError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(criticalError)
                        .font(.caption)
                }
                .padding(.vertical, 4)

                Button("Repair") {
                    viewModel.triggerRepair()
                }

                Divider()
            }

            // Settings
            Button(action: onOpenSettings) {
                Label("Settings...", systemImage: "gearshape")
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            // Quit
            Button("Quit NexusCommand") {
                onQuit()
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}

// MARK: - Menu Bar View Model

@MainActor @Observable
final class MenuBarViewModel {
    var recentCommands: [CommandHistoryDTO] = []
    var isIndexing: Bool = false
    var indexedFileCount: Int = 0
    var criticalError: String?

    private var historyService: CommandHistoryService?
    private var indexingService: IndexingService?

    func configure(historyService: CommandHistoryService, indexingService: IndexingService) {
        self.historyService = historyService
        self.indexingService = indexingService
    }

    func refresh() async {
        if let historyService {
            recentCommands = await historyService.frequentCommands(limit: 5)
        }
        if let indexingService {
            isIndexing = indexingService.indexStatus == .indexing
            indexedFileCount = indexingService.totalRecordCount
        }
    }

    func triggerRepair() {
        criticalError = nil
        // Trigger re-index via indexing service
        Task {
            if let indexingService, let prefs = loadDefaultPaths() {
                await indexingService.startIndexing(paths: prefs)
            }
        }
    }

    private func loadDefaultPaths() -> [URL]? {
        let defaults = ["~/Documents", "~/Desktop", "~/Downloads", "/Applications"]
        return defaults.compactMap { path in
            let expanded = NSString(string: path).expandingTildeInPath
            return URL(fileURLWithPath: expanded, isDirectory: true)
        }
    }
}
