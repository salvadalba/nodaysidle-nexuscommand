import Foundation
import os

@MainActor @Observable
final class CommandHistoryService {
    private static let logger = Logger(subsystem: "com.nexuscommand", category: "history")

    private let historyActor: HistoryActor

    init(historyActor: HistoryActor) {
        self.historyActor = historyActor
    }

    func record(query: String, selectedResult: String?, timestamp: Date = .now) async {
        do {
            try await historyActor.record(query: query, selectedResultPath: selectedResult, timestamp: timestamp)
            Self.logger.debug("Recorded command: \(query, privacy: .private)")
        } catch {
            Self.logger.error("Failed to record command: \(error.localizedDescription)")
        }
    }

    func frequentCommands(limit: Int = 5) async -> [CommandHistoryDTO] {
        do {
            return try await historyActor.frequentCommands(limit: limit)
        } catch {
            Self.logger.error("Failed to fetch frequent commands: \(error.localizedDescription)")
            return []
        }
    }

    func searchHistory(query: String, limit: Int = 10) async -> [CommandHistoryDTO] {
        do {
            return try await historyActor.searchHistory(containing: query, limit: limit)
        } catch {
            Self.logger.error("Failed to search history: \(error.localizedDescription)")
            return []
        }
    }

    func clearHistory() async {
        do {
            try await historyActor.clearHistory()
            Self.logger.info("Command history cleared")
        } catch {
            Self.logger.error("Failed to clear history: \(error.localizedDescription)")
        }
    }

    func pruneExpired(retentionDays: Int = 90) async {
        do {
            try await historyActor.pruneExpired(retentionDays: retentionDays)
        } catch {
            Self.logger.error("Failed to prune history: \(error.localizedDescription)")
        }
    }
}
