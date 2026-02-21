import Foundation
import os

@MainActor @Observable
final class CommandBarViewModel {
    private static let logger = Logger(subsystem: "com.nexuscommand", category: "search")
    private static let signposter = OSSignposter(subsystem: "com.nexuscommand", category: "search")

    var query: String = "" {
        didSet { onQueryChanged() }
    }
    var results: [SearchResultItem] = []
    var selectedIndex: Int = 0
    var isLoading: Bool = false
    var errorMessage: String?
    var shouldDismissAfterExecution: Bool = false

    private var searchTask: Task<Void, Never>?
    private var intentService: IntentParsingService?
    private var searchService: FileSearchService?
    private var actionService: SystemActionService?
    private var historyService: CommandHistoryService?

    func configure(
        intentService: IntentParsingService,
        searchService: FileSearchService,
        actionService: SystemActionService,
        historyService: CommandHistoryService
    ) {
        self.intentService = intentService
        self.searchService = searchService
        self.actionService = actionService
        self.historyService = historyService
    }

    func onAppear() {
        // Show frequent commands as initial suggestions
        Task {
            guard let historyService else { return }
            let frequent = await historyService.frequentCommands(limit: 5)
            if query.isEmpty {
                results = frequent.map { record in
                    SearchResultItem(
                        id: record.id,
                        title: record.query,
                        subtitle: "Used \(record.executionCount) times",
                        icon: "clock.arrow.circlepath",
                        action: .openFile,
                        parameters: ["query": record.query],
                        relevanceScore: Float(record.executionCount),
                        source: .history
                    )
                }
            }
        }
    }

    func clearState() {
        searchTask?.cancel()
        query = ""
        results = []
        selectedIndex = 0
        isLoading = false
        errorMessage = nil
        shouldDismissAfterExecution = false
    }

    func moveSelectionDown() {
        guard !results.isEmpty else { return }
        selectedIndex = min(selectedIndex + 1, results.count - 1)
    }

    func moveSelectionUp() {
        guard !results.isEmpty else { return }
        selectedIndex = max(selectedIndex - 1, 0)
    }

    func executeSelected() {
        guard let item = results[safe: selectedIndex] else { return }
        shouldDismissAfterExecution = false

        Task {
            let intent = ParsedIntent(
                action: item.action,
                parameters: item.parameters,
                confidence: item.relevanceScore
            )

            do {
                let result = try await actionService?.execute(intent: intent)
                if let result, result.success {
                    shouldDismissAfterExecution = true
                    // Record to history
                    await historyService?.record(
                        query: query.isEmpty ? item.title : query,
                        selectedResult: item.parameters["path"] ?? item.parameters["app"]
                    )
                    Self.logger.info("Action executed successfully: \(item.action.rawValue)")
                } else if let output = result?.output {
                    errorMessage = output
                }
            } catch {
                errorMessage = error.localizedDescription
                Self.logger.error("Action failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Query Pipeline (50ms debounce)

    private func onQueryChanged() {
        searchTask?.cancel()
        errorMessage = nil

        let currentQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentQuery.isEmpty else {
            results = []
            selectedIndex = 0
            isLoading = false
            onAppear()  // Show frequent commands again
            return
        }

        isLoading = true

        searchTask = Task {
            // 50ms debounce
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }

            let signpostID = Self.signposter.makeSignpostID()
            let state = Self.signposter.beginInterval("QueryPipeline", id: signpostID)
            defer { Self.signposter.endInterval("QueryPipeline", state) }

            await runParallelSearch(query: currentQuery)
        }
    }

    private func runParallelSearch(query: String) async {
        guard !Task.isCancelled else { return }

        // Run searches sequentially to avoid Swift 6 sending-parameter races
        // (all services are @MainActor so they're serialized anyway)
        var intentResults: [SearchResultItem] = []
        var fileResults: [SearchResultItem] = []
        var historyResults: [SearchResultItem] = []

        // Intent parsing
        if let chain = try? await intentService?.parse(query: query), !Task.isCancelled {
            intentResults = chain.intents.map { intent in
                SearchResultItem(
                    id: UUID(),
                    title: titleForIntent(intent),
                    subtitle: subtitleForIntent(intent),
                    icon: iconForAction(intent.action),
                    action: intent.action,
                    parameters: intent.parameters,
                    relevanceScore: intent.confidence,
                    source: .intentParsing
                )
            }
        }

        // File search
        if let searchResults = try? await searchService?.search(query: query), !Task.isCancelled {
            fileResults = searchResults.map { result in
                SearchResultItem(
                    id: UUID(),
                    title: result.fileName,
                    subtitle: result.path,
                    icon: "doc",
                    action: .openFile,
                    parameters: ["path": result.path],
                    relevanceScore: result.relevanceScore,
                    source: .fileSearch
                )
            }
        }

        // History search
        if let records = await historyService?.searchHistory(query: query, limit: 3), !Task.isCancelled {
            historyResults = records.map { record in
                SearchResultItem(
                    id: UUID(),
                    title: record.query,
                    subtitle: "Recent • Used \(record.executionCount) times",
                    icon: "clock.arrow.circlepath",
                    action: .openFile,
                    parameters: ["query": record.query],
                    relevanceScore: Float(record.executionCount) * 0.5,
                    source: .history
                )
            }
        }

        guard !Task.isCancelled else { return }

        // Merge results: intents first, then history matches, then file results
        var merged: [SearchResultItem] = []
        merged.append(contentsOf: intentResults)
        merged.append(contentsOf: historyResults)
        merged.append(contentsOf: fileResults)

        // Deduplicate by title
        var seen = Set<String>()
        merged = merged.filter { item in
            let key = item.title.lowercased()
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }

        results = Array(merged.prefix(20))
        selectedIndex = 0
        isLoading = false
    }

    // MARK: - Display Helpers

    private func titleForIntent(_ intent: ParsedIntent) -> String {
        switch intent.action {
        case .launchApp:
            "Launch \(intent.parameters["app"] ?? "application")"
        case .openFile:
            "Open \(intent.parameters["path"] ?? intent.parameters["query"] ?? "file")"
        case .runShellCommand:
            "Run: \(intent.parameters["command"] ?? "command")"
        case .systemPreference:
            "Open Settings: \(intent.parameters["pane"] ?? "")"
        case .webSearch:
            "Search: \(intent.parameters["query"] ?? "")"
        case .calculate:
            intent.parameters["expression"] ?? "Calculate"
        }
    }

    private func subtitleForIntent(_ intent: ParsedIntent) -> String {
        switch intent.action {
        case .launchApp: "Application"
        case .openFile: "File"
        case .runShellCommand: "Shell Command"
        case .systemPreference: "System Settings"
        case .webSearch: "Web Search"
        case .calculate: "Calculator"
        }
    }

    func iconForAction(_ action: IntentAction) -> String {
        switch action {
        case .launchApp: "app.badge.checkmark"
        case .openFile: "doc"
        case .runShellCommand: "terminal"
        case .systemPreference: "gearshape"
        case .webSearch: "globe"
        case .calculate: "function"
        }
    }
}
