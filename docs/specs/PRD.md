# Nexus Command

## 🎯 Product Vision
A premium macOS command center that delivers sub-10ms query latency through native Swift performance, on-device ML intent parsing, and a translucent always-available command bar — combining Raycast-level polish with local-first privacy and zero cloud exposure.

## ❓ Problem Statement
Power users on macOS lack a unified command interface that combines fast file search, intelligent intent parsing, and system-level actions without shipping data to the cloud or sacrificing responsiveness. Existing tools either require network connectivity for AI features, suffer from Electron-based performance overhead, or fail to deeply integrate with macOS system capabilities.

## 🎯 Goals
- Deliver sub-10ms query latency for all local operations using Metal and Neural Engine on Apple Silicon
- Parse user intent entirely on-device using CoreML and NaturalLanguage frameworks with no network dependency
- Provide a polished, always-available command bar with translucent SwiftUI 6 materials rivaling Raycast in visual quality
- Index and retrieve local file metadata using SwiftData with Spotlight-style search capabilities
- Maintain a strict local-first architecture with zero cloud data exposure by default
- Enable parallel file search, ML inference, and UI updates using Swift 6 Structured Concurrency without blocking the main thread

## 🚫 Non-Goals
- Supporting macOS versions earlier than macOS 15 Sequoia
- Building a server-side backend or requiring any cloud infrastructure for core functionality
- Direct loading of Hugging Face models without CoreML conversion pipeline
- Cross-platform support for iOS, iPadOS, or non-Apple platforms
- Replacing Spotlight or Finder as the default system search
- Implementing MLX-based inference as a primary inference path

## 👥 Target Users
- macOS power users on Apple Silicon who want a fast, keyboard-driven command interface
- Privacy-conscious professionals who require on-device AI without cloud data transmission
- Developers and knowledge workers who need rapid file search, app launching, and system actions from a single entry point
- Users of existing command launchers (Raycast, Alfred) seeking deeper OS integration and native performance

## 🧩 Core Features
- Global hotkey-activated translucent command bar using NSWindow customization with .ultraThinMaterial and .regularMaterial
- On-device intent chain parsing via CoreML and NaturalLanguage frameworks for natural language command interpretation
- SwiftData-backed local file metadata index with Spotlight-style full-text and attribute search
- Menu bar presence via MenuBarExtra for always-available access and quick actions
- Animated result transitions using matchedGeometryEffect, PhaseAnimator, and TimelineView for premium feel
- Metal shader-driven custom blur and glow effects for the command bar overlay
- Parallel search and inference pipeline using async/await and TaskGroups for non-blocking responsiveness
- Settings scene for user preferences including hotkey configuration, indexing paths, and appearance options
- Optional CloudKit sync for settings and command history across devices

## ⚙️ Non-Functional Requirements
- Sub-10ms latency for local query execution and result rendering on Apple Silicon
- Zero network calls for all core command parsing and file search operations
- Main thread never blocked during file indexing, ML inference, or search operations
- App launch to command bar visible in under 200ms from global hotkey press
- SwiftData index updates must complete within 50ms for incremental file changes
- Memory footprint under 150MB during active use with loaded CoreML models
- Graceful degradation on Intel Macs with longer but functional ML inference times

## 📊 Success Metrics
- P95 query-to-first-result latency under 10ms on M1 or later Apple Silicon
- On-device intent parsing accuracy above 92% for supported command patterns
- Command bar activation-to-visible time under 200ms measured via Instruments
- User retention rate above 60% at 30 days post-install
- Zero unintentional network requests logged during core feature usage
- File metadata index covers 95% of user-specified directories within first indexing pass

## 📌 Assumptions
- Users are running macOS 15 Sequoia or later on Apple Silicon hardware
- CoreML models can be pre-converted and bundled with the application binary
- NaturalLanguage framework tokenization is sufficient for command intent extraction without custom tokenizers
- SwiftData performance is adequate for indexing up to 500,000 file metadata records
- Users will grant Full Disk Access or equivalent permissions for comprehensive file indexing
- Metal shaders for blur and glow effects perform consistently across all supported GPU configurations
- The Observation framework with @Observable provides sufficient reactivity for real-time search result updates

## ❓ Open Questions
- What is the CoreML model conversion pipeline for intent parsing — custom trained or fine-tuned from existing NLU models?
- Should CloudKit sync be opt-in during onboarding or buried in settings?
- How should the app handle Intel Mac users where Neural Engine is unavailable — CPU fallback or feature gating?
- What is the maximum acceptable initial indexing time for a fresh install on a large filesystem?
- Should plugin or extension support be scoped for v1, or deferred to a future release?
- How do we handle Accessibility permissions and sandboxing constraints for global hotkey and system-wide actions?
- What is the update and model distribution strategy — bundled models only or optional model downloads post-install?