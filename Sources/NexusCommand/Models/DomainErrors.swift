import Foundation

// MARK: - Intent Errors

enum IntentError: LocalizedError, Sendable, Equatable {
    case modelNotLoaded
    case modelNotFound
    case modelCompilationFailed(String)
    case parsingTimeout
    case emptyQuery

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            "Intent model is not loaded"
        case .modelNotFound:
            "Intent classification model not found in app bundle"
        case .modelCompilationFailed(let reason):
            "Model compilation failed: \(reason)"
        case .parsingTimeout:
            "Intent parsing exceeded time budget"
        case .emptyQuery:
            "Query is empty"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .modelNotLoaded:
            "Wait for the model to finish loading or restart the app"
        case .modelNotFound:
            "Reinstall the application to restore the model bundle"
        case .modelCompilationFailed:
            "Try restarting the app or reinstalling"
        case .parsingTimeout:
            "Try a shorter, simpler query"
        case .emptyQuery:
            "Type a command to search or execute"
        }
    }
}

// MARK: - Search Errors

enum SearchError: LocalizedError, Sendable, Equatable {
    case indexNotReady
    case invalidPredicate(String)

    var errorDescription: String? {
        switch self {
        case .indexNotReady:
            "File index is still building"
        case .invalidPredicate(let detail):
            "Invalid search query: \(detail)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .indexNotReady:
            "Please wait for indexing to complete"
        case .invalidPredicate:
            "Try simplifying your search query"
        }
    }
}

// MARK: - Action Errors

enum ActionError: LocalizedError, Sendable, Equatable {
    case permissionDenied(String)
    case appNotFound(String)
    case shellCommandFailed(stderr: String, exitCode: Int32)
    case unsupportedAction
    case commandNotAllowed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied(let detail):
            "Permission denied: \(detail)"
        case .appNotFound(let name):
            "Application not found: \(name)"
        case .shellCommandFailed(let stderr, let code):
            "Command failed (exit \(code)): \(stderr)"
        case .unsupportedAction:
            "This action type is not supported"
        case .commandNotAllowed(let cmd):
            "Command not allowed: \(cmd)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .permissionDenied:
            "Grant the required permission in System Settings > Privacy & Security"
        case .appNotFound:
            "Verify the application is installed in /Applications"
        case .shellCommandFailed:
            "Check the command syntax and try again"
        case .unsupportedAction:
            "Try a different command"
        case .commandNotAllowed:
            "Only allowlisted commands run without confirmation"
        }
    }
}

// MARK: - Index Errors

enum IndexError: LocalizedError, Sendable, Equatable {
    case pathNotAccessible(String)
    case indexCorrupted

    var errorDescription: String? {
        switch self {
        case .pathNotAccessible(let path):
            "Cannot access path: \(path)"
        case .indexCorrupted:
            "File index is corrupted"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .pathNotAccessible:
            "Check that the directory exists and Full Disk Access is granted"
        case .indexCorrupted:
            "A full re-index will be triggered automatically"
        }
    }
}

// MARK: - Hotkey Errors

enum HotkeyError: LocalizedError, Sendable, Equatable {
    case hotkeyConflict
    case accessibilityNotGranted

    var errorDescription: String? {
        switch self {
        case .hotkeyConflict:
            "Hotkey combination is already in use"
        case .accessibilityNotGranted:
            "Accessibility permission not granted"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .hotkeyConflict:
            "Choose a different key combination in Settings"
        case .accessibilityNotGranted:
            "Enable Accessibility in System Settings > Privacy & Security > Accessibility"
        }
    }
}
