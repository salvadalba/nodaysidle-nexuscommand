import AppKit
import SwiftData
import os

@MainActor @Observable
final class ServiceContainer {
    private static let logger = Logger(subsystem: "com.nexuscommand", category: "lifecycle")

    let hotkeyService: HotkeyService
    let intentParsingService: IntentParsingService
    let fileSearchService: FileSearchService
    let systemActionService: SystemActionService
    let indexingService: IndexingService
    let commandHistoryService: CommandHistoryService
    let shaderService: ShaderService

    // View models
    let commandBarViewModel: CommandBarViewModel
    let menuBarViewModel: MenuBarViewModel
    let settingsViewModel: SettingsViewModel

    // Window controller
    private(set) var commandBarController: CommandBarWindowController!

    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer

        // Create actors
        let indexingActor = IndexingActor(modelContainer: modelContainer)
        let historyActor = HistoryActor(modelContainer: modelContainer)

        // Create services
        hotkeyService = HotkeyService()
        intentParsingService = IntentParsingService()
        fileSearchService = FileSearchService(indexingActor: indexingActor)
        systemActionService = SystemActionService()
        indexingService = IndexingService(indexingActor: indexingActor)
        commandHistoryService = CommandHistoryService(historyActor: historyActor)
        shaderService = ShaderService()

        // Create view models
        commandBarViewModel = CommandBarViewModel()
        menuBarViewModel = MenuBarViewModel()
        settingsViewModel = SettingsViewModel()

        // Wire up dependencies
        commandBarViewModel.configure(
            intentService: intentParsingService,
            searchService: fileSearchService,
            actionService: systemActionService,
            historyService: commandHistoryService
        )

        menuBarViewModel.configure(
            historyService: commandHistoryService,
            indexingService: indexingService
        )

        settingsViewModel.configure(
            modelContext: modelContainer.mainContext,
            hotkeyService: hotkeyService,
            indexingService: indexingService
        )

        // Wire file events to search cache invalidation
        indexingService.onFileEvent = { [weak self] in
            self?.fileSearchService.invalidateCache()
        }

        // Create window controller
        commandBarController = CommandBarWindowController(
            viewModel: commandBarViewModel,
            shaderService: shaderService
        )

        Self.logger.info("ServiceContainer initialized")
    }

    // MARK: - App Launch Sequence

    func performLaunchSequence() async {
        Self.logger.info("Starting launch sequence")

        // 1. Initialize Metal shaders
        shaderService.initialize()

        // 2. Warm up CoreML model
        await intentParsingService.warmup()

        // 3. Register global hotkey
        registerHotkey()

        // 4. Check store health and start monitoring
        let healthy = await indexingService.checkStoreHealth()
        if !healthy {
            Self.logger.fault("SwiftData store corrupted, triggering re-index")
            menuBarViewModel.criticalError = "File index corrupted. Repair in progress."
        }

        // 5. Start FSEvents monitoring
        let paths = settingsViewModel.indexingPaths.compactMap { path -> URL? in
            let expanded = NSString(string: path).expandingTildeInPath
            return URL(fileURLWithPath: expanded, isDirectory: true)
        }
        indexingService.startMonitoring(paths: paths)

        // 6. Trigger initial index if needed
        if !healthy || indexingService.totalRecordCount == 0 {
            await indexingService.startIndexing(paths: paths)
        }

        // 7. Prune expired history
        await commandHistoryService.pruneExpired()

        // 8. Start metrics timer
        startMetricsCollection()

        Self.logger.info("Launch sequence complete")
    }

    // MARK: - Hotkey

    private func registerHotkey() {
        let combo = HotkeyCombo(
            keyCode: UInt16(settingsViewModel.hotkeyKeyCode),
            modifiers: UInt(settingsViewModel.hotkeyModifiers)
        )

        do {
            try hotkeyService.register(hotkey: combo) { [weak self] in
                Task { @MainActor in
                    self?.commandBarController.toggle()
                }
            }
        } catch {
            Self.logger.error("Failed to register hotkey: \(error.localizedDescription)")
        }
    }

    // MARK: - Ensure Default Preferences

    func ensureDefaultPreferences() {
        let context = modelContainer.mainContext
        do {
            var descriptor = FetchDescriptor<UserPreferenceRecord>()
            descriptor.fetchLimit = 1
            if try context.fetch(descriptor).isEmpty {
                context.insert(UserPreferenceRecord())
                try context.save()
                Self.logger.info("Default preferences created")
            }
        } catch {
            Self.logger.error("Failed to ensure default preferences: \(error.localizedDescription)")
        }
    }

    // MARK: - Metrics

    private func startMetricsCollection() {
        let logger = Logger(subsystem: "com.nexuscommand", category: "metrics")

        Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))

                // Memory footprint
                var info = mach_task_basic_info()
                var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
                let result = withUnsafeMutablePointer(to: &info) {
                    $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                        task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
                    }
                }

                if result == KERN_SUCCESS {
                    let mb = Double(info.resident_size) / 1_048_576.0
                    logger.info("memory_footprint_mb: \(mb, format: .fixed(precision: 1))")
                }

                // Cache hit rate
                let hitRate = fileSearchService.cacheHitRate
                logger.info("cache_hit_rate: \(hitRate, format: .fixed(precision: 2))")

                // Index count
                let indexCount = indexingService.totalRecordCount
                logger.info("index_total_records: \(indexCount)")
            }
        }
    }
}
