import AppKit
import Foundation

// MARK: - Intent Action

enum IntentAction: String, Sendable, Equatable, CaseIterable, Codable {
    case openFile
    case launchApp
    case runShellCommand
    case systemPreference
    case webSearch
    case calculate
}

// MARK: - Parsed Intent

struct ParsedIntent: Sendable, Equatable {
    let action: IntentAction
    let parameters: [String: String]
    let confidence: Float
}

// MARK: - Intent Chain

struct IntentChain: Sendable, Equatable {
    let intents: [ParsedIntent]
    let confidence: Float
    let rawTokens: [String]

    var primaryIntent: ParsedIntent? { intents.first }
    var isCompound: Bool { intents.count > 1 }
}

// MARK: - Action Result

struct ActionResult: Sendable, Equatable {
    let success: Bool
    let output: String?
    let openedURL: URL?
    let launchedApp: String?

    static func ok(output: String? = nil, openedURL: URL? = nil, launchedApp: String? = nil) -> ActionResult {
        ActionResult(success: true, output: output, openedURL: openedURL, launchedApp: launchedApp)
    }

    static func failed(output: String) -> ActionResult {
        ActionResult(success: false, output: output, openedURL: nil, launchedApp: nil)
    }
}

// MARK: - Search Result Item

struct SearchResultItem: Identifiable, Sendable, Equatable {
    let id: UUID
    let title: String
    let subtitle: String
    let icon: String // SF Symbol name
    let action: IntentAction
    let parameters: [String: String]
    let relevanceScore: Float
    let source: ResultSource

    enum ResultSource: Sendable, Equatable {
        case fileSearch
        case intentParsing
        case history
    }
}

// MARK: - Search Filters

struct SearchFilters: Sendable, Equatable, Hashable {
    var fileTypes: [String]?  // UTType identifiers
    var modifiedAfter: Date?
    var modifiedBefore: Date?
    var maxResults: Int = 20
}

// MARK: - File Search Result

// MARK: - Command History DTO (Sendable)

struct CommandHistoryDTO: Sendable, Identifiable, Equatable {
    let id: UUID
    let query: String
    let selectedResultPath: String?
    let timestamp: Date
    let executionCount: Int
}

// MARK: - File Metadata DTO (Sendable)

struct FileMetadataDTO: Sendable {
    let filePath: String
    let fileName: String
    let fileExtension: String
    let fileType: String
    let fileSize: Int64
    let modifiedDate: Date
    let contentSnippet: String?
    let contentHash: String
}

struct FileSearchResult: Sendable, Equatable {
    let path: String
    let fileName: String
    let fileType: String
    let lastModified: Date
    let contentSnippet: String?
    let relevanceScore: Float
}

// MARK: - Index Progress

struct IndexProgress: Sendable {
    let totalFiles: Int
    let processedFiles: Int
    let currentPath: String
}

// MARK: - Index Status

enum IndexStatus: Sendable, Equatable {
    case idle
    case indexing
    case error(String)
}

// MARK: - Model Status

enum ModelStatus: Sendable, Equatable {
    case loading
    case loaded
    case failed
}

// MARK: - File System Event

struct FileSystemEvent: Sendable {
    let path: URL
    let eventType: FileEventType
}

enum FileEventType: Sendable {
    case created
    case modified
    case deleted
    case renamed
}

// MARK: - Hotkey Combo

struct HotkeyCombo: Sendable, Equatable, Codable {
    let keyCode: UInt16
    let modifiers: UInt

    static let defaultCombo = HotkeyCombo(keyCode: 49, modifiers: 524288) // Option+Space

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers)
    }

    var displayString: String {
        var parts: [String] = []
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        if flags.contains(.command) { parts.append("⌘") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.control) { parts.append("⌃") }
        parts.append(keyCodeToString(keyCode))
        return parts.joined()
    }

    private func keyCodeToString(_ code: UInt16) -> String {
        switch code {
        case 49: return "Space"
        case 36: return "↩"
        case 48: return "⇥"
        case 53: return "⎋"
        default:
            if let scalar = UnicodeScalar(code) {
                return String(Character(scalar)).uppercased()
            }
            return "Key(\(code))"
        }
    }
}

