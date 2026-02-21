import AppKit
import SwiftData
import ServiceManagement
import os

@MainActor @Observable
final class SettingsViewModel {
    private static let logger = Logger(subsystem: "com.nexuscommand", category: "settings")

    // General
    var hotkeyKeyCode: Int = 49
    var hotkeyModifiers: Int = 256
    var launchAtLogin: Bool = false {
        didSet { updateLaunchAtLogin() }
    }
    var showMenuBarIcon: Bool = true
    var hotkeyError: String?

    // Indexing
    var indexingPaths: [String] = []
    var maxIndexedFiles: Int = 500_000
    var isReIndexing: Bool = false

    // Appearance
    var appearanceMode: String = "system"
    var commandBarWidth: Double = 680.0

    private var modelContext: ModelContext?
    private var hotkeyService: HotkeyService?
    private var indexingService: IndexingService?

    func configure(
        modelContext: ModelContext,
        hotkeyService: HotkeyService,
        indexingService: IndexingService
    ) {
        self.modelContext = modelContext
        self.hotkeyService = hotkeyService
        self.indexingService = indexingService
        loadPreferences()
    }

    func loadPreferences() {
        guard let modelContext else { return }
        do {
            var descriptor = FetchDescriptor<UserPreferenceRecord>()
            descriptor.fetchLimit = 1
            if let prefs = try modelContext.fetch(descriptor).first {
                hotkeyKeyCode = prefs.hotkeyKeyCode
                hotkeyModifiers = prefs.hotkeyModifiers
                indexingPaths = prefs.indexingPaths
                maxIndexedFiles = prefs.maxIndexedFiles
                appearanceMode = prefs.appearanceMode
                commandBarWidth = prefs.commandBarWidth
                showMenuBarIcon = prefs.showMenuBarIcon
            }
        } catch {
            Self.logger.error("Failed to load preferences: \(error.localizedDescription)")
        }
    }

    func savePreferences() {
        guard let modelContext else { return }
        do {
            var descriptor = FetchDescriptor<UserPreferenceRecord>()
            descriptor.fetchLimit = 1
            let prefs = try modelContext.fetch(descriptor).first ?? UserPreferenceRecord()

            prefs.hotkeyKeyCode = hotkeyKeyCode
            prefs.hotkeyModifiers = hotkeyModifiers
            prefs.indexingPaths = indexingPaths
            prefs.maxIndexedFiles = maxIndexedFiles
            prefs.appearanceMode = appearanceMode
            prefs.commandBarWidth = commandBarWidth
            prefs.showMenuBarIcon = showMenuBarIcon

            if prefs.modelContext == nil {
                modelContext.insert(prefs)
            }
            try modelContext.save()
            Self.logger.info("Preferences saved")
        } catch {
            Self.logger.error("Failed to save preferences: \(error.localizedDescription)")
        }
    }

    func addDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a directory to index"

        if panel.runModal() == .OK, let url = panel.url {
            let path = url.path(percentEncoded: false)
            if !indexingPaths.contains(path) {
                indexingPaths.append(path)
                savePreferences()
            }
        }
    }

    func removePath(_ path: String) {
        indexingPaths.removeAll { $0 == path }
        savePreferences()
    }

    func triggerReIndex() {
        guard let indexingService else { return }
        isReIndexing = true

        let urls = indexingPaths.compactMap { path -> URL? in
            let expanded = NSString(string: path).expandingTildeInPath
            return URL(fileURLWithPath: expanded, isDirectory: true)
        }

        Task {
            await indexingService.startIndexing(paths: urls)
            isReIndexing = false
        }
    }

    private func updateLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Self.logger.error("Failed to update launch at login: \(error.localizedDescription)")
        }
    }
}
