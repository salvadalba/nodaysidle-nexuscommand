import Testing
import Foundation
import SwiftData
@testable import NexusCommand

@Suite("Query Pipeline Integration Tests")
struct QueryPipelineIntegrationTests {

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: FileMetadataRecord.self, CommandHistoryRecord.self, UserPreferenceRecord.self,
            configurations: config
        )
    }

    @MainActor
    private func seedRecords(container: ModelContainer, count: Int) throws {
        let context = container.mainContext
        let fileNames = [
            "readme.md", "document.pdf", "notes.txt", "report.docx",
            "image.png", "photo.jpg", "script.py", "main.swift",
            "config.json", "data.csv", "presentation.key", "budget.xlsx"
        ]

        for i in 0..<count {
            let name = fileNames[i % fileNames.count]
            let baseName = (URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent)
            let ext = URL(fileURLWithPath: name).pathExtension
            let record = FileMetadataRecord(
                filePath: "/Users/test/Documents/\(i)/\(name)",
                fileName: "\(baseName)_\(i).\(ext)",
                fileExtension: ext,
                fileType: "public.\(ext)",
                fileSize: Int64.random(in: 100...10000),
                createdDate: Date.now.addingTimeInterval(Double(-i * 3600)),
                modifiedDate: Date.now.addingTimeInterval(Double(-i * 1800)),
                contentSnippet: i % 3 == 0 ? "This is the content of \(name) number \(i)" : nil,
                contentHash: "hash_\(i)"
            )
            context.insert(record)
        }
        try context.save()
    }

    @Test("Full pipeline: parse + search returns matching results")
    @MainActor
    func testFullPipeline() async throws {
        let container = try makeContainer()
        try seedRecords(container: container, count: 100)

        let indexingActor = IndexingActor(modelContainer: container)
        let intentService = IntentParsingService()
        await intentService.warmup()

        let searchService = FileSearchService(indexingActor: indexingActor)

        // Parse intent
        let chain = try await intentService.parse(query: "find document")
        #expect(chain.primaryIntent?.action == .openFile)

        // Search for files
        let results = try await searchService.search(query: "document")
        #expect(!results.isEmpty)
        #expect(results.contains(where: { $0.fileName.contains("document") }))
    }

    @Test("Pipeline with 100 seeded records returns results under maxResults")
    @MainActor
    func testPipelineWithManyRecords() async throws {
        let container = try makeContainer()
        try seedRecords(container: container, count: 100)

        let indexingActor = IndexingActor(modelContainer: container)
        let searchService = FileSearchService(indexingActor: indexingActor)

        let filters = SearchFilters(maxResults: 10)
        let results = try await searchService.search(query: "main", filters: filters)
        #expect(results.count <= 10)
    }

    @Test("Pipeline search results are sorted by relevance")
    @MainActor
    func testPipelineResultsSorted() async throws {
        let container = try makeContainer()
        try seedRecords(container: container, count: 100)

        let indexingActor = IndexingActor(modelContainer: container)
        let searchService = FileSearchService(indexingActor: indexingActor)

        let results = try await searchService.search(query: "readme")
        for i in 0..<max(0, results.count - 1) {
            #expect(results[i].relevanceScore >= results[i + 1].relevanceScore)
        }
    }

    @Test("History integration: recorded commands appear in frequent list")
    @MainActor
    func testHistoryIntegration() async throws {
        let container = try makeContainer()
        let historyActor = HistoryActor(modelContainer: container)
        let historyService = CommandHistoryService(historyActor: historyActor)

        // Simulate 5 queries
        await historyService.record(query: "open Safari", selectedResult: nil)
        await historyService.record(query: "find readme", selectedResult: "/readme.md")
        await historyService.record(query: "run ls", selectedResult: nil)
        await historyService.record(query: "open Safari", selectedResult: nil)
        await historyService.record(query: "2+2", selectedResult: nil)

        let frequent = await historyService.frequentCommands(limit: 5)
        #expect(!frequent.isEmpty)
        #expect(frequent.first?.query == "open Safari")
        #expect(frequent.first?.executionCount == 2)
    }
}
