# Architecture Requirements Document

## 🧱 System Overview
Nexus Command is a native macOS command center application targeting macOS 15+ on Apple Silicon. It provides a global hotkey-activated translucent command bar with on-device ML intent parsing, local file metadata search, and system-level actions. The architecture is strictly local-first with zero cloud dependency for core features, leveraging Metal and Neural Engine for sub-10ms query latency. All ML inference runs on-device via CoreML and NaturalLanguage frameworks. SwiftData provides indexed local storage, and an optional CloudKit layer syncs user settings across devices.

## 🏗 Architecture Style
Single-process native macOS application using a layered architecture: UI Layer (SwiftUI 6 views + Metal shaders), Service Layer (Structured Concurrency pipelines for search, ML inference, and system actions), Data Layer (SwiftData local store + Spotlight-style indexing), and an optional Sync Layer (CloudKit for settings). No server, no microservices, no network dependency for core paths.

## 🎨 Frontend Architecture
- **Framework:** SwiftUI 6 with NSWindow customization for the translucent command bar overlay. MenuBarExtra for persistent menu bar presence. Settings scene for user preferences. .ultraThinMaterial and .regularMaterial for the command bar aesthetic.
- **State Management:** Observation framework with @Observable view models. @State and @Binding for local view state. @Environment for dependency injection of shared services (search engine, ML pipeline, SwiftData model context).
- **Routing:** Single-window command bar overlay activated via global hotkey (NSEvent.addGlobalMonitorForEvents). NavigationStack within Settings scene for preferences navigation. No traditional routing — command bar results drive view transitions using matchedGeometryEffect and PhaseAnimator.
- **Build Tooling:** Xcode 16+ with Swift 6 language mode. Swift Package Manager for dependency management. CoreML model compiler integrated into the build pipeline. Metal shader compilation as part of the asset catalog build phase.

## 🧠 Backend Architecture
- **Approach:** No server backend. All logic runs in-process on the user's Mac. Service layer uses Swift 6 Structured Concurrency (async/await, TaskGroups, AsyncSequence) to orchestrate parallel file search, ML inference, and UI updates without blocking the main thread.
- **API Style:** No external API. Internal service communication via direct Swift async method calls and AsyncSequence streams. Services are injected as @Observable singletons through SwiftUI @Environment.
- **Services:**
- IntentParsingService — CoreML + NaturalLanguage pipeline for on-device natural language command interpretation and intent chain extraction
- FileSearchService — SwiftData-backed indexed file metadata search with full-text and attribute queries, inspired by Spotlight indexing patterns
- SystemActionService — executes resolved intents as macOS system actions (app launch, file open, shell commands, system preferences) via NSWorkspace and scripting bridges
- IndexingService — background file system crawler using DispatchSource for file events and TaskGroup for parallel metadata extraction, writing to SwiftData store
- HotkeyService — global hotkey registration via NSEvent.addGlobalMonitorForEvents and Carbon-level hotkey APIs for reliable system-wide activation
- ShaderService — Metal shader compilation and caching for custom blur, glow, and transition effects on the command bar overlay

## 🗄 Data Layer
- **Primary Store:** SwiftData with a local SQLite backing store. Three primary models: FileMetadataRecord (indexed file attributes, content hash, path, last modified), CommandHistoryRecord (past queries, selected results, timestamps), and UserPreferenceRecord (hotkey config, indexing paths, appearance settings). Full-text search enabled via SwiftData predicates on indexed string properties.
- **Relationships:** FileMetadataRecord is standalone with no foreign keys — flat indexed records for fast retrieval. CommandHistoryRecord references FileMetadataRecord by path string for result tracking. UserPreferenceRecord is a singleton record pattern. No complex relationship graphs — optimized for read-heavy search workloads.
- **Migrations:** SwiftData lightweight migration via schema versioning. VersionedSchema conformance for each release. No manual migration scripts — rely on SwiftData automatic migration for additive schema changes. Destructive migrations (rare) trigger a re-index of the file system.

## ☁️ Infrastructure
- **Hosting:** No server hosting. Distributed as a signed and notarized macOS application via direct download (.dmg) and optionally the Mac App Store. CoreML models bundled in the app binary. No cloud infrastructure required for core functionality.
- **Scaling Strategy:** Single-user single-machine. Scaling concerns are purely local: SwiftData index size (target up to 500K file records), CoreML model memory footprint (under 150MB total), and concurrent TaskGroup parallelism bounded by available CPU cores. Incremental indexing via file system event monitoring (DispatchSource/FSEvents) avoids full re-scans.
- **CI/CD:** Xcode Cloud or GitHub Actions with xcodebuild. Pipeline stages: Swift 6 strict concurrency compilation, unit tests, CoreML model validation, notarization, and DMG packaging. No server deployment — artifacts are signed application bundles.

## ⚖️ Key Trade-offs
- macOS 15+ only: excludes users on older OS versions but enables SwiftUI 6 materials, Observation framework, and latest SwiftData APIs without compatibility shims
- CoreML-only inference: requires a model conversion pipeline from training frameworks to CoreML format, but eliminates MLX dependency overhead and guarantees Neural Engine acceleration
- Local-first with no server: maximizes privacy and eliminates latency from network calls, but means no cross-device command history without optional CloudKit opt-in
- SwiftData over Core Data: simpler API and Swift-native modeling, but less mature ecosystem and fewer escape hatches for complex query patterns
- Bundled models only in v1: guarantees offline functionality and predictable app size, but limits model updates to app releases unless optional download mechanism is added later
- NSWindow customization over pure SwiftUI: required for translucent overlay and global hotkey behavior, but introduces AppKit bridging complexity
- Metal shaders for visual effects: enables premium blur and glow aesthetics beyond standard SwiftUI materials, but requires GPU compatibility testing across all supported Mac configurations

## 📐 Non-Functional Requirements
- Sub-10ms P95 query-to-first-result latency on M1 or later Apple Silicon for all local operations
- Command bar activation-to-visible in under 200ms from global hotkey press
- Zero network calls during all core command parsing, file search, and system action operations
- Main thread never blocked during file indexing, ML inference, or search — all heavy work dispatched via Structured Concurrency
- Memory footprint under 150MB during active use with loaded CoreML models and SwiftData index
- SwiftData incremental index updates complete within 50ms for single file changes
- Graceful degradation on Intel Macs: CPU-based CoreML inference with longer but functional response times
- Application signed, notarized, and sandboxed with explicit entitlements for Full Disk Access, Accessibility, and global hotkey registration