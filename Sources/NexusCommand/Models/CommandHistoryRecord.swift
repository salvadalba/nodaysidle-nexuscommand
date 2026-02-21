import Foundation
import SwiftData

@Model
final class CommandHistoryRecord {
    #Unique<CommandHistoryRecord>([\.id])

    @Attribute(.unique) var id: UUID
    @Attribute(.spotlight) var query: String
    var selectedResultPath: String?
    @Attribute(.spotlight) var timestamp: Date
    var executionCount: Int

    init(
        id: UUID = UUID(),
        query: String,
        selectedResultPath: String? = nil,
        timestamp: Date = .now,
        executionCount: Int = 1
    ) {
        self.id = id
        self.query = query
        self.selectedResultPath = selectedResultPath
        self.timestamp = timestamp
        self.executionCount = executionCount
    }
}
