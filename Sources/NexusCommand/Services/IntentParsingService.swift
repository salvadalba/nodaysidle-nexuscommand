import Foundation
import NaturalLanguage
import os

@MainActor @Observable
final class IntentParsingService {
    private static let logger = Logger(subsystem: "com.nexuscommand", category: "intent")
    private static let signposter = OSSignposter(subsystem: "com.nexuscommand", category: "intent")

    private(set) var modelStatus: ModelStatus = .loading
    private let cache = LRUCache<String, IntentChain>(capacity: 50)
    private let tokenizer = NLTokenizer(unit: .word)

    // Conjunction patterns for splitting compound queries
    private let conjunctions: Set<String> = ["and", "then", "also"]

    func warmup() async {
        modelStatus = .loading
        Self.logger.info("Warming up intent parsing model")
        // Rule-based parser requires no model loading, but simulate warmup for CoreML slot
        // In production, load the .mlmodelc bundle here
        try? await Task.sleep(for: .milliseconds(50))
        modelStatus = .loaded
        Self.logger.info("Intent parsing model ready")
    }

    func parse(query: String) async throws -> IntentChain {
        guard modelStatus == .loaded else { throw IntentError.modelNotLoaded }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { !$0.isNewline && $0.asciiValue != nil || !$0.isASCII }
        let truncated = String(trimmed.prefix(500))

        guard !truncated.isEmpty else { throw IntentError.emptyQuery }

        let normalized = truncated.lowercased()
        if let cached = cache.get(normalized) {
            Self.logger.debug("Cache hit for intent: \(normalized, privacy: .private)")
            return cached
        }

        let signpostID = Self.signposter.makeSignpostID()
        let state = Self.signposter.beginInterval("MLInference", id: signpostID)
        defer { Self.signposter.endInterval("MLInference", state) }

        // Tokenize
        tokenizer.string = truncated
        var tokens: [String] = []
        tokenizer.enumerateTokens(in: truncated.startIndex..<truncated.endIndex) { range, _ in
            tokens.append(String(truncated[range]))
            return true
        }

        // Split compound queries
        let segments = splitOnConjunctions(tokens: tokens, originalQuery: truncated)

        var intents: [ParsedIntent] = []
        for segment in segments {
            let intent = classifyIntent(tokens: segment.tokens, text: segment.text)
            intents.append(intent)
        }

        let overallConfidence = intents.map(\.confidence).min() ?? 0.0
        let chain = IntentChain(intents: intents, confidence: overallConfidence, rawTokens: tokens)

        if chain.confidence >= 0.5 {
            cache.set(normalized, value: chain)
        }

        Self.logger.debug("Parsed '\(truncated, privacy: .private)' → \(intents.count) intent(s), confidence: \(overallConfidence)")
        return chain
    }

    // MARK: - Rule-Based Classification

    private struct QuerySegment {
        let tokens: [String]
        let text: String
    }

    private func splitOnConjunctions(tokens: [String], originalQuery: String) -> [QuerySegment] {
        // Find conjunction positions in the token list
        let conjunctionPositions: [Int] = tokens.enumerated().compactMap { (i, token) in
            conjunctions.contains(token.lowercased()) && i > 0 ? i : nil
        }

        guard !conjunctionPositions.isEmpty else {
            return [QuerySegment(tokens: tokens, text: originalQuery)]
        }

        // Split the original text on conjunction word boundaries to preserve punctuation
        var segments: [QuerySegment] = []
        var remaining = originalQuery

        for conjunction in conjunctionPositions {
            let word = tokens[conjunction]
            // Match the conjunction surrounded by whitespace in the original text
            guard let range = remaining.range(of: " \(word) ", options: .caseInsensitive) else { continue }

            let before = String(remaining[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            if !before.isEmpty {
                segments.append(QuerySegment(tokens: tokenizeText(before), text: before))
            }
            remaining = String(remaining[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }

        if !remaining.isEmpty {
            segments.append(QuerySegment(tokens: tokenizeText(remaining), text: remaining))
        }

        return segments.isEmpty ? [QuerySegment(tokens: tokens, text: originalQuery)] : segments
    }

    private func tokenizeText(_ text: String) -> [String] {
        let t = NLTokenizer(unit: .word)
        t.string = text
        var result: [String] = []
        t.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            result.append(String(text[range]))
            return true
        }
        return result
    }

    private func classifyIntent(tokens: [String], text: String) -> ParsedIntent {
        let lowered = text.lowercased().trimmingCharacters(in: .whitespaces)
        let lowerTokens = tokens.map { $0.lowercased() }

        // Calculate — detect math expressions
        if isMathExpression(lowered) {
            return ParsedIntent(action: .calculate, parameters: ["expression": text.trimmingCharacters(in: .whitespaces)], confidence: 0.95)
        }

        // Early check: if the FULL query matches an app name (handles "Google Chrome", "VS Code", etc.)
        if isLikelyApp(lowered) {
            return ParsedIntent(action: .launchApp, parameters: ["app": text.trimmingCharacters(in: .whitespaces)], confidence: 0.9)
        }

        // Fuzzy app match for typos (e.g. "chrme" → "Chrome", "gogle chrome" → "Google Chrome")
        if let fuzzyMatch = fuzzyMatchApp(lowered) {
            return ParsedIntent(action: .launchApp, parameters: ["app": fuzzyMatch], confidence: 0.75)
        }

        // Extract text after the first word from the ORIGINAL text (preserves punctuation)
        let rest = textAfterFirstWord(text)

        // System Preferences
        if lowered.hasPrefix("settings") || lowered.hasPrefix("preferences") ||
           lowered.hasPrefix("system preferences") || lowered.hasPrefix("system settings") {
            let pane = text.replacingOccurrences(of: "(?i)^(settings|preferences|system preferences|system settings)\\s*", with: "", options: .regularExpression)
            return ParsedIntent(action: .systemPreference, parameters: ["pane": pane.trimmingCharacters(in: .whitespaces)], confidence: 0.85)
        }

        // Web Search
        if lowerTokens.first == "search" || lowerTokens.first == "google" || lowerTokens.first == "web" {
            return ParsedIntent(action: .webSearch, parameters: ["query": rest.lowercased()], confidence: 0.85)
        }

        // Shell Command
        if lowerTokens.first == "run" || lowerTokens.first == "exec" || lowerTokens.first == "execute" {
            return ParsedIntent(action: .runShellCommand, parameters: ["command": rest], confidence: 0.9)
        }

        // Launch App
        if lowerTokens.first == "open" || lowerTokens.first == "launch" || lowerTokens.first == "start" {
            if isLikelyApp(rest) {
                return ParsedIntent(action: .launchApp, parameters: ["app": rest], confidence: 0.9)
            }
            if let fuzzyMatch = fuzzyMatchApp(rest.lowercased()) {
                return ParsedIntent(action: .launchApp, parameters: ["app": fuzzyMatch], confidence: 0.8)
            }
            return ParsedIntent(action: .openFile, parameters: ["path": rest], confidence: 0.8)
        }

        // Find File
        if lowerTokens.first == "find" || lowerTokens.first == "locate" {
            return ParsedIntent(action: .openFile, parameters: ["query": rest], confidence: 0.85)
        }

        // Default to file search
        return ParsedIntent(action: .openFile, parameters: ["query": text], confidence: 0.6)
    }

    private func textAfterFirstWord(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let spaceIndex = trimmed.firstIndex(of: " ") else { return "" }
        return String(trimmed[trimmed.index(after: spaceIndex)...]).trimmingCharacters(in: .whitespaces)
    }

    private func isMathExpression(_ text: String) -> Bool {
        let mathPattern = #"^[\d\s\+\-\*\/\(\)\.\,\%\^]+$"#
        return text.range(of: mathPattern, options: .regularExpression) != nil && text.contains(where: { "+-*/^%".contains($0) })
    }

    // Known apps with their canonical names for display/launch
    private static let knownApps: [(canonical: String, aliases: [String])] = [
        ("Safari", ["safari"]),
        ("Google Chrome", ["google chrome", "chrome"]),
        ("Firefox", ["firefox"]),
        ("Terminal", ["terminal"]),
        ("iTerm", ["iterm", "iterm2"]),
        ("Finder", ["finder"]),
        ("Xcode", ["xcode"]),
        ("Visual Studio Code", ["vscode", "visual studio code", "vs code", "code"]),
        ("Notes", ["notes"]),
        ("Mail", ["mail"]),
        ("Messages", ["messages"]),
        ("Calendar", ["calendar"]),
        ("Reminders", ["reminders"]),
        ("Music", ["music"]),
        ("Photos", ["photos"]),
        ("Preview", ["preview"]),
        ("TextEdit", ["textedit"]),
        ("Calculator", ["calculator"]),
        ("Slack", ["slack"]),
        ("Discord", ["discord"]),
        ("Zoom", ["zoom"]),
        ("Microsoft Teams", ["teams", "microsoft teams"]),
        ("Spotify", ["spotify"]),
        ("Activity Monitor", ["activity monitor"]),
        ("Console", ["console"]),
        ("Keychain Access", ["keychain access", "keychain"]),
        ("Disk Utility", ["disk utility"]),
        ("Arc", ["arc"]),
        ("Cursor", ["cursor"]),
        ("Warp", ["warp"]),
        ("1Password", ["1password"]),
        ("Notion", ["notion"]),
        ("Figma", ["figma"]),
        ("Telegram", ["telegram"]),
        ("WhatsApp", ["whatsapp"]),
    ]

    private static let allAliases: Set<String> = {
        Set(knownApps.flatMap { $0.aliases })
    }()

    private func isLikelyApp(_ name: String) -> Bool {
        let cleanName = name.lowercased()
            .replacingOccurrences(of: ".app", with: "")
            .trimmingCharacters(in: .whitespaces)

        if Self.allAliases.contains(cleanName) { return true }

        // Check /Applications (case-insensitive)
        return resolveAppPath(cleanName) != nil
    }

    private func resolveAppPath(_ name: String) -> String? {
        let dirs = ["/Applications", "/System/Applications", "/Applications/Utilities"]
        for dir in dirs {
            guard let contents = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for item in contents where item.hasSuffix(".app") {
                let appName = String(item.dropLast(4)) // remove .app
                if appName.lowercased() == name.lowercased() {
                    return "\(dir)/\(item)"
                }
            }
        }
        return nil
    }

    /// Fuzzy match: finds apps even with typos (e.g. "chrme" → "Chrome")
    private func fuzzyMatchApp(_ input: String) -> String? {
        let clean = input.replacingOccurrences(of: ".app", with: "").trimmingCharacters(in: .whitespaces)
        guard clean.count >= 3 else { return nil }

        var bestMatch: String?
        var bestDistance = Int.max
        let threshold = max(2, clean.count / 3) // allow ~1 typo per 3 chars

        // Check known apps
        for app in Self.knownApps {
            for alias in app.aliases {
                let d = levenshteinDistance(clean, alias)
                if d < bestDistance && d <= threshold {
                    bestDistance = d
                    bestMatch = app.canonical
                }
            }
        }

        // Also scan /Applications
        let dirs = ["/Applications", "/System/Applications"]
        for dir in dirs {
            guard let contents = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for item in contents where item.hasSuffix(".app") {
                let appName = String(item.dropLast(4))
                let d = levenshteinDistance(clean, appName.lowercased())
                if d < bestDistance && d <= threshold {
                    bestDistance = d
                    bestMatch = appName
                }
            }
        }

        return bestMatch
    }

    /// Simple Levenshtein distance for typo tolerance
    private func levenshteinDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        let m = a.count, n = b.count
        if m == 0 { return n }
        if n == 0 { return m }
        var prev = Array(0...n)
        var curr = [Int](repeating: 0, count: n + 1)
        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                let cost = a[i-1] == b[j-1] ? 0 : 1
                curr[j] = min(prev[j] + 1, curr[j-1] + 1, prev[j-1] + cost)
            }
            prev = curr
        }
        return prev[n]
    }
}
