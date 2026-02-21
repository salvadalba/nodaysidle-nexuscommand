<p align="center">
  <img src="https://img.shields.io/badge/macOS-15%2B-000000?style=for-the-badge&logo=apple&logoColor=white" />
  <img src="https://img.shields.io/badge/Swift-6.0-F05138?style=for-the-badge&logo=swift&logoColor=white" />
  <img src="https://img.shields.io/badge/SwiftUI-6-007AFF?style=for-the-badge&logo=swift&logoColor=white" />
  <img src="https://img.shields.io/badge/CoreML-On--Device-34C759?style=for-the-badge&logo=apple&logoColor=white" />
  <img src="https://img.shields.io/badge/License-MIT-yellow?style=for-the-badge" />
</p>

<h1 align="center">
  <br>
  Nexus Command
  <br>
</h1>

<h3 align="center">An open-source, privacy-first command launcher for macOS.<br>Zero dependencies. Zero telemetry. 100% on-device.</h3>

<p align="center">
  <b>Press Option+Space. Type what you want. Done.</b>
</p>

---

## Why NexusCommand?

Every launcher on macOS asks you to trade something — your data, your money, or your trust. Raycast phones home. Alfred charges for a Powerpack. Spotlight can't run shell commands.

**NexusCommand trades nothing.** It's built entirely with Apple-native frameworks, runs 100% on-device, and ships as a single binary with no dependencies. Your keystrokes, your files, your commands — they never leave your machine.

| | NexusCommand | Raycast | Alfred | Spotlight |
|---|:---:|:---:|:---:|:---:|
| **Open source** | Yes | No | No | No |
| **Price** | Free | Free / $8-12/mo | Free / $34+ | Free |
| **Telemetry** | None | Yes | Optional | Yes |
| **Dependencies** | Zero | Electron-based | Obj-C runtime | System |
| **On-device ML** | CoreML | Cloud AI (Pro) | No ML | Server-side |
| **Shell commands** | Yes (sandboxed) | Yes | Yes (Powerpack) | No |
| **Swift 6 strict concurrency** | Yes | N/A | N/A | N/A |
| **Custom hotkey** | Yes | Yes | Yes (Powerpack) | Limited |
| **File indexing** | FSEvents real-time | Yes | Yes | Yes |
| **Memory footprint** | ~50 MB | ~200-400 MB | ~80-150 MB | System |

---

## How It Works

```
  Option+Space
       │
       ▼
┌─────────────────────────────────────────┐
│  ┌─ 🔍 Type a command...            ─┐  │
│  └───────────────────────────────────┘  │
│                                         │
│  ▸ Launch Google Chrome    Application  │
│    Open readme.md          File         │
│    Run: ls -la             Shell        │
│    Settings: Bluetooth     System       │
│    Search: swift tutorials Web Search   │
│    2+2 = 4                 Calculator   │
└─────────────────────────────────────────┘
       │
       ▼
  50ms debounce → parallel intent + file + history search
       │
       ▼
  Press Enter → action executes
```

Type naturally. NexusCommand understands what you mean:

- **`chrome`** → launches Google Chrome (fuzzy matches `chrme` too)
- **`find readme.md`** → searches your indexed files
- **`run ls -la`** → executes in a sandboxed shell
- **`settings bluetooth`** → opens System Settings
- **`search swift concurrency`** → opens a web search
- **`2+2`** → instant calculation
- **`open Terminal and run pwd`** → compound commands

---

## Architecture

Built with zero external dependencies — only Apple SDKs:

```
┌──────────────────────────────────────────────────────────┐
│                    NexusCommandApp                         │
│              NSApplicationDelegateAdaptor                  │
│                MenuBarExtra + Settings                    │
├──────────────┬────────────────────┬───────────────────────┤
│  CommandBar  │    Intent Engine   │    File Indexer        │
│  ┌────────┐  │  ┌──────────────┐  │  ┌─────────────────┐  │
│  │NSPanel │  │  │NLTokenizer   │  │  │FSEvents monitor │  │
│  │floating│  │  │Rule-based +  │  │  │Real-time updates│  │
│  │overlay │  │  │Fuzzy matching│  │  │SwiftData store  │  │
│  └────────┘  │  └──────────────┘  │  └─────────────────┘  │
├──────────────┼────────────────────┼───────────────────────┤
│              │    Service Layer   │                        │
│  HotkeyService (Carbon + NSEvent global monitor)         │
│  FileSearchService (SwiftData + LRU cache + scoring)     │
│  CommandHistoryService (SwiftData + auto-prune)          │
│  SystemActionService (NSWorkspace + sandboxed Process)    │
│  ShaderService (Metal fallback to .ultraThinMaterial)    │
├──────────────────────────────────────────────────────────┤
│              SwiftData (ModelContainer)                    │
│  FileMetadataRecord · CommandHistoryRecord · Preferences  │
└──────────────────────────────────────────────────────────┘
```

**Key technical decisions:**

- **Swift 6 strict concurrency** — `@MainActor @Observable` view models, `@ModelActor` for SwiftData isolation, `Sendable` DTOs at every actor boundary
- **NSPanel (non-activating)** — floating command bar that doesn't steal focus from your current app, just like Raycast/Alfred
- **Carbon `RegisterEventHotKey`** — system-wide hotkey that works even when NexusCommand isn't focused, with NSEvent global monitor fallback
- **FSEvents via `FSEventStreamSetDispatchQueue`** — real-time file monitoring with sub-second index updates
- **Levenshtein fuzzy matching** — handles typos like `chrme` → Chrome, `slak` → Slack
- **LRU caches** — 100-entry file search cache + 50-entry intent cache, invalidated on file events
- **No Xcode project** — pure SwiftPM, builds with `swift build` from the command line

---

## Quick Start

### Requirements

- macOS 15 (Sequoia) or later
- Apple Silicon Mac
- Xcode 16+ (Swift 6 toolchain)

### Build & Run

```bash
git clone https://github.com/salvadalba/nodaysidle-nexuscommand.git
cd nodaysidle-nexuscommand

# Build and launch (debug)
chmod +x Scripts/compile_and_run.sh
Scripts/compile_and_run.sh debug

# Or build release + install to /Applications
chmod +x Scripts/package_app.sh
Scripts/package_app.sh release
cp -R NexusCommand.app /Applications/
open /Applications/NexusCommand.app
```

### First Launch

1. Grant **Accessibility** permission when prompted (System Settings > Privacy & Security > Accessibility)
2. The app indexes your Documents, Desktop, Downloads, and Applications
3. Press **Option+Space** to open the command bar
4. Type and press Enter

---

## Usage

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| **Option+Space** | Open / close command bar (configurable) |
| **Up / Down** | Navigate results |
| **Return** | Execute selected result |
| **Escape** | Dismiss command bar |
| **Cmd+,** | Open Settings |

### Supported Actions

| Prefix | Action | Example |
|--------|--------|---------|
| *(app name)* | Launch app | `chrome`, `slack`, `xcode` |
| `open` / `launch` | Launch app | `open Safari` |
| `find` / `locate` | Search files | `find readme.md` |
| `run` / `exec` | Shell command | `run ls -la` |
| `settings` | System Settings | `settings bluetooth` |
| `search` / `google` | Web search | `search swift tutorials` |
| *(math)* | Calculate | `2+2`, `100 * 0.15` |
| `and` / `then` | Compound | `open Terminal and run pwd` |

### Settings

Open from the menu bar icon or **Cmd+,**:

- **General** — hotkey recorder, launch at login, menu bar icon toggle
- **Indexing** — manage indexed directories, max file count, force re-index
- **Appearance** — color scheme (system/light/dark), command bar width (500-900pt)

---

## Project Structure

```
Sources/NexusCommand/
  App/            NexusCommandApp.swift, ServiceContainer.swift
  Models/         SwiftData models (FileMetadata, CommandHistory, Preferences)
  Services/       HotkeyService, IndexingService, IntentParsingService,
                  FileSearchService, CommandHistoryService, SystemActionService,
                  ShaderService, LRUCache
  CommandBar/     CommandBarPanel (NSPanel), CommandBarView, ViewModel
  MenuBar/        NexusMenuBarExtra
  Settings/       SettingsView, SettingsViewModel, HotkeyRecorderView
  Shaders/        BlurShader.metal, GlowShader.metal

Tests/
  NexusCommandTests/        42 unit + integration tests
  NexusCommandUITests/      E2E test stubs

Scripts/
  compile_and_run.sh        Dev build loop
  package_app.sh            .app bundle packaging
  build-dmg.sh              DMG creation for distribution
  generate_icon.swift       Programmatic icon generation
```

---

## Testing

```bash
# Run all 42 tests
swift test

# Run with verbose output
swift test --verbose 2>&1 | grep -E "(passed|failed|Test run)"
```

Test coverage:
- **IntentParsingServiceTests** — all 6 action types, compound queries, edge cases
- **FileSearchServiceTests** — text search, date filters, UTType filters, relevance scoring
- **SystemActionServiceTests** — app launch, shell allowlisting, calculator
- **IndexingAndHistoryTests** — crawl, FSEvents handling, history CRUD, pruning
- **QueryPipelineIntegrationTests** — end-to-end with 100 seeded records

---

## Privacy

- **All processing is on-device.** No network calls in core modules.
- **No telemetry, no analytics, no tracking.**
- **File index and history** stored locally at `~/Library/Application Support/NexusCommand/`
- **Web searches** only leave your machine when you explicitly execute one (opens your default browser)
- **Shell commands** are sandboxed to an allowlist: `open`, `defaults`, `osascript`, `pbcopy`, `pbpaste`
- **CI enforces** no `URLSession` imports in core service modules

---

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Run `swift test` and ensure all 42 tests pass
4. Commit your changes
5. Push to the branch and open a Pull Request

---

## License

MIT License. See [LICENSE](LICENSE) for details.

---

<p align="center">
  Built with Swift 6, SwiftUI, SwiftData, CoreML, and Metal.<br>
  No Electron. No dependencies. No compromises.<br><br>
  <b>⌥ Space — and you're there.</b>
</p>
