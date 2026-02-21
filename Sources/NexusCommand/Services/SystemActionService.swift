import AppKit
import Foundation
import os

@MainActor @Observable
final class SystemActionService {
    private static let logger = Logger(subsystem: "com.nexuscommand", category: "action")

    private let allowedCommands: Set<String> = ["open", "defaults", "osascript", "pbcopy", "pbpaste"]

    func execute(intent: ParsedIntent) async throws -> ActionResult {
        Self.logger.info("Executing action: \(intent.action.rawValue)")

        switch intent.action {
        case .openFile:
            return try await openFile(intent: intent)
        case .launchApp:
            return try await launchApp(intent: intent)
        case .runShellCommand:
            return try await runShellCommand(intent: intent)
        case .systemPreference:
            return try openSystemPreference(intent: intent)
        case .webSearch:
            return try openWebSearch(intent: intent)
        case .calculate:
            return try evaluateExpression(intent: intent)
        }
    }

    // MARK: - Open File

    private func openFile(intent: ParsedIntent) async throws -> ActionResult {
        if let path = intent.parameters["path"] {
            let url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
            guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
                throw ActionError.appNotFound(path)
            }
            let config = NSWorkspace.OpenConfiguration()
            try await NSWorkspace.shared.open(url, configuration: config)
            return .ok(openedURL: url)
        }
        // If it's a query, just return the intent for the UI to handle as search
        return .ok(output: "Search: \(intent.parameters["query"] ?? "")")
    }

    // MARK: - Launch App

    private func launchApp(intent: ParsedIntent) async throws -> ActionResult {
        guard let appName = intent.parameters["app"] else {
            throw ActionError.appNotFound("unknown")
        }

        let cleanName = appName.trimmingCharacters(in: .whitespaces)
        let appURL = resolveAppURL(name: cleanName)

        guard let appURL else {
            throw ActionError.appNotFound(cleanName)
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        try await NSWorkspace.shared.openApplication(at: appURL, configuration: config)

        Self.logger.info("Launched app: \(cleanName)")
        return .ok(launchedApp: cleanName)
    }

    private func resolveAppURL(name: String) -> URL? {
        // Exact path checks first (fast path)
        let candidates = [
            "/Applications/\(name).app",
            "/Applications/\(name.capitalized).app",
            "/System/Applications/\(name).app",
            "/System/Applications/\(name.capitalized).app",
            "/Applications/Utilities/\(name).app",
            "/Applications/Utilities/\(name.capitalized).app",
        ]

        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        // Case-insensitive scan of /Applications
        let dirs = ["/Applications", "/System/Applications", "/Applications/Utilities"]
        let lowerName = name.lowercased()
        for dir in dirs {
            guard let contents = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for item in contents where item.hasSuffix(".app") {
                let appName = String(item.dropLast(4))
                if appName.lowercased() == lowerName {
                    return URL(fileURLWithPath: "\(dir)/\(item)")
                }
            }
        }

        // Try NSWorkspace bundle ID resolution
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.\(name.lowercased())") {
            return url
        }

        return nil
    }

    // MARK: - Shell Command

    private func runShellCommand(intent: ParsedIntent) async throws -> ActionResult {
        guard let command = intent.parameters["command"] else {
            throw ActionError.shellCommandFailed(stderr: "No command specified", exitCode: 1)
        }

        let baseCommand = command.split(separator: " ").first.map(String.init) ?? command

        if !allowedCommands.contains(baseCommand) {
            // In production, show confirmation dialog. For now, deny non-allowlisted commands.
            Self.logger.warning("Command not in allowlist: \(baseCommand)")
            throw ActionError.commandNotAllowed(command)
        }

        return try await executeShell(command: command)
    }

    private func executeShell(command: String) async throws -> ActionResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw ActionError.shellCommandFailed(stderr: stderr, exitCode: process.terminationStatus)
        }

        Self.logger.info("Shell command completed: \(command, privacy: .private)")
        return .ok(output: stdout.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - System Preferences

    private func openSystemPreference(intent: ParsedIntent) throws -> ActionResult {
        let pane = intent.parameters["pane"] ?? ""
        let paneMap: [String: String] = [
            "general": "com.apple.preference.general",
            "appearance": "com.apple.preference.general",
            "desktop": "com.apple.preference.desktopscreeneffect",
            "dock": "com.apple.preference.dock",
            "network": "com.apple.preference.network",
            "bluetooth": "com.apple.preference.bluetooth",
            "sound": "com.apple.preference.sound",
            "displays": "com.apple.preference.displays",
            "keyboard": "com.apple.preference.keyboard",
            "trackpad": "com.apple.preference.trackpad",
            "mouse": "com.apple.preference.mouse",
            "printers": "com.apple.preference.printfax",
            "security": "com.apple.preference.security",
            "privacy": "com.apple.preference.security",
            "battery": "com.apple.preference.battery",
            "notifications": "com.apple.preference.notifications",
            "users": "com.apple.preference.users",
            "accessibility": "com.apple.preference.universalaccess",
        ]

        let paneID = paneMap[pane.lowercased()] ?? pane
        let urlString = paneID.isEmpty ? "x-apple.systempreferences:" : "x-apple.systempreferences:\(paneID)"

        guard let url = URL(string: urlString) else {
            throw ActionError.unsupportedAction
        }

        NSWorkspace.shared.open(url)
        return .ok(openedURL: url)
    }

    // MARK: - Web Search

    private func openWebSearch(intent: ParsedIntent) throws -> ActionResult {
        guard let query = intent.parameters["query"], !query.isEmpty else {
            throw ActionError.unsupportedAction
        }

        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.google.com/search?q=\(encoded)") else {
            throw ActionError.unsupportedAction
        }

        NSWorkspace.shared.open(url)
        return .ok(openedURL: url)
    }

    // MARK: - Calculate

    private func evaluateExpression(intent: ParsedIntent) throws -> ActionResult {
        guard let expression = intent.parameters["expression"] else {
            throw ActionError.unsupportedAction
        }

        // Sanitize the expression
        let sanitized = expression
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "^", with: "**")
            .trimmingCharacters(in: .whitespaces)

        let nsExpression = NSExpression(format: sanitized)
        guard let result = nsExpression.expressionValue(with: nil, context: nil) else {
            return .failed(output: "Invalid expression")
        }

        let output = "\(sanitized) = \(result)"
        Self.logger.debug("Calculated: \(output)")
        return .ok(output: output)
    }
}
