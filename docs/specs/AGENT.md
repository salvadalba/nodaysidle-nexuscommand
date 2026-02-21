# Agent Prompts — NexusCommand

## Global Rules

### Do
- Use SwiftUI 6 with @Observable, SwiftData, CoreML, Metal shaders, and Structured Concurrency exclusively
- Target macOS 15+ (Sequoia) with Apple Silicon optimization throughout
- Use os.Logger with subsystem 'com.nexuscommand' and os_signpost for all performance tracing
- Keep all data local-first — no server, no URLSession in core modules
- Conform all shared types to Sendable for Swift 6 concurrency safety

### Don't
- Do not introduce any server-side code, REST APIs, or URLSession in core service modules
- Do not use ObservableObject/@Published — use @Observable from Observation framework only
- Do not use MLX, third-party ML frameworks, or any dependency outside Apple SDKs
- Do not target macOS versions below 15 or support Intel-specific codepaths in core logic
- Do not use modal alert dialogs for recoverable errors — use inline tinted result rows only

---

## Task Prompts
### Task 1: App Shell, Window Infrastructure & Menu Bar

**Role:** Expert macOS AppKit/SwiftUI Engineer
**Goal:** Build the app entry point, floating NSPanel command bar with keyboard nav, global hotkey service, MenuBarExtra, and permission onboarding flow.

**Context**
Establish the foundational macOS app with hidden WindowGroup, NSPanel-based floating command bar, global hotkey activation, MenuBarExtra, keyboard navigation, and first-launch permission onboarding. This is the skeleton that all other features plug into.

**Files to Create**
- NexusCommand/App/NexusCommandApp.swift
- NexusCommand/App/ServiceContainer.swift
- NexusCommand/CommandBar/CommandBarPanel.swift
- NexusCommand/CommandBar/CommandBarWindowController.swift
- NexusCommand/CommandBar/CommandBarView.swift
- NexusCommand/CommandBar/CommandBarViewModel.swift
- NexusCommand/Services/HotkeyService.swift
- NexusCommand/MenuBar/NexusMenuBarExtra.swift

**Files to Modify**
_None_

**Steps**
1. Create NexusCommandApp.swift with @main, hidden WindowGroup, MenuBarExtra scene using command.square.fill SF Symbol, and Settings scene placeholder. Initialize ModelContainer with ModelConfiguration pointing to appSupportDir/NexusCommand/nexus.store. Set LSUIElement behavior so app appears only in menu bar.
2. Implement CommandBarPanel as NSPanel subclass with .nonactivatingPanel behavior, .canJoinAllSpaces collection behavior, no title bar, and .ultraThinMaterial background. Create CommandBarWindowController managing show/hide lifecycle, centering panel horizontally on the active screen. Wire NSHostingView to embed CommandBarView.
3. Build CommandBarView with styled TextField bound to CommandBarViewModel.query, scrollable result list rendering placeholder items, and selectedIndex-based row highlighting. Set 680pt width with rounded corners. Add keyboard handling: arrow up/down for selectedIndex, Enter to execute, Escape to dismiss, Tab captured for future autocomplete. Use .onKeyPress or NSEvent local monitor.
4. Implement HotkeyService using NSEvent.addGlobalMonitorForEvents(matching: .keyDown) with Carbon RegisterEventHotKey fallback. Default Cmd+Space. Detect conflicts via kEventHotKeyExistsErr. Expose currentHotkey, register(), unregister(). Wire hotkey callback to CommandBarWindowController toggle — focus TextField on show, clear query/results on hide. Log hotkey_to_visible_ms via os_signpost.
5. Build first-launch onboarding: present Accessibility permission request (for global hotkey) and Full Disk Access request (for file indexing) with explanation dialogs. Graceful fallback if denied. Persist onboarding-complete flag to UserDefaults. Implement MenuBarExtra with Open Command Bar, recent commands placeholder, Settings shortcut, and Quit items via MenuBarViewModel.

**Validation**
`xcodebuild -scheme NexusCommand -destination 'platform=macOS' build 2>&1 | tail -5`

---

### Task 2: SwiftData Schema, Indexing & File Search Services

**Role:** Expert Swift Data Persistence & File Systems Engineer
**Goal:** Create SwiftData models, background indexing with FSEvents, and fast file search with relevance scoring and LRU cache.

**Context**
Define all SwiftData models, build the background file indexing pipeline with FSEvents monitoring, and implement the file search service with relevance scoring and LRU caching. This provides the local-first data layer that powers query results.

**Files to Create**
- NexusCommand/Models/FileMetadataRecord.swift
- NexusCommand/Models/CommandHistoryRecord.swift
- NexusCommand/Models/UserPreferenceRecord.swift
- NexusCommand/Services/IndexingActor.swift
- NexusCommand/Services/HistoryActor.swift
- NexusCommand/Services/IndexingService.swift
- NexusCommand/Services/FileSearchService.swift
- NexusCommand/Services/CommandHistoryService.swift

**Files to Modify**
- NexusCommand/App/NexusCommandApp.swift

**Steps**
1. Define @Model FileMetadataRecord (id UUID .unique, filePath/fileName/fileExtension/modifiedDate indexed, fileType, fileSize Int64, createdDate, contentSnippet optional indexed, contentHash String). Define @Model CommandHistoryRecord (id, query indexed, selectedResultPath, timestamp indexed, executionCount default 1). Define @Model UserPreferenceRecord as singleton with all preference fields (hotkeyKeyCode, hotkeyModifiers, indexingPaths, maxIndexedFiles, historyRetentionDays, appearanceMode, commandBarWidth, showMenuBarIcon). Create VersionedSchema v1 containing all three.
2. Create IndexingActor and HistoryActor as ModelActor subclasses with isolated ModelContext instances sharing the app ModelContainer. IndexingActor handles FileMetadataRecord CRUD. HistoryActor handles CommandHistoryRecord writes. Implement CommandHistoryService with record(), frequentCommands(limit:), searchHistory(query:), clearHistory(), pruneExpired() methods delegating to HistoryActor.
3. Build IndexingService.startIndexing(paths:) using FileManager.enumerator with TaskGroup parallelism capped at activeProcessorCount - 2. Extract metadata per file: fileName, filePath, UTType.identifier, fileSize, dates, SHA256 contentHash. For plainText-conforming files, extract first 500 chars as contentSnippet. Write via IndexingActor. Publish progress via AsyncStream<IndexProgress>. Add stopIndexing() with cooperative cancellation and indexStatus enum (idle/indexing/error).
4. Set up FSEvents stream (DispatchSource or EmbeddedFSEvents) to monitor indexed directories. Map events to FileSystemEvent(path, eventType: created/modified/deleted/renamed). Call IndexingService.handleFileEvent() for incremental SwiftData updates within 50ms target. Auto-detect SwiftData corruption on launch and trigger full re-index.
5. Implement FileSearchService.search(query:filters:) using SwiftData FetchDescriptor with compiled predicates matching fileName and contentSnippet. Support SearchFilters (fileTypes, modifiedAfter/Before, maxResults default 20). Score results: text match rank 0.7 weight + recency 0.3 weight, sort by relevanceScore descending. Add LRU cache (100-entry, keyed by query+filters hash), invalidated on any IndexingService file event. Expose cache_hit_rate counter.

**Validation**
`xcodebuild -scheme NexusCommand -destination 'platform=macOS' build 2>&1 | tail -5`

---

### Task 3: CoreML Intent Pipeline & System Action Execution

**Role:** Expert CoreML & macOS System Integration Engineer
**Goal:** Train CoreML intent classifier, build IntentParsingService with tokenization and caching, implement SystemActionService with shell allowlisting.

**Context**
Build the on-device intent classification pipeline using CoreML and NaturalLanguage frameworks, then wire parsed intents to macOS system operations. This is the AI brain that converts natural language queries into executable actions.

**Files to Create**
- NexusCommand/Models/IntentTypes.swift
- NexusCommand/Services/IntentParsingService.swift
- NexusCommand/Services/SystemActionService.swift
- NexusCommand/ML/NexusIntentClassifier.mlmodelc
- NexusCommand/Models/DomainErrors.swift

**Files to Modify**
- NexusCommand/App/ServiceContainer.swift

**Steps**
1. Define IntentAction enum (openFile, launchApp, runShellCommand, systemPreference, webSearch, calculate) as Sendable + Equatable. Create ParsedIntent struct (action, parameters: [String:String], confidence: Float). Create IntentChain struct (intents: [ParsedIntent], confidence: Float, rawTokens: [String]). Define all domain error enums: IntentError, SearchError, ActionError, IndexError, HotkeyError — each conforming to LocalizedError with errorDescription and recoverySuggestion.
2. Create a CoreML text classification model for the 6 IntentAction categories using Create ML or coremltools. Training data: synthetic command templates ('open [app]', 'find [file]', 'run [command]', 'settings [pane]', 'search [query]', '[math expr]'). Export as .mlmodelc bundle. Target sub-5ms inference on Neural Engine. Include NLTokenizer-based parameter extraction patterns.
3. Implement IntentParsingService with warmup() that preloads .mlmodelc at launch (modelStatus: loading/loaded/failed, target 200-500ms). Build parse(query:) that tokenizes via NLTokenizer(.word), strips control chars, enforces 500-char max, runs CoreML prediction. Split compound queries on conjunctions ('and','then','also') for multi-intent chains. Throw EmptyQuery for blank input, ParsingTimeout if >10ms. Add 50-entry LRU cache keyed by normalized query, skip caching below 0.5 confidence.
4. Build SystemActionService.execute(intent:) — openFile/launchApp via NSWorkspace.shared.open. runShellCommand via Process with /bin/zsh, stdout/stderr pipes, allowlist [open,defaults,osascript,pbcopy,pbpaste]; non-allowlisted shows confirmation dialog, user decline throws CommandNotAllowed. systemPreference opens x-apple.systempreferences URL scheme. webSearch opens URL via NSWorkspace. calculate evaluates via NSExpression. Return ActionResult with success/output.
5. Wire ServiceContainer to hold all service singletons (IntentParsingService, FileSearchService, SystemActionService, IndexingService, HotkeyService, CommandHistoryService). Inject via @Environment at app root. Implement app launch sequence in .task: (1) warmup CoreML, (2) register hotkey, (3) start FSEvents, (4) trigger initial index if needed. Log all lifecycle events via os.Logger.

**Validation**
`xcodebuild -scheme NexusCommand -destination 'platform=macOS' build 2>&1 | tail -5`

---

### Task 4: Query Pipeline, Settings, Visual Polish & Metal Shaders

**Role:** Expert SwiftUI & Metal Graphics Engineer
**Goal:** Wire debounced query pipeline with parallel search, build Settings UI, add Metal shaders and premium animations.

**Context**
Wire the command bar UI to parallel intent parsing and file search with debounced input. Build the tabbed Settings module. Add premium visual effects with Metal shaders, matchedGeometryEffect, and PhaseAnimator to achieve Raycast-rivaling polish.

**Files to Create**
- NexusCommand/Shaders/BlurShader.metal
- NexusCommand/Shaders/GlowShader.metal
- NexusCommand/Services/ShaderService.swift
- NexusCommand/Settings/SettingsView.swift
- NexusCommand/Settings/SettingsViewModel.swift
- NexusCommand/Settings/HotkeyRecorderView.swift

**Files to Modify**
- NexusCommand/CommandBar/CommandBarViewModel.swift
- NexusCommand/CommandBar/CommandBarView.swift
- NexusCommand/CommandBar/CommandBarPanel.swift
- NexusCommand/MenuBar/NexusMenuBarExtra.swift

**Steps**
1. In CommandBarViewModel, implement 50ms debounced query pipeline: on query change, cancel prior Task, sleep 50ms, then run IntentParsingService.parse and FileSearchService.search in parallel TaskGroup. Merge results into unified [SearchResultItem]. On Enter, execute via SystemActionService, show inline success/error feedback (tinted row, no modals), record to CommandHistoryService. On open, show frequentCommands(limit:5) as initial suggestions. Blend history matches while typing.
2. Write Metal shaders: BlurShader.metal (gaussian kernel blur with radius parameter), GlowShader.metal (color + intensity bloom). Build ShaderService that compiles .metal files at launch into cached MTLFunction refs, exposes as SwiftUI Shader via ShaderLibrary. Add isMetalAvailable check with graceful fallback to standard .ultraThinMaterial. Apply shaders to CommandBarPanel via .visualEffect/.layerEffect — custom blur behind panel, glow on focused TextField.
3. Add matchedGeometryEffect to result list items for smooth expand/collapse on selection change using @Namespace. Add PhaseAnimator for result entrance/exit (fade+slide). Add TimelineView for animated loading spinner. Animate indexing progress badge in MenuBarExtra. Respect .accessibilityReduceMotion. Wire MenuBarViewModel to live CommandHistoryService and IndexingService data.
4. Build SettingsView as Settings scene with TabView containing General, Indexing, Appearance tabs. SettingsViewModel as @Observable reads/writes UserPreferenceRecord via ModelContext. General tab: custom HotkeyRecorderView capturing key combos, launch-at-login toggle via SMAppService, menu bar icon toggle. Indexing tab: editable path list with NSOpenPanel add, max file count, re-index button with progress. Appearance tab: color scheme picker (system/light/dark), command bar width slider (500-900, default 680).
5. Add os.Logger per service (subsystem com.nexuscommand, categories: intent/search/indexing/hotkey/action/lifecycle). Instrument os_signpost intervals: QueryPipeline, MLInference, DataQuery, FSIndex, HotkeyActivation. Sample memory_footprint_mb via task_info every 60s. Track cache_hit_rate per 100 queries. Mark sensitive data with .private in log formatting.

**Validation**
`xcodebuild -scheme NexusCommand -destination 'platform=macOS' build 2>&1 | tail -5`

---

### Task 5: Testing, Code Signing & Distribution

**Role:** Expert macOS Testing & Distribution Engineer
**Goal:** Write unit/integration/E2E tests for all services, configure signing, notarization, DMG packaging, and CI pipeline.

**Context**
Build comprehensive test suites covering all services and E2E workflows. Configure code signing with Hardened Runtime, notarization, DMG packaging, and CI pipeline for automated builds.

**Files to Create**
- NexusCommandTests/IntentParsingServiceTests.swift
- NexusCommandTests/FileSearchServiceTests.swift
- NexusCommandTests/SystemActionServiceTests.swift
- NexusCommandTests/IndexingAndHistoryTests.swift
- NexusCommandTests/QueryPipelineIntegrationTests.swift
- NexusCommandUITests/CommandBarE2ETests.swift
- Scripts/build-dmg.sh
- .github/workflows/ci.yml

**Files to Modify**
- NexusCommand/NexusCommand.entitlements

**Steps**
1. Write IntentParsingServiceTests: mock CoreML model with deterministic outputs, test all 6 IntentAction types with representative queries, compound query producing 2-intent chain, EmptyQuery for blank input, ParsingTimeout handling. Write FileSearchServiceTests with in-memory ModelContainer seeded with FileMetadataRecords: verify text search, date filter, UTType filter, relevanceScore sorting, maxResults cap, recentFiles ordering.
2. Write SystemActionServiceTests: mock NSWorkspace and Process, test launchApp calls open with correct URL, allowlisted commands execute without confirmation, non-allowlisted 'rm -rf /' throws CommandNotAllowed, calculate evaluates valid/invalid expressions. Write IndexingAndHistoryTests: test crawl creates correct records, handleFileEvent for create/delete/modify, record creates/increments, frequentCommands ordering, pruneExpired removes old records. All use in-memory ModelContainer and temp directories.
3. Write QueryPipelineIntegrationTests: seed SwiftData with 100 FileMetadataRecords, parse 'find document.pdf' via real CoreML model, verify matching FileSearchResult, measure end-to-end latency via os_signpost, assert under 10ms on Apple Silicon. Write CommandBarE2ETests with XCUITest: launch app, simulate hotkey, verify command bar visible, type query, verify results, press Enter, verify action. SettingsE2E: open Settings, change hotkey. ColdStartE2E: measure time to responsiveness under 3s.
4. Configure NexusCommand.entitlements with App Sandbox, com.apple.security.files.user-selected.read-write, com.apple.security.temporary-exception.files.absolute-path.read-only for index paths, com.apple.security.automation.apple-events. Enable Hardened Runtime with no JIT/unsigned code exceptions. Set up notarytool submission and stapling script. Create Scripts/build-dmg.sh producing signed DMG with background image, app icon, /Applications alias.
5. Create .github/workflows/ci.yml: checkout, select Xcode 16, xcodebuild build, run unit tests, run UI tests, code sign with Developer ID, notarize via notarytool, run build-dmg.sh, upload DMG artifact. Add build-time grep check enforcing no URLSession import in NexusCommand/Services/ directory. Fail build if found.

**Validation**
`xcodebuild -scheme NexusCommand -destination 'platform=macOS' test 2>&1 | tail -10`