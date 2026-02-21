import SwiftUI
import SwiftData
import os

@main
struct NexusCommandApp: App {
    private static let logger = Logger(subsystem: "com.nexuscommand", category: "lifecycle")

    @NSApplicationDelegateAdaptor(NexusAppDelegate.self) private var appDelegate

    var body: some Scene {
        // Menu Bar — the only visible scene
        MenuBarExtra("NexusCommand", systemImage: "command.square.fill") {
            if let container = appDelegate.serviceContainer {
                NexusMenuBarExtra(
                    viewModel: container.menuBarViewModel,
                    onOpenCommandBar: {
                        container.commandBarController.show()
                    },
                    onOpenSettings: {
                        NSApp.activate(ignoringOtherApps: true)
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    },
                    onQuit: {
                        NSApplication.shared.terminate(nil)
                    }
                )
                .task {
                    await container.menuBarViewModel.refresh()
                }
            } else {
                Text("Loading...")
                    .foregroundStyle(.secondary)
            }
        }

        // Settings window
        Settings {
            if let container = appDelegate.serviceContainer {
                SettingsView(viewModel: container.settingsViewModel)
            }
        }
    }
}

// MARK: - App Delegate — drives all startup

@MainActor
final class NexusAppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private static let logger = Logger(subsystem: "com.nexuscommand", category: "lifecycle")

    private(set) var serviceContainer: ServiceContainer?
    private var modelContainer: ModelContainer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.logger.info("Application did finish launching")

        // Hide dock icon — menu bar only
        NSApp.setActivationPolicy(.accessory)

        // Create SwiftData container
        let schema = Schema([
            FileMetadataRecord.self,
            CommandHistoryRecord.self,
            UserPreferenceRecord.self,
        ])

        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let storeDir = appSupportURL.appendingPathComponent("NexusCommand", isDirectory: true)
        let storeURL = storeDir.appendingPathComponent("nexus.store")

        try? FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)

        let config = ModelConfiguration(
            "NexusStore",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )

        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            self.modelContainer = container
            let sc = ServiceContainer(modelContainer: container)
            self.serviceContainer = sc
            Self.logger.info("ServiceContainer created, store at \(storeURL.path())")

            // Run async launch sequence
            Task { @MainActor in
                await self.performLaunchSequence(serviceContainer: sc)
            }
        } catch {
            Self.logger.fault("Failed to create ModelContainer: \(error.localizedDescription)")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        serviceContainer?.indexingService.stopMonitoring()
        Self.logger.info("Application will terminate")
    }

    // MARK: - Launch Sequence

    private func performLaunchSequence(serviceContainer sc: ServiceContainer) async {
        Self.logger.info("Launch sequence starting")

        // 1. Ensure default preferences exist, then reload them into view model
        sc.ensureDefaultPreferences()
        sc.settingsViewModel.loadPreferences()

        // 2. First-launch: request Accessibility permission
        if !UserDefaults.standard.bool(forKey: "onboardingComplete") {
            sc.hotkeyService.requestAccessibility()
            UserDefaults.standard.set(true, forKey: "onboardingComplete")
            Self.logger.info("First launch — requesting Accessibility permission")
        }

        // 3. Full service startup (hotkey, ML warmup, FSEvents, indexing, prune history)
        await sc.performLaunchSequence()

        // 4. Refresh menu bar
        await sc.menuBarViewModel.refresh()

        Self.logger.info("Launch sequence complete")
    }
}
