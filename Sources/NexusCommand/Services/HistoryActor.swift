import Foundation
import SwiftData
import os

@ModelActor
actor HistoryActor {
    private static let logger = Logger(subsystem: "com.nexuscommand", category: "history")

    func record(query: String, selectedResultPath: String?, timestamp: Date) throws {
        let descriptor = FetchDescriptor<CommandHistoryRecord>(
            predicate: #Predicate { $0.query == query }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            existing.executionCount += 1
            existing.timestamp = timestamp
            existing.selectedResultPath = selectedResultPath
        } else {
            let record = CommandHistoryRecord(
                query: query,
                selectedResultPath: selectedResultPath,
                timestamp: timestamp
            )
            modelContext.insert(record)
        }
        try modelContext.save()
    }

    func frequentCommands(limit: Int) throws -> [CommandHistoryDTO] {
        var descriptor = FetchDescriptor<CommandHistoryRecord>(
            sortBy: [SortDescriptor(\.executionCount, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor).map(\.toDTO)
    }

    func searchHistory(containing query: String, limit: Int) throws -> [CommandHistoryDTO] {
        let lowered = query.lowercased()
        var descriptor = FetchDescriptor<CommandHistoryRecord>(
            predicate: #Predicate { $0.query.localizedStandardContains(lowered) },
            sortBy: [SortDescriptor(\.executionCount, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor).map(\.toDTO)
    }

    func clearHistory() throws {
        try modelContext.delete(model: CommandHistoryRecord.self)
        try modelContext.save()
    }

    func pruneExpired(retentionDays: Int) throws {
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: .now) ?? .distantPast
        let descriptor = FetchDescriptor<CommandHistoryRecord>(
            predicate: #Predicate { $0.timestamp < cutoff }
        )
        let expired = try modelContext.fetch(descriptor)
        for record in expired {
            modelContext.delete(record)
        }
        if !expired.isEmpty {
            try modelContext.save()
            Self.logger.info("Pruned \(expired.count) expired history records")
        }
    }
}

// MARK: - Model to DTO conversion

extension CommandHistoryRecord {
    var toDTO: CommandHistoryDTO {
        CommandHistoryDTO(
            id: id,
            query: query,
            selectedResultPath: selectedResultPath,
            timestamp: timestamp,
            executionCount: executionCount
        )
    }
}
