# NexusCommand User Guide

## What is NexusCommand?

NexusCommand is a macOS command center that lives in your menu bar. Press a keyboard shortcut, type what you want to do, and NexusCommand figures out the rest — launch apps, find files, run shell commands, do quick math, open System Settings, or search the web.

It runs entirely on-device with no network calls for core functionality.

---

## Installation

### Requirements

- macOS 15 (Sequoia) or later
- Apple Silicon Mac

### From Source

```bash
git clone <repo-url> && cd nodaysidle-nexuscommand

# Build and run (debug)
Scripts/compile_and_run.sh debug

# Build release
Scripts/compile_and_run.sh release
```

### From DMG (Release)

1. Open the `.dmg` file
2. Drag **Nexus Command** to your Applications folder
3. Launch from Applications or Spotlight

### First Launch

On first launch, NexusCommand will:

1. **Request Accessibility permission** — required for the global hotkey to work system-wide. Grant this in **System Settings > Privacy & Security > Accessibility**.
2. **Create default preferences** — stored in `~/Library/Application Support/NexusCommand/`
3. **Begin indexing** your Documents, Desktop, Downloads, and Applications folders

NexusCommand appears as a menu bar icon (a command symbol). It has no Dock icon — this is intentional for a utility that should stay out of your way.

---

## Using the Command Bar

### Opening

| Method | How |
|--------|-----|
| **Keyboard shortcut** | Press **Option + Space** (default — configurable in Settings) |
| **Menu bar** | Click the menu bar icon, then "Open Command Bar" |

### Typing Commands

Just start typing. NexusCommand uses natural language parsing to figure out what you mean:

| What you type | What happens |
|---------------|-------------|
| `open Safari` | Launches Safari |
| `find readme.md` | Searches your indexed files for "readme.md" |
| `run ls` | Runs `ls` in a shell |
| `settings bluetooth` | Opens System Settings > Bluetooth |
| `search swift tutorials` | Opens a web search for "swift tutorials" |
| `2+2` | Calculates and shows the result: 4 |
| `open Terminal and run pwd` | Compound command: launches Terminal, then runs `pwd` |

Results appear instantly as you type (50ms debounce). The command bar merges results from three sources:

- **Intent parsing** — understands what action you want
- **File search** — finds matching files in your index
- **History** — surfaces commands you've used before

### Navigating Results

| Key | Action |
|-----|--------|
| **Up/Down arrows** | Move selection through results |
| **Return** | Execute the selected result |
| **Escape** | Dismiss the command bar |
| **Click** | Execute a result directly |

When the command bar is empty, it shows your **most frequently used commands** as suggestions.

### Result Types

Each result row shows an icon indicating its type:

| Icon | Type | Description |
|------|------|-------------|
| App badge | **Application** | Launch a macOS app |
| Document | **File** | Open a file |
| Terminal | **Shell Command** | Run a terminal command |
| Gear | **System Settings** | Open a Settings pane |
| Globe | **Web Search** | Search the web in your default browser |
| Function | **Calculator** | Evaluate a math expression |

---

## The Menu Bar

Click the NexusCommand icon in your menu bar to see:

- **Open Command Bar** (Cmd+O) — alternative way to activate
- **Recent Commands** — your most-used commands for quick access
- **Indexing Status** — shows a spinner while indexing, or the total indexed file count
- **Error Banner** — if the file index is corrupted, a "Repair" button appears here
- **Settings** (Cmd+,) — open the preferences window
- **Quit NexusCommand** (Cmd+Q)

---

## Settings

Open Settings from the menu bar or press **Cmd+,** from the command bar.

### General Tab

- **Activation Hotkey** — click the recorder and press your preferred key combination. Default is Option+Space. The recorder captures the exact modifier + key combo.
- **Launch at Login** — toggle to auto-start NexusCommand when you log in (uses SMAppService)
- **Show Menu Bar Icon** — toggle the menu bar icon visibility

### Indexing Tab

- **Indexed Directories** — add or remove folders that NexusCommand scans. Click "Add Directory..." to pick a folder. Click the minus icon to remove one.
- **Max Indexed Files** — limit on total indexed files (default: 500,000)
- **Re-index Now** — force a full re-index of all configured directories. Useful after moving large numbers of files.

### Appearance Tab

- **Color Scheme** — System / Light / Dark
- **Command Bar Width** — slider from 500pt to 900pt (default: 680pt)

---

## Supported Actions

### Launch Applications

Type `open`, `launch`, or `start` followed by an app name:

```
open Xcode
launch Slack
start Terminal
```

NexusCommand recognizes common apps by name (Safari, Chrome, Finder, Xcode, VS Code, Slack, Discord, Zoom, Spotify, etc.) and also checks `/Applications/` for matches.

### Find and Open Files

Type `find`, `search`, or `locate` followed by a filename or keyword:

```
find report.pdf
search budget spreadsheet
locate main.swift
```

Results are ranked by:
- **Text match** (70% weight) — exact match > prefix > contains > snippet match > fuzzy token overlap
- **Recency** (30% weight) — recently modified files score higher

### Run Shell Commands

Type `run`, `exec`, or `execute` followed by a command:

```
run ls -la
run open .
run pbcopy
```

**Security note:** Only these commands are allowed: `open`, `defaults`, `osascript`, `pbcopy`, `pbpaste`. Dangerous commands like `rm`, `sudo`, etc. are blocked. This is a safety allowlist, not a limitation — it prevents accidental destructive operations from a quick-launch tool.

### System Settings

Type `settings` or `preferences` followed by the pane name:

```
settings bluetooth
settings network
settings displays
```

This opens the corresponding pane in System Settings via URL scheme.

### Web Search

Type `search`, `google`, or `web` followed by your query:

```
search how to use SwiftData
google macOS Sequoia features
```

Opens your default browser with the search query.

### Calculator

Type any math expression directly:

```
2+2
100 * 0.15
(50 + 30) / 4
3.14 * 10 ^ 2
```

Supports: `+`, `-`, `*`, `/`, `^`, `%`, parentheses, decimals.

### Compound Commands

Chain actions with `and`, `then`, or `also`:

```
open Terminal and run pwd
launch Safari then search swift documentation
```

Each part is parsed and executed independently.

---

## File Indexing

NexusCommand maintains a local file index using SwiftData for instant search results.

### What Gets Indexed

- File path, name, extension, type (UTI), size
- Creation and modification dates
- First 500 characters of text files (for content search)
- SHA256 content hash (for change detection)

### Real-Time Monitoring

After the initial index, NexusCommand monitors your configured directories via FSEvents. When files are created, modified, deleted, or renamed, the index updates automatically within 500ms.

### Index Storage

The index database lives at:

```
~/Library/Application Support/NexusCommand/nexus.store
```

### Expired History Pruning

Command history older than 90 days is automatically pruned on each app launch.

---

## Performance

NexusCommand is designed to stay under 50 MB of memory at idle:

- **Query debounce**: 50ms — prevents excessive searches while typing
- **Search cache**: LRU cache (100 entries) with cache-hit-rate tracking
- **Intent cache**: LRU cache (50 entries) for parsed queries
- **Bounded indexing**: Uses `activeProcessorCount - 2` concurrent tasks during crawl
- **Metrics**: Memory footprint, cache hit rate, and index count logged every 60 seconds via `os.Logger`

---

## Keyboard Shortcut Reference

| Shortcut | Context | Action |
|----------|---------|--------|
| Option+Space | Global | Open/close command bar (configurable) |
| Escape | Command bar | Dismiss |
| Up/Down | Command bar | Navigate results |
| Return | Command bar | Execute selected result |
| Cmd+O | Menu bar | Open command bar |
| Cmd+, | Menu bar | Open Settings |
| Cmd+Q | Menu bar | Quit NexusCommand |

---

## Troubleshooting

### Command bar doesn't appear when I press the hotkey

1. Check **System Settings > Privacy & Security > Accessibility** — NexusCommand must be listed and enabled
2. If another app uses the same shortcut, change NexusCommand's hotkey in **Settings > General > Activation Hotkey**
3. Try clicking "Open Command Bar" from the menu bar to verify the app is running

### The hotkey conflicts with Spotlight

By default NexusCommand uses Option+Space. If another app already claims that shortcut, either:
- Change NexusCommand's hotkey in Settings
- Disable the conflicting app's shortcut

### File search returns no results

1. Open **Settings > Indexing** and verify directories are listed
2. Click **"Re-index Now"** to force a fresh index
3. Check the menu bar for indexing status — wait for indexing to complete
4. Ensure the files are in directories NexusCommand is configured to scan

### "File index corrupted" error in menu bar

Click the **"Repair"** button in the menu bar dropdown. This triggers a full re-index. If the problem persists, quit NexusCommand, delete `~/Library/Application Support/NexusCommand/nexus.store`, and relaunch.

### App uses too much memory during indexing

Indexing large directory trees (100K+ files) temporarily increases memory usage. NexusCommand bounds concurrency to `CPU cores - 2` to avoid overwhelming the system. Memory usage returns to normal after indexing completes.

### Shell command is blocked

NexusCommand only allows these shell commands: `open`, `defaults`, `osascript`, `pbcopy`, `pbpaste`. This is a security measure — a command launcher shouldn't be able to run destructive operations like `rm -rf`. For unrestricted shell access, use Terminal.

### Menu bar icon is missing

Check **Settings > General > Show Menu Bar Icon**. If the icon is enabled but not visible, it may be hidden by macOS's menu bar overflow — try expanding the menu bar or reducing other menu bar items.

---

## Building from Source

### Prerequisites

- Xcode 16+ (for Swift 6 toolchain)
- macOS 15+

### Commands

```bash
# Build (debug)
swift build

# Run tests (42 tests across 6 suites)
swift test

# Package as .app and launch
Scripts/compile_and_run.sh debug

# Build release .app
Scripts/package_app.sh release

# Build signed DMG for distribution
Scripts/build-dmg.sh
```

### Project Structure

```
Sources/NexusCommand/
  App/              NexusCommandApp.swift, ServiceContainer.swift
  Models/           SwiftData models + domain types
  Services/         HotkeyService, IndexingService, IntentParsingService,
                    FileSearchService, CommandHistoryService, SystemActionService,
                    ShaderService, LRUCache
  CommandBar/       CommandBarPanel, CommandBarView, CommandBarViewModel
  MenuBar/          NexusMenuBarExtra
  Settings/         SettingsView, SettingsViewModel, HotkeyRecorderView
  Shaders/          BlurShader.metal, GlowShader.metal

Tests/NexusCommandTests/
  IntentParsingServiceTests.swift
  FileSearchServiceTests.swift
  SystemActionServiceTests.swift
  IndexingAndHistoryTests.swift
  QueryPipelineIntegrationTests.swift
  CommandBarE2ETests.swift
```

---

## Data & Privacy

- All processing happens on-device. No data is sent to any server.
- File index and command history are stored locally in `~/Library/Application Support/NexusCommand/`.
- Web search queries are sent to your default browser's search engine only when you explicitly execute a web search action.
- Command history can be cleared at any time via the `clearHistory()` API or by deleting the store file.
