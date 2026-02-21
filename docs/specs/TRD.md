# Technical Requirements Document

## 🧭 System Context
Nexus Command is a single-process native macOS 15+ (Sequoia) command center for Apple Silicon. Global hotkey activates a translucent SwiftUI 6 command bar overlay with on-device CoreML + NaturalLanguage intent parsing, SwiftData-backed local file metadata search, and system action execution. Zero cloud dependency for core paths. Sub-10ms P95 query latency target. Layered architecture: UI Layer (SwiftUI 6 + Metal shaders), Service Layer (Swift 6 Structured Concurrency), Data Layer (SwiftData local SQLite), optional Sync Layer (CloudKit for user settings only). Distributed as signed/notarized .dmg and optionally Mac App Store.

## 🔌 API Contracts
### IntentParsingService.parse
- **Method:** async throws
- **Path:** IntentParsingService.parse(query: String) async throws -> IntentChain
- **Auth:** none — in-process call
- **Request:** query: String — raw user input from command bar (max 500 chars, control characters stripped)
- **Response:** IntentChain { intents: [ParsedIntent], confidence: Float, rawTokens: [String] }. ParsedIntent { action: IntentAction (enum: openFile, launchApp, runShellCommand, systemPreference, webSearch, calculate), parameters: [String: String], confidence: Float }
- **Errors:** ModelNotLoaded — CoreML model failed to initialize on startup, ParsingTimeout — inference exceeded 10ms budget, EmptyQuery — input was empty or whitespace-only

### IntentParsingService.warmup
- **Method:** async
- **Path:** IntentParsingService.warmup() async
- **Auth:** none — called at app launch
- **Request:** none — preloads CoreML model into memory
- **Response:** Void — model ready for inference. Sets modelStatus to .loaded
- **Errors:** ModelNotFound — .mlmodelc bundle missing from app resources, ModelCompilationFailed — CoreML could not compile model for this hardware

### FileSearchService.search
- **Method:** async throws
- **Path:** FileSearchService.search(query: String, filters: SearchFilters?) async throws -> [FileSearchResult]
- **Auth:** none — in-process call
- **Request:** query: String — search terms. filters: SearchFilters? { fileTypes: [UTType]?, modifiedAfter: Date?, modifiedBefore: Date?, maxResults: Int = 20 }
- **Response:** [FileSearchResult] { path: String, fileName: String, fileType: UTType, lastModified: Date, contentSnippet: String?, relevanceScore: Float } — sorted by relevanceScore descending, capped at maxResults
- **Errors:** IndexNotReady — SwiftData index still building on first launch, InvalidPredicate — query produced malformed SwiftData predicate

### FileSearchService.recentFiles
- **Method:** async
- **Path:** FileSearchService.recentFiles(limit: Int = 10) async -> [FileSearchResult]
- **Auth:** none — in-process call
- **Request:** limit: Int — max recent files to return
- **Response:** [FileSearchResult] — ordered by lastModified descending

### SystemActionService.execute
- **Method:** async throws
- **Path:** SystemActionService.execute(intent: ParsedIntent) async throws -> ActionResult
- **Auth:** Requires entitlements: Full Disk Access for file ops, Accessibility for UI scripting, Automation for AppleEvents
- **Request:** intent: ParsedIntent — resolved intent with action type and parameters
- **Response:** ActionResult { success: Bool, output: String?, openedURL: URL?, launchedApp: String? }
- **Errors:** PermissionDenied — missing entitlement or user denied access, AppNotFound — target application not installed, ShellCommandFailed — non-zero exit code with stderr, UnsupportedAction — unrecognized IntentAction, CommandNotAllowed — shell command not in allowlist and user declined confirmation

### IndexingService.startIndexing
- **Method:** async
- **Path:** IndexingService.startIndexing(paths: [URL]) async
- **Auth:** Requires Full Disk Access entitlement for broad directory crawl
- **Request:** paths: [URL] — root directories to crawl. Progress via IndexingService.progress: AsyncStream<IndexProgress { totalFiles: Int, processedFiles: Int, currentPath: String }>
- **Response:** Void — runs as background TaskGroup. Completion signaled by IndexProgress with processedFiles == totalFiles
- **Errors:** PathNotAccessible — directory cannot be read, IndexCorrupted — SwiftData store inconsistent, auto-triggers re-index

### IndexingService.handleFileEvent
- **Method:** async
- **Path:** IndexingService.handleFileEvent(event: FileSystemEvent) async
- **Auth:** none — triggered by DispatchSource/FSEvents monitor
- **Request:** event: FileSystemEvent { path: URL, eventType: FileEventType (created, modified, deleted, renamed) }
- **Response:** Void — SwiftData index updated incrementally within 50ms target

### HotkeyService.register
- **Method:** sync throws
- **Path:** HotkeyService.register(hotkey: HotkeyCombo, handler: @escaping () -> Void) throws
- **Auth:** Requires Accessibility entitlement for NSEvent global monitoring
- **Request:** hotkey: HotkeyCombo { keyCode: UInt16, modifiers: NSEvent.ModifierFlags }. handler: closure on hotkey press
- **Response:** Void — hotkey active system-wide
- **Errors:** HotkeyConflict — combination already registered by another app, AccessibilityNotGranted — user has not granted Accessibility permission

### CommandHistoryService.record
- **Method:** async
- **Path:** CommandHistoryService.record(query: String, selectedResult: String?, timestamp: Date) async
- **Auth:** none — in-process call
- **Request:** query: String, selectedResult: String? — path of chosen result, timestamp: Date
- **Response:** Void — persisted to SwiftData. If duplicate query exists, increments executionCount

### CommandHistoryService.frequentCommands
- **Method:** async
- **Path:** CommandHistoryService.frequentCommands(limit: Int = 5) async -> [CommandHistoryRecord]
- **Auth:** none — in-process call
- **Request:** limit: Int — max results
- **Response:** [CommandHistoryRecord] — ordered by executionCount descending

## 🧱 Modules
### CommandBarUI
- **Responsibilities:**
- Render translucent command bar overlay using SwiftUI 6 with .ultraThinMaterial on NSPanel
- NSPanel subclass (CommandBarPanel) configured as nonactivating floating panel with no title bar
- matchedGeometryEffect for result item expand/collapse transitions
- PhaseAnimator for result list entrance/exit animations
- TimelineView for animated loading and status indicators
- Keyboard navigation: arrow keys for selection, Enter to execute, Escape to dismiss, Tab for autocomplete
- 50ms debounced query input triggers parallel IntentParsing and FileSearch via TaskGroup
- **Interfaces:**
- CommandBarView: View — main overlay view with TextField, result list, and status bar
- CommandBarViewModel: @Observable — properties: query (String), results ([SearchResultItem]), selectedIndex (Int), isLoading (Bool), errorMessage (String?)
- CommandBarPanel: NSPanel — floating nonactivating panel with custom frame and .ultraThinMaterial background
- CommandBarWindowController: NSWindowController — manages panel show/hide lifecycle, screen positioning
- **Dependencies:**
- IntentParsingService
- FileSearchService
- CommandHistoryService
- ShaderService

### MenuBarModule
- **Responsibilities:**
- Persistent MenuBarExtra with app icon using SF Symbol (command.square.fill)
- Quick access menu: recent commands, indexing status, Settings shortcut, Quit
- Show indexing progress badge when IndexingService is active
- **Interfaces:**
- NexusMenuBarExtra: Scene — MenuBarExtra(content:label:) scene
- MenuBarViewModel: @Observable — recentCommands, indexStatus, isIndexing
- **Dependencies:**
- CommandHistoryService
- IndexingService

### SettingsModule
- **Responsibilities:**
- Settings scene with tabbed NavigationStack: General, Indexing, Appearance
- General tab: hotkey recorder, launch at login toggle, menu bar icon toggle
- Indexing tab: directory picker for index paths, max file count, re-index button with progress
- Appearance tab: color scheme picker (system/light/dark), command bar width slider
- Persist all preferences to SwiftData UserPreferenceRecord singleton
- **Interfaces:**
- SettingsView: View — tabbed settings container
- GeneralSettingsView: View, IndexingSettingsView: View, AppearanceSettingsView: View
- SettingsViewModel: @Observable — reads/writes UserPreferenceRecord via ModelContext
- **Dependencies:**
- HotkeyService
- IndexingService

### IntentParsingService
- **Responsibilities:**
- Load CoreML .mlmodelc bundle on warmup() — target 200-500ms load time
- Tokenize query via NLTokenizer with .word unit
- Run CoreML prediction to classify IntentAction and extract parameter slots
- Chain intents from compound queries by splitting on conjunctions (and, then, also)
- LRU cache (capacity: 50) for recent parse results keyed by normalized query string
- **Interfaces:**
- parse(query: String) async throws -> IntentChain
- warmup() async
- modelStatus: ModelStatus { loaded, loading, failed }

### FileSearchService
- **Responsibilities:**
- Build SwiftData FetchDescriptor with compiled predicates for text and attribute search
- Full-text match on indexed fileName and contentSnippet properties
- Attribute filters: UTType, modification date range
- Relevance scoring: weighted combination of text match rank (0.7) and recency (0.3)
- LRU result cache (capacity: 100) invalidated on any IndexingService file event
- **Interfaces:**
- search(query: String, filters: SearchFilters?) async throws -> [FileSearchResult]
- recentFiles(limit: Int) async -> [FileSearchResult]
- invalidateCache() — called by IndexingService on file events
- **Dependencies:**
- IndexingService

### SystemActionService
- **Responsibilities:**
- Map IntentAction enum cases to macOS system operations
- openFile/launchApp: NSWorkspace.shared.open(_:)
- runShellCommand: Process with /bin/zsh, stdout/stderr pipe capture, allowlist validation
- systemPreference: URL scheme x-apple.systempreferences:{paneID}
- webSearch: NSWorkspace.shared.open(URL) with default browser
- calculate: NSExpression evaluation for math expressions
- Shell allowlist: [open, defaults, osascript, pbcopy, pbpaste]. Others require user confirmation dialog
- **Interfaces:**
- execute(intent: ParsedIntent) async throws -> ActionResult

### IndexingService
- **Responsibilities:**
- Full directory crawl via FileManager.enumerator with TaskGroup parallelism bounded to activeProcessorCount - 2
- Extract metadata: fileName, filePath, UTType via URL.resourceValues, fileSize, dates, SHA256 contentHash
- Text content preview: first 500 characters for UTType.plainText conforming files
- FSEvents/DispatchSource monitoring for real-time incremental updates
- Write/update/delete FileMetadataRecord in SwiftData on a dedicated background ModelActor
- Publish progress via AsyncStream<IndexProgress>
- **Interfaces:**
- startIndexing(paths: [URL]) async
- stopIndexing()
- handleFileEvent(event: FileSystemEvent) async
- progress: AsyncStream<IndexProgress>
- indexStatus: IndexStatus { idle, indexing, error(String) }
- totalRecordCount: Int

### HotkeyService
- **Responsibilities:**
- Primary: NSEvent.addGlobalMonitorForEvents(matching: .keyDown) for hotkey detection
- Fallback: Carbon RegisterEventHotKey for reliability when NSEvent monitor fails
- Conflict detection: attempt registration and handle kEventHotKeyExistsErr
- Persist hotkey config to UserPreferenceRecord via SettingsModule
- **Interfaces:**
- register(hotkey: HotkeyCombo, handler: @escaping () -> Void) throws
- unregister()
- currentHotkey: HotkeyCombo?

### ShaderService
- **Responsibilities:**
- Compile Metal shaders from .metal files in asset catalog at app launch
- Cache compiled MTLFunction references for reuse
- Provide SwiftUI Shader instances via ShaderLibrary for .visualEffect and .layerEffect modifiers
- Handle MTLDevice unavailability gracefully (fall back to standard SwiftUI materials)
- **Interfaces:**
- blurShader(radius: Float) -> Shader
- glowShader(color: Color, intensity: Float) -> Shader
- transitionShader(progress: Float) -> Shader
- isMetalAvailable: Bool

### CommandHistoryService
- **Responsibilities:**
- Persist query + selected result + timestamp to SwiftData CommandHistoryRecord
- Increment executionCount on duplicate query strings for frequency tracking
- Provide top-N frequent commands for autocomplete suggestions
- Prune records older than historyRetentionDays (from UserPreferenceRecord, default 90)
- **Interfaces:**
- record(query: String, selectedResult: String?, timestamp: Date) async
- frequentCommands(limit: Int) async -> [CommandHistoryRecord]
- searchHistory(containing: String, limit: Int) async -> [CommandHistoryRecord]
- clearHistory() async
- pruneExpired() async

### AppLifecycleModule
- **Responsibilities:**
- SwiftUI App entry point with WindowGroup (hidden), MenuBarExtra, and Settings scenes
- Dependency injection: create service singletons and inject via @Environment
- App launch sequence: warmup CoreML model, register hotkey, start FSEvents monitor, trigger initial index if needed
- Permission onboarding: request Full Disk Access and Accessibility on first launch with explanation dialogs
- **Interfaces:**
- NexusCommandApp: App — @main entry point
- ServiceContainer: @Observable — holds all service instances for @Environment injection
- **Dependencies:**
- IntentParsingService
- FileSearchService
- SystemActionService
- IndexingService
- HotkeyService
- ShaderService
- CommandHistoryService

## 🗃 Data Model Notes
- @Model FileMetadataRecord: id (UUID, .unique), filePath (String, indexed), fileName (String, indexed), fileExtension (String, indexed), fileType (String — UTType.identifier), fileSize (Int64), createdDate (Date), modifiedDate (Date, indexed), contentSnippet (String?, indexed — first 500 chars of text files), contentHash (String — SHA256 hex). No relationships. Flat for fast predicate queries.

- @Model CommandHistoryRecord: id (UUID, .unique), query (String, indexed), selectedResultPath (String?), timestamp (Date, indexed), executionCount (Int, default 1). References FileMetadataRecord by path string only — no formal relationship. executionCount incremented on repeat queries.

- @Model UserPreferenceRecord: Singleton pattern. id (UUID), hotkeyKeyCode (UInt16, default 49/Space), hotkeyModifiers (UInt, default Cmd), indexingPaths ([String], default ~/Documents ~/Desktop ~/Downloads /Applications), maxIndexedFiles (Int, default 500000), historyRetentionDays (Int, default 90), appearanceMode (String, default 'system'), commandBarWidth (Double, default 680.0), showMenuBarIcon (Bool, default true). Fetched with FetchDescriptor limit 1.

- ModelContainer configured with ModelConfiguration(url: appSupportDir/NexusCommand/nexus.store). Schema versioning via VersionedSchema with SchemaMigrationPlan for each release.

- Background SwiftData access via ModelActor subclass (IndexingActor, HistoryActor) to keep main actor free for UI.

- CloudKit sync scope (optional): UserPreferenceRecord only. FileMetadataRecord and CommandHistoryRecord remain strictly local via separate ModelConfiguration with no CloudKit container.

## 🔐 Validation & Security
- App Sandbox enabled. Entitlements: com.apple.security.files.user-selected.read-write (user-chosen folders), com.apple.security.temporary-exception.files.absolute-path.read-only (configurable index paths), com.apple.security.automation.apple-events (osascript)
- Full Disk Access (FDA) requested via onboarding dialog with clear explanation. If denied, IndexingService only crawls user-selected folders. Degraded but functional.
- Accessibility permission for global hotkey. Shows system permission dialog. If denied, hotkey registration fails gracefully — user must use menu bar icon to open command bar.
- Shell command allowlist: ['open', 'defaults', 'osascript', 'pbcopy', 'pbpaste']. Commands outside allowlist show confirmation dialog with full command text before execution. No silent arbitrary command execution.
- Command bar input: max 500 characters enforced in TextField. Control characters stripped. No HTML/script injection surface — SwiftUI Text renders plain strings.
- CoreML model is code-signed inside the app bundle. No runtime model download in v1. Model integrity verified by code signing validation.
- No URLSession import permitted in core service modules (IntentParsingService, FileSearchService, SystemActionService, IndexingService). Enforced by build-time grep check in CI.
- SwiftData SQLite store encrypted at rest via macOS FileVault. No additional app-level encryption required for local data.
- Hardened Runtime enabled. No JIT, no unsigned code, no DYLD environment variables.

## 🧯 Error Handling Strategy
Domain-specific error enums per service conforming to LocalizedError (e.g., IntentError, SearchError, ActionError). UI layer catches all errors and renders inline in command bar as a tinted result row — no modal alerts for recoverable errors. Non-recoverable errors (CoreML model load failure, SwiftData store corruption) log to os.Logger at .fault level and show persistent banner in MenuBarExtra with Repair action triggering re-initialization. All async Tasks cooperate with cancellation — cancelled operations return empty results instead of throwing. SwiftData corruption auto-detected on launch triggers full re-index. No retry loops — fail fast and surface to user. Shell command failures (non-zero exit) captured via stderr pipe and displayed as ActionResult.output.

## 🔭 Observability
- **Logging:** os.Logger with subsystem 'com.nexuscommand'. Per-service categories: 'intent', 'search', 'indexing', 'hotkey', 'action', 'lifecycle'. Levels: .debug for query traces and timing, .info for lifecycle events (launch, index start/complete, hotkey registered), .error for recoverable failures, .fault for non-recoverable state. Sensitive data (file paths, query text) marked with .private in os_log format strings — visible only in debug builds or with sysdiagnose.
- **Tracing:** os_signpost intervals with named categories: QueryPipeline (end-to-end query), MLInference (CoreML), DataQuery (SwiftData), FSIndex (crawl/update), HotkeyActivation (press-to-visible). All viewable in Instruments via os_signpost instrument and Time Profiler. No distributed tracing — single-process architecture. Custom Instruments package (.instrpkg) for Nexus-specific trace visualization.
- **Metrics:**
- query_latency_ms — os_signpost interval from TextField onChange to result list render (P95 target: <10ms)
- intent_parse_ms — os_signpost interval for CoreML inference call (P95 target: <5ms)
- file_search_ms — os_signpost interval for SwiftData fetch (P95 target: <5ms)
- index_total_records — gauge logged on index completion and periodic 60s heartbeat
- index_update_ms — os_signpost interval for single file event processing (P95 target: <50ms)
- hotkey_to_visible_ms — os_signpost interval from hotkey callback to window orderFront (target: <200ms)
- memory_footprint_mb — sampled via task_info every 60s, logged at .info level
- cache_hit_rate — counter for FileSearchService LRU cache hits/misses per 100 queries

## ⚡ Performance Notes
- CoreML model preloaded at launch via IntentParsingService.warmup() — 200-500ms load amortized to startup, not first query
- SwiftData FetchDescriptors pre-compiled with static predicates. Dynamic query parts injected as variables, not string-built predicates
- FileSearchService LRU cache: 100 entry capacity, keyed by (query + filters hash). Invalidated wholesale on any IndexingService file event notification
- IndexingService TaskGroup concurrency: max(ProcessInfo.activeProcessorCount - 2, 1) to reserve cores for UI and ML
- 50ms debounce on CommandBarViewModel.query via Task.sleep(for: .milliseconds(50)) with cancellation of prior search task
- After debounce, IntentParsingService.parse and FileSearchService.search run in parallel TaskGroup — results merged when both complete
- Metal shaders compiled once at ShaderService init from pre-compiled .metallib in app bundle — zero runtime shader compilation
- NSPanel configured with .nonactivatingPanel behavior and .canJoinAllSpaces — no focus stealing, works across Spaces
- SwiftData background writes via ModelActor — main actor never blocks on index writes or history persistence
- Intel Mac fallback: CoreML automatically uses CPU inference. Parse latency degrades to ~50-100ms. UI remains responsive since inference runs off main actor.

## 🧪 Testing Strategy
### Unit
- IntentParsingServiceTests: parse() returns correct IntentAction for 'open Safari' (launchApp), 'find readme.md' (openFile), 'run ls' (runShellCommand). Compound query 'open Terminal and run pwd' produces 2-intent chain. Empty/whitespace input throws EmptyQuery. Uses mock CoreML model with deterministic MLMultiArray outputs.
- FileSearchServiceTests: search('readme') returns FileSearchResult with fileName containing 'readme'. Date range filter excludes old files. fileType filter returns only matching UTTypes. Results sorted by relevanceScore. maxResults caps output. Uses in-memory ModelContainer with seeded FileMetadataRecords.
- SystemActionServiceTests: execute(launchApp 'Safari') calls NSWorkspace.open(URL('file:///Applications/Safari.app')). execute(runShellCommand 'open .') passes allowlist. execute(runShellCommand 'rm -rf /') throws CommandNotAllowed. Mock NSWorkspace and Process.
- CommandHistoryServiceTests: record() creates CommandHistoryRecord in SwiftData. Second record() with same query increments executionCount. frequentCommands(3) returns top 3 by executionCount desc. pruneExpired() removes records older than 90 days. In-memory ModelContainer.
- HotkeyServiceTests: register(Cmd+Space) succeeds. register(already-taken) throws HotkeyConflict. unregister() clears currentHotkey. Mock NSEvent monitor and Carbon API.
- IndexingServiceTests: startIndexing on temp directory with 10 files creates 10 FileMetadataRecords. handleFileEvent(.created) adds record. handleFileEvent(.deleted) removes record. handleFileEvent(.modified) updates contentHash. Temp directory + in-memory ModelContainer.
### Integration
- QueryPipelineTest: seed SwiftData with 100 FileMetadataRecords. Parse 'find document.pdf' via real CoreML model. Verify FileSearchService returns matching record. Assert end-to-end latency under 10ms on Apple Silicon via os_signpost measurement.
- IndexingPipelineTest: create temp directory tree (3 levels, 50 files). Run startIndexing(). Verify 50 FileMetadataRecords in SwiftData with correct metadata. Modify one file, call handleFileEvent(.modified), verify updated contentHash. Delete one file, verify record removed.
- HistoryIntegrationTest: perform 5 queries via CommandBarViewModel. Verify CommandHistoryRecords created. Open command bar again, verify frequentCommands appear as autocomplete suggestions.
### E2E
- CommandBarActivationE2E (XCUITest): launch app, simulate Cmd+Space hotkey, assert command bar window visible within 200ms. Type 'Safari', assert result list contains Safari.app. Press Enter, assert Safari launches. Press Escape, assert command bar dismisses.
- SettingsE2E (XCUITest): open Settings via menu bar, navigate to General tab. Record new hotkey (Cmd+Shift+Space). Dismiss Settings. Simulate new hotkey, assert command bar appears. Navigate to Indexing tab, add temp folder, tap Re-index, assert progress indicator shown.
- ColdStartE2E: terminate and relaunch app. Measure time from launch to command bar responsiveness (hotkey works + first query returns results). Assert under 3 seconds. Verify CoreML model loaded (parse returns valid IntentChain) and SwiftData index accessible.

## 🚀 Rollout Plan
- Phase 1 — App Shell (2 weeks): @main App with hidden WindowGroup, MenuBarExtra, Settings scene. NSPanel-based CommandBarPanel with .ultraThinMaterial. HotkeyService with Cmd+Space default. TextField + static placeholder results. Keyboard navigation (arrows, Enter, Escape). Permission onboarding flow for Accessibility.

- Phase 2 — Data Layer (2 weeks): SwiftData schema v1 with FileMetadataRecord, CommandHistoryRecord, UserPreferenceRecord. ModelActor for background writes. IndexingService full crawl with TaskGroup. FSEvents incremental monitor. FileSearchService with predicate search. Validate 500K records and sub-10ms search latency.

- Phase 3 — ML Pipeline (2 weeks): Train intent classification model (distilled NLModel or CoreML neural network). Convert to .mlmodelc. IntentParsingService with NLTokenizer + CoreML prediction. Intent chain splitting for compound queries. LRU parse cache. Verify sub-5ms inference on Neural Engine.

- Phase 4 — System Actions (1 week): SystemActionService for all IntentAction cases. NSWorkspace app launch and file open. Process-based shell execution with allowlist. URL scheme for System Settings panes. NSExpression for calculate. User confirmation dialog for non-allowlisted commands.

- Phase 5 — Visual Polish (1 week): ShaderService with Metal blur, glow, transition shaders. matchedGeometryEffect result transitions. PhaseAnimator entrance/exit. TimelineView loading indicators. CommandHistoryService autocomplete integration. GPU testing across M1/M2/M3/M4.

- Phase 6 — Testing and Profiling (1 week): Full unit test suite. Integration tests with real CoreML model. E2E XCUITests. Instruments profiling: Time Profiler, Allocations (150MB budget), os_signpost latency. Intel Mac degradation testing. Sandbox and entitlement audit.

- Phase 7 — Distribution (1 week): Code signing with Developer ID. Notarization via notarytool. DMG packaging with background image and /Applications alias. CI pipeline: xcodebuild → test → sign → notarize → package. Optional Mac App Store build with reduced entitlements.

## ❓ Open Questions
- CoreML model architecture: NLModel with custom intent classifier vs. converted transformer? Training data source for intent classification (synthetic command templates vs. collected user queries)?
- CloudKit sync: should CommandHistoryRecord sync cross-device or remain strictly local? Privacy implications of syncing query history to iCloud.
- Shell command allowlist expansion: should power users configure custom allowlisted commands via Settings? Risk of user misconfiguration enabling dangerous commands.
- Spotlight supplemental search: should FileSearchService also query CSSearchableIndex for files outside configured indexing paths? Adds coverage but introduces Spotlight dependency.
- CoreML model updates post-v1: app update only (simpler, offline guaranteed) vs. optional background model download (faster iteration, adds network code to core)?
- VoiceOver accessibility: NSPanel requires custom NSAccessibility conformance for command bar. Priority and scope for full screen reader support.
- Mac App Store sandbox restrictions: FDA and global hotkey entitlements may be rejected. Direct .dmg distribution only, or maintain two builds with different capability levels?