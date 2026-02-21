# Tasks Plan — Nexus Command

## 📌 Global Assumptions
- Solo developer on Apple Silicon Mac with macOS 15+ (Sequoia)
- Xcode 16+ with Swift 6 and SwiftUI 6 support
- Apple Developer Program membership for code signing and notarization
- CoreML model trained on synthetic command templates (not production user data)
- No server infrastructure required — fully local-first architecture
- CloudKit sync deferred — UserPreferenceRecord sync is post-v1 scope
- Mac App Store submission deferred — initial distribution via signed DMG only
- Target hardware: Apple Silicon Macs (M1+). Intel supported with degraded ML performance.

## ⚠️ Risks
- CoreML model accuracy may be insufficient for diverse user queries — mitigation: rule-based fallback for common patterns
- Global hotkey Cmd+Space conflicts with Spotlight — mitigation: default to alternative like Cmd+Shift+Space or detect conflict and prompt
- Full Disk Access rejection rate may be high — mitigation: graceful degradation with user-selected folders only
- SwiftData performance at 500K records is uncharted — mitigation: profile early in Phase 2, add pagination if needed
- Metal shader compatibility across GPU generations — mitigation: test on M1/M2/M3/M4, fallback to standard materials
- App Sandbox entitlement temporary exceptions may trigger notarization rejection — mitigation: test notarization early, adjust entitlements
- 50ms debounce + parallel ML+search may still exceed 10ms P95 on first cold query — mitigation: precompute common queries in warmup

## 🧩 Epics
## App Shell & Window Infrastructure
**Goal:** Establish the foundational macOS app structure with hidden WindowGroup, MenuBarExtra, NSPanel-based command bar, and global hotkey activation

### User Stories
_None_

### Acceptance Criteria
_None_

### ✅ Create Xcode project with SwiftUI App entry point (2h)

Set up @main NexusCommandApp with hidden WindowGroup scene, macOS 15+ deployment target, and App Sandbox entitlements. Configure ModelContainer with ModelConfiguration pointing to appSupportDir/NexusCommand/nexus.store.

**Acceptance Criteria**
- App launches with no visible window
- macOS 15+ deployment target set
- App Sandbox enabled in entitlements
- ModelContainer initialized with correct store URL
- App appears only in menu bar (LSUIElement or similar)

**Dependencies**
_None_

### ✅ Implement CommandBarPanel NSPanel subclass (4h)

Create CommandBarPanel as NSPanel subclass configured as nonactivating floating panel with no title bar. Set .nonactivatingPanel behavior, .canJoinAllSpaces collection behavior, and .ultraThinMaterial background. Create CommandBarWindowController to manage show/hide lifecycle and center positioning on active screen.

**Acceptance Criteria**
- NSPanel appears as floating overlay without stealing focus
- Panel has no title bar and uses .ultraThinMaterial
- Panel works across all Spaces
- Panel centers horizontally on the active screen
- Show/hide toggles cleanly without animation glitches

**Dependencies**
_None_

### ✅ Build CommandBarView with TextField and result list (4h)

Create CommandBarView with a styled TextField for query input and a scrollable result list. Create CommandBarViewModel as @Observable with query, results, selectedIndex, isLoading, and errorMessage properties. Wire TextField to query property. Display static placeholder results for now. Set command bar width to 680pt default.

**Acceptance Criteria**
- TextField accepts input and updates ViewModel query
- Result list renders placeholder items
- selectedIndex highlights current row visually
- Command bar is 680pt wide with rounded corners
- isLoading shows a loading indicator

**Dependencies**
- Implement CommandBarPanel NSPanel subclass

### ✅ Implement keyboard navigation in command bar (3h)

Add keyboard event handling to CommandBarView: arrow up/down to change selectedIndex, Enter to execute selected result, Escape to dismiss command bar, Tab for future autocomplete. Use .onKeyPress or NSEvent local monitor as needed.

**Acceptance Criteria**
- Arrow keys move selection up/down through result list
- Selection wraps or clamps at boundaries
- Enter triggers action on selected result
- Escape dismisses the command bar panel
- Tab is captured for future autocomplete use

**Dependencies**
- Build CommandBarView with TextField and result list

### ✅ Implement HotkeyService with global hotkey registration (4h)

Create HotkeyService that registers a global hotkey using NSEvent.addGlobalMonitorForEvents(matching: .keyDown). Default hotkey: Cmd+Space. Include Carbon RegisterEventHotKey fallback. Detect conflicts via kEventHotKeyExistsErr. Expose currentHotkey, register(), and unregister().

**Acceptance Criteria**
- Cmd+Space activates command bar from any app
- HotkeyConflict error thrown if combination is taken
- AccessibilityNotGranted error if permission missing
- unregister() cleanly removes the hotkey
- Fallback to Carbon API works when NSEvent monitor fails

**Dependencies**
_None_

### ✅ Wire hotkey to command bar panel toggle (2h)

Connect HotkeyService handler to CommandBarWindowController show/hide. On hotkey press, toggle panel visibility. If showing, focus the TextField. If hiding, clear query and results. Measure hotkey_to_visible_ms with os_signpost.

**Acceptance Criteria**
- Hotkey toggles command bar visibility
- TextField is focused when command bar appears
- Query and results cleared on dismiss
- hotkey_to_visible_ms logged via os_signpost
- Target: panel visible within 200ms of hotkey press

**Dependencies**
- Implement HotkeyService with global hotkey registration
- Implement CommandBarPanel NSPanel subclass

### ✅ Build permission onboarding flow (3h)

On first launch, present explanation dialogs requesting Accessibility permission (for global hotkey) and Full Disk Access (for file indexing). If Accessibility denied, disable hotkey gracefully and show menu bar fallback instruction. If FDA denied, note degraded indexing scope. Persist onboarding-complete flag to UserDefaults.

**Acceptance Criteria**
- First launch shows Accessibility permission request with explanation
- First launch shows Full Disk Access request with explanation
- Denied Accessibility results in graceful fallback message
- Denied FDA results in informational message about limited indexing
- Onboarding does not repeat after completion

**Dependencies**
- Implement HotkeyService with global hotkey registration

### ✅ Implement MenuBarExtra with basic menu (2h)

Create NexusMenuBarExtra scene using MenuBarExtra(content:label:) with SF Symbol command.square.fill. Menu items: Open Command Bar, recent commands placeholder, Settings shortcut, Quit. Create MenuBarViewModel as @Observable.

**Acceptance Criteria**
- Menu bar icon visible using command.square.fill SF Symbol
- Open Command Bar menu item toggles command bar panel
- Settings menu item opens Settings window
- Quit menu item terminates the app
- Recent commands section shows placeholder text

**Dependencies**
- Create Xcode project with SwiftUI App entry point

## SwiftData Schema & Indexing Service
**Goal:** Define the SwiftData models and build the file indexing pipeline with background crawling and real-time FSEvents monitoring

### User Stories
_None_

### Acceptance Criteria
_None_

### ✅ Define SwiftData models for FileMetadataRecord (1h)

Create @Model FileMetadataRecord with: id (UUID, .unique), filePath (String, indexed), fileName (String, indexed), fileExtension (String, indexed), fileType (String — UTType.identifier), fileSize (Int64), createdDate (Date), modifiedDate (Date, indexed), contentSnippet (String?, indexed), contentHash (String). No relationships. Flat schema for fast predicate queries.

**Acceptance Criteria**
- @Model compiles with all specified properties
- Indexed attributes: filePath, fileName, fileExtension, modifiedDate, contentSnippet
- id is UUID with .unique attribute
- Model can be inserted and fetched from in-memory ModelContainer
- Schema version 1 defined via VersionedSchema

**Dependencies**
_None_

### ✅ Define SwiftData models for CommandHistoryRecord and UserPreferenceRecord (1h)

Create @Model CommandHistoryRecord with: id, query (indexed), selectedResultPath, timestamp (indexed), executionCount (default 1). Create @Model UserPreferenceRecord as singleton with all preference fields from TRD (hotkeyKeyCode, hotkeyModifiers, indexingPaths, maxIndexedFiles, historyRetentionDays, appearanceMode, commandBarWidth, showMenuBarIcon).

**Acceptance Criteria**
- CommandHistoryRecord compiles with indexed query and timestamp
- UserPreferenceRecord has all specified default values
- UserPreferenceRecord fetched via FetchDescriptor limit 1
- Both models work with in-memory ModelContainer
- VersionedSchema includes all three models

**Dependencies**
- Define SwiftData models for FileMetadataRecord

### ✅ Create ModelActor subclasses for background SwiftData access (3h)

Implement IndexingActor and HistoryActor as ModelActor subclasses. IndexingActor handles FileMetadataRecord CRUD off main actor. HistoryActor handles CommandHistoryRecord writes. Both use the shared ModelContainer but isolated ModelContext instances.

**Acceptance Criteria**
- IndexingActor can insert, update, delete FileMetadataRecords
- HistoryActor can insert and update CommandHistoryRecords
- Neither actor blocks main actor during operations
- Both actors use the same ModelContainer
- Concurrent read/write does not cause crashes

**Dependencies**
- Define SwiftData models for FileMetadataRecord
- Define SwiftData models for CommandHistoryRecord and UserPreferenceRecord

### ✅ Implement IndexingService full directory crawl (6h)

Build IndexingService.startIndexing(paths:) using FileManager.enumerator with TaskGroup parallelism capped at activeProcessorCount - 2. Extract metadata per file: fileName, filePath, UTType, fileSize, dates, SHA256 contentHash. For UTType.plainText conforming files, extract first 500 characters as contentSnippet. Write FileMetadataRecords via IndexingActor. Publish progress via AsyncStream<IndexProgress>.

**Acceptance Criteria**
- Crawls all files in specified directories recursively
- TaskGroup concurrency bounded to activeProcessorCount - 2
- Correct metadata extracted for each file
- Text file content snippets limited to 500 characters
- SHA256 contentHash computed for each file
- Progress published via AsyncStream with totalFiles and processedFiles
- Handles inaccessible directories with PathNotAccessible error

**Dependencies**
- Create ModelActor subclasses for background SwiftData access

### ✅ Implement FSEvents real-time file monitoring (4h)

Set up DispatchSource or FSEvents stream to monitor indexed directories for file system changes. Map events to FileSystemEvent { path, eventType: created/modified/deleted/renamed }. Call IndexingService.handleFileEvent() for incremental SwiftData updates within 50ms target.

**Acceptance Criteria**
- FSEvents stream monitors all configured index paths
- File creation triggers new FileMetadataRecord insert
- File modification updates contentHash and modifiedDate
- File deletion removes corresponding record
- File rename updates filePath and fileName
- Incremental update completes within 50ms target

**Dependencies**
- Implement IndexingService full directory crawl

### ✅ Implement IndexingService stopIndexing and status reporting (2h)

Add cooperative cancellation to TaskGroup crawl via stopIndexing(). Expose indexStatus: IndexStatus { idle, indexing, error(String) } and totalRecordCount. Auto-detect SwiftData corruption on launch and trigger full re-index.

**Acceptance Criteria**
- stopIndexing() cancels in-progress crawl cooperatively
- indexStatus reflects current state accurately
- totalRecordCount returns correct FileMetadataRecord count
- Corrupted SwiftData store triggers automatic re-index
- Cancellation produces no partial/corrupt records

**Dependencies**
- Implement IndexingService full directory crawl

## File Search Service
**Goal:** Build fast SwiftData-backed file search with text matching, attribute filtering, relevance scoring, and LRU caching

### User Stories
_None_

### Acceptance Criteria
_None_

### ✅ Implement FileSearchService.search with predicate queries (4h)

Build search(query:filters:) using SwiftData FetchDescriptor with compiled predicates. Full-text match on fileName and contentSnippet. Support SearchFilters: fileTypes ([UTType]), modifiedAfter/Before (Date), maxResults (default 20). Pre-compile static predicate parts, inject dynamic values as variables.

**Acceptance Criteria**
- Text query matches against fileName and contentSnippet
- UTType filter restricts results to matching file types
- Date range filters work correctly
- Results capped at maxResults
- Empty query returns empty array (not error)
- InvalidPredicate error thrown for malformed queries
- IndexNotReady error when index is still building

**Dependencies**
- Implement IndexingService full directory crawl

### ✅ Implement relevance scoring and result sorting (3h)

Score each FileSearchResult with weighted combination: text match rank (0.7 weight) and recency based on modifiedDate (0.3 weight). Sort results by relevanceScore descending. Implement recentFiles(limit:) returning files ordered by modifiedDate descending.

**Acceptance Criteria**
- Exact fileName matches score higher than partial matches
- Recently modified files rank higher than old files with equal text match
- relevanceScore is a Float between 0 and 1
- Results sorted by relevanceScore descending
- recentFiles returns correct order by modifiedDate

**Dependencies**
- Implement FileSearchService.search with predicate queries

### ✅ Add LRU cache to FileSearchService (2h)

Implement an LRU cache with 100-entry capacity keyed by (query + filters hash). Cache stores [FileSearchResult]. invalidateCache() called on any IndexingService file event. Expose cache_hit_rate counter for observability.

**Acceptance Criteria**
- Repeated identical queries return cached results
- Cache evicts least-recently-used entry at capacity
- Any file event from IndexingService invalidates entire cache
- cache_hit_rate counter tracks hits/misses
- Cache key correctly differentiates different filter combinations

**Dependencies**
- Implement relevance scoring and result sorting

## CoreML Intent Parsing Pipeline
**Goal:** Train or convert a CoreML intent classification model and build the IntentParsingService with tokenization, prediction, intent chaining, and caching

### User Stories
_None_

### Acceptance Criteria
_None_

### ✅ Define IntentAction enum and ParsedIntent data types (1h)

Create IntentAction enum with cases: openFile, launchApp, runShellCommand, systemPreference, webSearch, calculate. Create ParsedIntent struct with action, parameters dictionary, and confidence. Create IntentChain struct with intents array, overall confidence, and rawTokens.

**Acceptance Criteria**
- IntentAction enum has all 6 cases
- ParsedIntent holds action, [String: String] parameters, Float confidence
- IntentChain holds [ParsedIntent], Float confidence, [String] rawTokens
- All types are Sendable for concurrency safety
- Types conform to Equatable for testing

**Dependencies**
_None_

### ✅ Create and convert CoreML intent classification model (8h)

Build a text classification model for the 6 IntentAction categories using Create ML or Python coremltools. Training data: synthetic command templates (e.g., 'open [app]', 'find [file]', 'run [command]'). Export as .mlmodelc bundle. Include parameter extraction via NLTokenizer named entity patterns. Target sub-5ms inference on Neural Engine.

**Acceptance Criteria**
- .mlmodelc bundle compiles and loads in Xcode project
- Model classifies 'open Safari' as launchApp
- Model classifies 'find readme.md' as openFile
- Model classifies 'run ls' as runShellCommand
- Model classifies '2+2' as calculate
- Inference time under 5ms on Apple Silicon Neural Engine
- Model code-signed inside app bundle

**Dependencies**
- Define IntentAction enum and ParsedIntent data types

### ✅ Implement IntentParsingService.warmup and model loading (2h)

Build warmup() that preloads the .mlmodelc bundle into memory at app launch. Set modelStatus to .loading during load, .loaded on success, .failed on error. Target 200-500ms load time. Handle ModelNotFound and ModelCompilationFailed errors.

**Acceptance Criteria**
- warmup() loads model and sets modelStatus to .loaded
- ModelNotFound thrown if .mlmodelc missing from bundle
- ModelCompilationFailed thrown if CoreML cannot compile
- Model load completes within 500ms on Apple Silicon
- modelStatus observable for UI binding

**Dependencies**
- Create and convert CoreML intent classification model

### ✅ Implement IntentParsingService.parse with tokenization and prediction (5h)

Build parse(query:) that tokenizes input via NLTokenizer with .word unit, runs CoreML prediction, and returns IntentChain. Strip control characters and enforce 500-char max. Handle compound queries by splitting on conjunctions ('and', 'then', 'also') to produce multi-intent chains. Throw EmptyQuery for blank input, ParsingTimeout if inference exceeds 10ms.

**Acceptance Criteria**
- Single intent queries return 1-element IntentChain
- Compound query 'open Terminal and run pwd' returns 2 intents
- Empty/whitespace input throws EmptyQuery
- Control characters stripped from input
- Input over 500 characters truncated
- ParsingTimeout thrown if inference exceeds 10ms budget
- Parameters extracted from query (e.g., app name, file name)

**Dependencies**
- Implement IntentParsingService.warmup and model loading

### ✅ Add LRU parse cache to IntentParsingService (2h)

Implement LRU cache with 50-entry capacity keyed by normalized (lowercased, trimmed) query string. Cache IntentChain results. Skip cache for queries with confidence below 0.5.

**Acceptance Criteria**
- Repeated identical queries return cached IntentChain
- Cache normalizes keys (lowercase, trimmed)
- Low-confidence results not cached
- Cache evicts LRU entry at 50 capacity
- Cache hit avoids CoreML inference call

**Dependencies**
- Implement IntentParsingService.parse with tokenization and prediction

## System Action Execution
**Goal:** Map parsed intents to macOS system operations with proper security controls and shell command allowlisting

### User Stories
_None_

### Acceptance Criteria
_None_

### ✅ Implement SystemActionService for file and app operations (3h)

Build execute(intent:) for openFile and launchApp actions using NSWorkspace.shared.open(_:). Map file paths to URLs. Map app names to /Applications paths. Return ActionResult with success status and launchedApp/openedURL.

**Acceptance Criteria**
- openFile opens file at specified path via NSWorkspace
- launchApp launches application by name from /Applications
- AppNotFound thrown for non-existent applications
- PermissionDenied thrown when entitlement missing
- ActionResult correctly populated with openedURL or launchedApp

**Dependencies**
- Define IntentAction enum and ParsedIntent data types

### ✅ Implement shell command execution with allowlist (4h)

Handle runShellCommand via Process with /bin/zsh. Capture stdout/stderr via pipes. Allowlist: [open, defaults, osascript, pbcopy, pbpaste]. Commands outside allowlist show confirmation dialog with full command text. CommandNotAllowed thrown if user declines. ShellCommandFailed on non-zero exit with stderr.

**Acceptance Criteria**
- Allowlisted commands execute without confirmation
- Non-allowlisted commands show confirmation dialog
- User decline throws CommandNotAllowed
- Non-zero exit code throws ShellCommandFailed with stderr
- stdout captured in ActionResult.output
- Commands run in /bin/zsh shell

**Dependencies**
- Implement SystemActionService for file and app operations

### ✅ Implement remaining action types (systemPreference, webSearch, calculate) (2h)

systemPreference: open URL scheme x-apple.systempreferences:{paneID}. webSearch: open URL in default browser via NSWorkspace. calculate: evaluate math expressions via NSExpression. Handle UnsupportedAction for unrecognized IntentAction cases.

**Acceptance Criteria**
- systemPreference opens correct System Settings pane
- webSearch opens URL in default browser
- calculate evaluates '2+2' and returns '4' in output
- calculate handles invalid expressions gracefully
- UnsupportedAction thrown for unknown action types

**Dependencies**
- Implement SystemActionService for file and app operations

## Command Bar Query Pipeline
**Goal:** Wire the command bar UI to parallel intent parsing and file search with debounced input and merged results

### User Stories
_None_

### Acceptance Criteria
_None_

### ✅ Implement 50ms debounced query pipeline in CommandBarViewModel (4h)

On query change, debounce for 50ms via Task.sleep(for: .milliseconds(50)) with cancellation of prior search task. After debounce, run IntentParsingService.parse and FileSearchService.search in parallel TaskGroup. Merge results into unified SearchResultItem list for display.

**Acceptance Criteria**
- Typing rapidly does not trigger search per keystroke
- Search fires 50ms after last keystroke
- Prior in-flight search cancelled on new input
- Intent parsing and file search run in parallel
- Results merged and displayed in result list
- isLoading true during search, false after

**Dependencies**
- Build CommandBarView with TextField and result list
- Implement IntentParsingService.parse with tokenization and prediction
- Implement FileSearchService.search with predicate queries

### ✅ Wire result selection to SystemActionService execution (3h)

When user presses Enter on a selected result, determine intent from the result and call SystemActionService.execute. Show success feedback inline. On error, display tinted error row in result list (no modal alerts). Record query and selection to CommandHistoryService.

**Acceptance Criteria**
- Enter executes the selected result's intent
- Success shows brief inline feedback
- Errors display as tinted row in result list, not modal
- Query + selection recorded to CommandHistoryService
- Command bar dismisses after successful execution

**Dependencies**
- Implement 50ms debounced query pipeline in CommandBarViewModel
- Implement SystemActionService for file and app operations

### ✅ Integrate CommandHistoryService for autocomplete suggestions (4h)

On command bar open, fetch frequentCommands(limit: 5) and show as initial suggestions. While typing, blend history matches with live search results. Implement CommandHistoryService.record(), frequentCommands(), searchHistory(), clearHistory(), and pruneExpired().

**Acceptance Criteria**
- Empty query shows top 5 frequent commands
- Typing blends history matches with live results
- record() creates or increments CommandHistoryRecord
- pruneExpired() removes records older than retention period
- clearHistory() wipes all records

**Dependencies**
- Implement 50ms debounced query pipeline in CommandBarViewModel
- Create ModelActor subclasses for background SwiftData access

## Visual Polish & Metal Shaders
**Goal:** Add premium visual effects including Metal shaders, matched geometry transitions, phase animations, and loading indicators

### User Stories
_None_

### Acceptance Criteria
_None_

### ✅ Implement ShaderService with Metal blur and glow effects (6h)

Write Metal shaders for blur (gaussian kernel), glow (color + intensity bloom), and transition (progress-based wipe). Compile from .metal files at app launch into cached MTLFunction references. Expose as SwiftUI Shader instances via ShaderLibrary. Graceful fallback to standard materials if Metal unavailable.

**Acceptance Criteria**
- blurShader(radius:) produces visible gaussian blur
- glowShader(color:intensity:) produces colored bloom effect
- transitionShader(progress:) animates between states
- Shaders compiled once at launch, cached for reuse
- isMetalAvailable false triggers graceful fallback
- No runtime shader compilation

**Dependencies**
_None_

### ✅ Add matchedGeometryEffect transitions to result list (3h)

Apply matchedGeometryEffect to result items for smooth expand/collapse transitions when selection changes or results update. Use Namespace for geometry matching across result rows.

**Acceptance Criteria**
- Result items animate smoothly on selection change
- New results entering the list have matched geometry transitions
- No visual glitches during rapid query changes
- Animations complete within 300ms

**Dependencies**
- Build CommandBarView with TextField and result list

### ✅ Add PhaseAnimator and TimelineView animations (3h)

PhaseAnimator for result list entrance/exit animations (fade + slide). TimelineView for animated loading spinner and status indicators in the command bar. Animate indexing progress badge in MenuBarExtra.

**Acceptance Criteria**
- Results animate in with fade+slide on appearance
- Results animate out on dismissal
- Loading spinner animates smoothly via TimelineView
- Menu bar indexing badge shows animated progress
- Animations respect reduced motion accessibility setting

**Dependencies**
- Build CommandBarView with TextField and result list
- Implement MenuBarExtra with basic menu

### ✅ Apply Metal shaders to command bar overlay (3h)

Integrate ShaderService shaders into CommandBarPanel via .visualEffect and .layerEffect modifiers. Custom blur behind the panel content. Subtle glow on focused TextField. Transition shader for panel show/hide.

**Acceptance Criteria**
- Command bar background has custom Metal blur effect
- TextField shows subtle glow when focused
- Panel show/hide uses shader transition
- Effects render correctly on M1/M2/M3/M4
- Fallback to standard materials on Metal unavailability

**Dependencies**
- Implement ShaderService with Metal blur and glow effects
- Implement CommandBarPanel NSPanel subclass

## Settings Module
**Goal:** Build a tabbed Settings scene for hotkey configuration, indexing path management, and appearance customization

### User Stories
_None_

### Acceptance Criteria
_None_

### ✅ Create tabbed SettingsView with General, Indexing, and Appearance tabs (2h)

Build SettingsView as a Settings scene with NavigationStack and three tabs. Create SettingsViewModel as @Observable that reads/writes UserPreferenceRecord via ModelContext. Wire to the app's Settings scene.

**Acceptance Criteria**
- Settings opens from menu bar and Cmd+comma
- Three tabs: General, Indexing, Appearance
- SettingsViewModel loads UserPreferenceRecord on init
- Changes persist to SwiftData immediately
- Settings window has standard macOS appearance

**Dependencies**
- Define SwiftData models for CommandHistoryRecord and UserPreferenceRecord

### ✅ Build General settings tab with hotkey recorder (4h)

General tab: custom hotkey recorder view that captures key combination, launch at login toggle (via SMAppService), menu bar icon toggle. Hotkey changes call HotkeyService.unregister then register with new combo.

**Acceptance Criteria**
- Hotkey recorder captures key + modifier combination
- New hotkey persisted to UserPreferenceRecord
- Launch at login toggle works via SMAppService
- Menu bar icon can be hidden/shown
- Hotkey conflict shows error inline

**Dependencies**
- Create tabbed SettingsView with General, Indexing, and Appearance tabs
- Implement HotkeyService with global hotkey registration

### ✅ Build Indexing settings tab with directory picker (3h)

Indexing tab: list of current index paths with add/remove. Add uses NSOpenPanel for directory selection. Display max file count setting. Re-index button triggers IndexingService.startIndexing with progress indicator.

**Acceptance Criteria**
- Current index paths displayed in editable list
- Add button opens NSOpenPanel for directory selection
- Remove button deletes path from list
- Max file count is configurable
- Re-index button triggers full re-index with progress bar

**Dependencies**
- Create tabbed SettingsView with General, Indexing, and Appearance tabs
- Implement IndexingService full directory crawl

### ✅ Build Appearance settings tab (2h)

Appearance tab: color scheme picker (system/light/dark) using preferredColorScheme modifier, command bar width slider (min 500, max 900, default 680). Changes reflect immediately in command bar.

**Acceptance Criteria**
- Color scheme picker with system/light/dark options
- Command bar width adjustable via slider
- Changes apply immediately without restart
- Preferences persisted to UserPreferenceRecord

**Dependencies**
- Create tabbed SettingsView with General, Indexing, and Appearance tabs

## Service Container & App Lifecycle
**Goal:** Wire all services together via dependency injection and orchestrate the app launch sequence

### User Stories
_None_

### Acceptance Criteria
_None_

### ✅ Create ServiceContainer with dependency injection (3h)

Build ServiceContainer as @Observable holding all service singletons: IntentParsingService, FileSearchService, SystemActionService, IndexingService, HotkeyService, ShaderService, CommandHistoryService. Inject via @Environment into SwiftUI views.

**Acceptance Criteria**
- All services instantiated as singletons in ServiceContainer
- ServiceContainer injected into environment at app root
- Views access services via @Environment
- ServiceContainer is @Observable for reactive status updates
- No circular dependencies between services

**Dependencies**
- Implement HotkeyService with global hotkey registration
- Implement IntentParsingService.warmup and model loading
- Implement IndexingService full directory crawl

### ✅ Implement app launch sequence (3h)

On app launch: (1) warmup CoreML model, (2) register global hotkey, (3) start FSEvents monitor on configured paths, (4) trigger initial index if first launch or index empty. Use Task { } from App.init or .task modifier. Log all lifecycle events via os.Logger.

**Acceptance Criteria**
- CoreML model loaded before first query possible
- Hotkey registered on launch
- FSEvents monitoring active for all configured paths
- Initial index triggered on first launch
- All lifecycle events logged to os.Logger
- Launch sequence completes within 3 seconds

**Dependencies**
- Create ServiceContainer with dependency injection

### ✅ Wire MenuBarExtra to live service data (2h)

Connect MenuBarViewModel to CommandHistoryService for recent commands and IndexingService for indexing status. Show indexing progress badge when active. Update recent commands list on each command bar dismissal.

**Acceptance Criteria**
- Recent commands section shows actual history
- Indexing status shown when indexing active
- Progress badge animates during indexing
- Menu updates when new commands executed

**Dependencies**
- Implement MenuBarExtra with basic menu
- Integrate CommandHistoryService for autocomplete suggestions
- Implement IndexingService full directory crawl

## Observability & Logging
**Goal:** Instrument all critical paths with os.Logger, os_signpost, and performance metrics

### User Stories
_None_

### Acceptance Criteria
_None_

### ✅ Add os.Logger per-service logging (2h)

Configure os.Logger with subsystem 'com.nexuscommand' and per-service categories: intent, search, indexing, hotkey, action, lifecycle. Log at appropriate levels: .debug for query traces, .info for lifecycle events, .error for recoverable failures, .fault for non-recoverable. Mark sensitive data (file paths, query text) with .private.

**Acceptance Criteria**
- Each service has its own os.Logger with correct category
- Debug level logs query text and timing
- Info level logs lifecycle events
- Error level logs recoverable failures
- Fault level logs non-recoverable state
- Sensitive data uses .private formatting

**Dependencies**
_None_

### ✅ Add os_signpost performance tracing (3h)

Instrument os_signpost intervals for: QueryPipeline (end-to-end), MLInference (CoreML), DataQuery (SwiftData), FSIndex (crawl/update), HotkeyActivation (press-to-visible). All viewable in Instruments. Track query_latency_ms, intent_parse_ms, file_search_ms, index_update_ms, hotkey_to_visible_ms.

**Acceptance Criteria**
- All 5 signpost categories emit begin/end intervals
- Intervals visible in Instruments os_signpost instrument
- query_latency_ms measurable end-to-end
- intent_parse_ms isolated to CoreML call
- hotkey_to_visible_ms from callback to orderFront

**Dependencies**
- Implement 50ms debounced query pipeline in CommandBarViewModel
- Wire hotkey to command bar panel toggle

### ✅ Add memory and cache metrics (2h)

Sample memory_footprint_mb via task_info every 60 seconds, log at .info level. Track cache_hit_rate for FileSearchService LRU cache per 100 queries. Log index_total_records on index completion and 60s heartbeat.

**Acceptance Criteria**
- Memory footprint logged every 60 seconds
- Cache hit/miss ratio tracked and logged
- Total indexed records logged periodically
- Metrics viewable in Console.app
- No significant overhead from metric collection

**Dependencies**
- Add LRU cache to FileSearchService
- Implement IndexingService full directory crawl

## Error Handling & Resilience
**Goal:** Implement domain-specific error types, inline error display, and graceful degradation for all failure modes

### User Stories
_None_

### Acceptance Criteria
_None_

### ✅ Define domain error enums per service (2h)

Create IntentError, SearchError, ActionError, IndexError, HotkeyError enums conforming to LocalizedError. Each case has errorDescription and recoverySuggestion. Map all error cases from API contracts.

**Acceptance Criteria**
- Each service has its own error enum
- All error cases from TRD are covered
- errorDescription returns user-friendly message
- recoverySuggestion provides actionable guidance
- Errors are Sendable for concurrency safety

**Dependencies**
_None_

### ✅ Implement inline error display in command bar (3h)

Catch all errors in CommandBarViewModel and render as tinted result row in command bar. No modal alerts for recoverable errors. Non-recoverable errors (model load failure, store corruption) show persistent banner in MenuBarExtra with Repair action.

**Acceptance Criteria**
- Recoverable errors shown as tinted row in result list
- No modal alert dialogs for search/parse errors
- Non-recoverable errors show MenuBarExtra banner
- Repair action triggers re-initialization
- Cancelled operations return empty results without error

**Dependencies**
- Define domain error enums per service
- Implement 50ms debounced query pipeline in CommandBarViewModel

## Testing
**Goal:** Build comprehensive unit, integration, and E2E test suites validating all services and user workflows

### User Stories
_None_

### Acceptance Criteria
_None_

### ✅ Write unit tests for IntentParsingService (3h)

Test parse() with mock CoreML model: 'open Safari' → launchApp, 'find readme.md' → openFile, 'run ls' → runShellCommand. Compound query produces 2-intent chain. Empty input throws EmptyQuery. Mock CoreML with deterministic MLMultiArray outputs.

**Acceptance Criteria**
- 6 IntentAction types tested with representative queries
- Compound query test produces multi-intent chain
- EmptyQuery thrown for blank input
- Mock CoreML model used (no real inference)
- All tests pass reliably

**Dependencies**
- Implement IntentParsingService.parse with tokenization and prediction

### ✅ Write unit tests for FileSearchService (3h)

Test with in-memory ModelContainer seeded with FileMetadataRecords. Verify text search, date filter, UTType filter, result sorting by relevance, maxResults cap. Test recentFiles ordering.

**Acceptance Criteria**
- Text search returns matching records
- Date range filter excludes out-of-range files
- UTType filter returns only matching types
- Results sorted by relevanceScore descending
- maxResults caps output correctly

**Dependencies**
- Implement relevance scoring and result sorting

### ✅ Write unit tests for SystemActionService (3h)

Mock NSWorkspace and Process. Test launchApp calls NSWorkspace.open with correct URL. Test allowlisted shell commands pass. Test non-allowlisted 'rm -rf /' throws CommandNotAllowed. Test calculate with valid and invalid expressions.

**Acceptance Criteria**
- launchApp test verifies NSWorkspace.open called
- Allowlisted command executes without confirmation
- Non-allowlisted command throws CommandNotAllowed
- ShellCommandFailed includes stderr output
- calculate evaluates expressions correctly

**Dependencies**
- Implement shell command execution with allowlist
- Implement remaining action types (systemPreference, webSearch, calculate)

### ✅ Write unit tests for CommandHistoryService and IndexingService (4h)

CommandHistoryService: test record creates/increments, frequentCommands ordering, pruneExpired. IndexingService: test crawl creates correct records, handleFileEvent for create/delete/modify. All with in-memory ModelContainer and temp directories.

**Acceptance Criteria**
- record() creates new or increments existing
- frequentCommands returns top-N by count
- pruneExpired removes old records
- Crawl creates FileMetadataRecords for all files
- File events update/remove records correctly

**Dependencies**
- Integrate CommandHistoryService for autocomplete suggestions
- Implement FSEvents real-time file monitoring

### ✅ Write integration test for query pipeline (3h)

Seed SwiftData with 100 FileMetadataRecords. Parse 'find document.pdf' via real CoreML model. Verify FileSearchService returns matching record. Measure end-to-end latency with os_signpost. Assert under 10ms on Apple Silicon.

**Acceptance Criteria**
- 100 seeded records searchable
- Real CoreML model produces valid IntentChain
- Matching FileSearchResult returned
- End-to-end latency measured via os_signpost
- Latency under 10ms on Apple Silicon

**Dependencies**
- Implement 50ms debounced query pipeline in CommandBarViewModel
- Add os_signpost performance tracing

### ✅ Write E2E tests with XCUITest (5h)

CommandBarActivationE2E: launch app, simulate hotkey, verify command bar visible, type query, verify results, press Enter, verify action. SettingsE2E: open Settings, change hotkey, verify new hotkey works. ColdStartE2E: relaunch app, measure time to responsiveness under 3 seconds.

**Acceptance Criteria**
- Command bar activation E2E passes
- Settings hotkey change E2E passes
- Cold start completes within 3 seconds
- All E2E tests run without flakiness
- Tests use XCUITest framework

**Dependencies**
- Wire result selection to SystemActionService execution
- Build General settings tab with hotkey recorder

## Distribution & Signing
**Goal:** Package the app as a signed, notarized .dmg with CI pipeline for automated builds

### User Stories
_None_

### Acceptance Criteria
_None_

### ✅ Configure code signing and Hardened Runtime (2h)

Set up Developer ID signing certificate. Enable Hardened Runtime with no JIT, no unsigned code, no DYLD environment variables. Configure entitlements: App Sandbox, files.user-selected.read-write, temporary-exception for index paths, automation.apple-events.

**Acceptance Criteria**
- App signed with Developer ID certificate
- Hardened Runtime enabled with no exceptions for JIT/unsigned
- All required entitlements in .entitlements file
- App launches correctly with Hardened Runtime
- codesign --verify passes

**Dependencies**
_None_

### ✅ Set up notarization via notarytool (2h)

Configure notarytool with Apple Developer credentials. Automate submission and stapling. Verify notarization succeeds with current entitlement set. Handle notarization failures with diagnostic logs.

**Acceptance Criteria**
- App submits to notarization successfully
- Stapled ticket attached to app bundle
- spctl --assess --type exec passes
- Notarization log accessible for debugging
- Process scriptable for CI integration

**Dependencies**
- Configure code signing and Hardened Runtime

### ✅ Create DMG packaging with installer appearance (2h)

Build .dmg with background image, app icon, and /Applications alias for drag-install. Script DMG creation for repeatability. Ensure DMG is signed and notarized.

**Acceptance Criteria**
- DMG opens with background image and app icon
- /Applications alias present for drag-install
- DMG signed and passes Gatekeeper
- DMG creation scripted and repeatable
- File size reasonable (under 50MB)

**Dependencies**
- Set up notarization via notarytool

### ✅ Set up CI pipeline for automated builds (4h)

Configure CI (GitHub Actions or Xcode Cloud) to: xcodebuild → run tests → code sign → notarize → package DMG. Add build-time grep check to enforce no URLSession import in core service modules.

**Acceptance Criteria**
- CI builds on every push to main
- Tests run and must pass before packaging
- Code signing automated in CI
- Notarization automated in CI
- DMG artifact produced and downloadable
- URLSession import check fails build if found in core modules

**Dependencies**
- Create DMG packaging with installer appearance

## ❓ Open Questions
- CoreML model architecture: NLModel with custom classifier vs. converted transformer? Training data source?
- Should CommandHistoryRecord sync cross-device via CloudKit or remain strictly local?
- Should power users configure custom shell command allowlists via Settings?
- Should FileSearchService also query CSSearchableIndex (Spotlight) for broader coverage?
- Post-v1 model updates: app update only or optional background model download?
- VoiceOver accessibility priority and scope for NSPanel command bar?
- Mac App Store dual-build strategy: reduced-capability MAS build vs. DMG-only distribution?