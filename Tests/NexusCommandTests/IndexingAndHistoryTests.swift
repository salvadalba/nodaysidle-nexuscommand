import Testing
import Foundation
import SwiftData
@testable import NexusCommand

@Suite("IndexingService Tests")
struct IndexingServiceTests {

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: FileMetadataRecord.self, CommandHistoryRecord.self, UserPreferenceRecord.self,
            configurations: config
        )
    }

    @Test("Crawl creates FileMetadataRecords for all files")
    @MainActor
    func testCrawlCreatesRecords() async throws {
        let container = try makeContainer()
        let indexingActor = IndexingActor(modelContainer: container)
        let service = IndexingService(indexingActor: indexingActor)

        // Create temp directory with files
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        for i in 0..<10 {
            let file = tempDir.appendingPathComponent("test\(i).txt")
            try "Content of file \(i)".write(to: file, atomically: true, encoding: .utf8)
        }

        await service.startIndexing(paths: [tempDir])

        let count = try await indexingActor.totalCount()
        #expect(count == 10)
    }

    @Test("handleFileEvent(.created) adds record")
    @MainActor
    func testFileCreatedEvent() async throws {
        let container = try makeContainer()
        let indexingActor = IndexingActor(modelContainer: container)
        let service = IndexingService(indexingActor: indexingActor)

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let file = tempDir.appendingPathComponent("newfile.txt")
        try "New content".write(to: file, atomically: true, encoding: .utf8)

        let event = FileSystemEvent(path: file, eventType: .created)
        await service.handleFileEvent(event)

        let count = try await indexingActor.totalCount()
        #expect(count == 1)
    }

    @Test("handleFileEvent(.deleted) removes record")
    @MainActor
    func testFileDeletedEvent() async throws {
        let container = try makeContainer()
        let indexingActor = IndexingActor(modelContainer: container)
        let service = IndexingService(indexingActor: indexingActor)

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let file = tempDir.appendingPathComponent("delete_me.txt")
        try "Content".write(to: file, atomically: true, encoding: .utf8)

        // Create
        let createEvent = FileSystemEvent(path: file, eventType: .created)
        await service.handleFileEvent(createEvent)
        #expect(try await indexingActor.totalCount() == 1)

        // Delete
        let deleteEvent = FileSystemEvent(path: file, eventType: .deleted)
        await service.handleFileEvent(deleteEvent)
        #expect(try await indexingActor.totalCount() == 0)
    }

    @Test("handleFileEvent(.modified) updates contentHash")
    @MainActor
    func testFileModifiedEvent() async throws {
        let container = try makeContainer()
        let indexingActor = IndexingActor(modelContainer: container)
        let service = IndexingService(indexingActor: indexingActor)

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let file = tempDir.appendingPathComponent("modify_me.txt")
        try "Original content".write(to: file, atomically: true, encoding: .utf8)

        let createEvent = FileSystemEvent(path: file, eventType: .created)
        await service.handleFileEvent(createEvent)

        let originalDTO = try await indexingActor.fetchRecord(filePath: file.path(percentEncoded: false))
        let originalHash = originalDTO?.contentHash

        // Modify file
        try "Modified content".write(to: file, atomically: true, encoding: .utf8)
        let modifyEvent = FileSystemEvent(path: file, eventType: .modified)
        await service.handleFileEvent(modifyEvent)

        let updatedDTO = try await indexingActor.fetchRecord(filePath: file.path(percentEncoded: false))
        #expect(updatedDTO?.contentHash != originalHash)
    }
}

// MARK: - CommandHistoryService Tests

@Suite("CommandHistoryService Tests")
struct CommandHistoryServiceTests {

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: FileMetadataRecord.self, CommandHistoryRecord.self, UserPreferenceRecord.self,
            configurations: config
        )
    }

    @Test("record() creates new CommandHistoryRecord")
    @MainActor
    func testRecordCreatesEntry() async throws {
        let container = try makeContainer()
        let historyActor = HistoryActor(modelContainer: container)
        let service = CommandHistoryService(historyActor: historyActor)

        await service.record(query: "test query", selectedResult: "/path/to/file")

        let records = await service.frequentCommands(limit: 10)
        #expect(records.count == 1)
        #expect(records.first?.query == "test query")
    }

    @Test("record() increments executionCount for duplicate query")
    @MainActor
    func testRecordIncrements() async throws {
        let container = try makeContainer()
        let historyActor = HistoryActor(modelContainer: container)
        let service = CommandHistoryService(historyActor: historyActor)

        await service.record(query: "open Safari", selectedResult: nil)
        await service.record(query: "open Safari", selectedResult: nil)
        await service.record(query: "open Safari", selectedResult: nil)

        let records = await service.frequentCommands(limit: 10)
        #expect(records.count == 1)
        #expect(records.first?.executionCount == 3)
    }

    @Test("frequentCommands returns top-N by count")
    @MainActor
    func testFrequentCommands() async throws {
        let container = try makeContainer()
        let historyActor = HistoryActor(modelContainer: container)
        let service = CommandHistoryService(historyActor: historyActor)

        // Create varying frequencies
        for _ in 0..<5 { await service.record(query: "most frequent", selectedResult: nil) }
        for _ in 0..<3 { await service.record(query: "medium", selectedResult: nil) }
        await service.record(query: "rare", selectedResult: nil)

        let top2 = await service.frequentCommands(limit: 2)
        #expect(top2.count == 2)
        #expect(top2[0].query == "most frequent")
        #expect(top2[1].query == "medium")
    }

    @Test("pruneExpired removes old records")
    @MainActor
    func testPruneExpired() async throws {
        let container = try makeContainer()
        let historyActor = HistoryActor(modelContainer: container)
        let service = CommandHistoryService(historyActor: historyActor)

        // Insert old record directly
        let oldDate = Calendar.current.date(byAdding: .day, value: -100, to: .now)!
        try await historyActor.record(query: "old query", selectedResultPath: nil, timestamp: oldDate)
        await service.record(query: "recent query", selectedResult: nil)

        await service.pruneExpired(retentionDays: 90)

        let records = await service.frequentCommands(limit: 10)
        #expect(records.count == 1)
        #expect(records.first?.query == "recent query")
    }

    @Test("clearHistory removes all records")
    @MainActor
    func testClearHistory() async throws {
        let container = try makeContainer()
        let historyActor = HistoryActor(modelContainer: container)
        let service = CommandHistoryService(historyActor: historyActor)

        await service.record(query: "query1", selectedResult: nil)
        await service.record(query: "query2", selectedResult: nil)
        await service.clearHistory()

        let records = await service.frequentCommands(limit: 10)
        #expect(records.isEmpty)
    }
}
