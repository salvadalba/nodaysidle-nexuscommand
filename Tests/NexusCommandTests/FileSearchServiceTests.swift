import Testing
import Foundation
import SwiftData
@testable import NexusCommand

@Suite("FileSearchService Tests")
struct FileSearchServiceTests {

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: FileMetadataRecord.self, CommandHistoryRecord.self, UserPreferenceRecord.self,
            configurations: config
        )
    }

    @MainActor
    private func seedRecords(container: ModelContainer, count: Int = 10) throws {
        let context = container.mainContext
        for i in 0..<count {
            let record = FileMetadataRecord(
                filePath: "/Users/test/Documents/file\(i).txt",
                fileName: "file\(i).txt",
                fileExtension: "txt",
                fileType: "public.plain-text",
                fileSize: Int64(i * 100),
                createdDate: Date.now.addingTimeInterval(Double(-i * 3600)),
                modifiedDate: Date.now.addingTimeInterval(Double(-i * 3600)),
                contentSnippet: "This is the content of file \(i) with some searchable text",
                contentHash: "hash\(i)"
            )
            context.insert(record)
        }
        try context.save()
    }

    // MARK: - Text Search

    @Test("Text search matches fileName")
    @MainActor
    func testTextSearchByName() async throws {
        let container = try makeContainer()
        try seedRecords(container: container)
        let actor = IndexingActor(modelContainer: container)
        let service = FileSearchService(indexingActor: actor)

        let results = try await service.search(query: "file3")
        #expect(!results.isEmpty)
        #expect(results.first?.fileName == "file3.txt")
    }

    @Test("Text search matches content snippet")
    @MainActor
    func testTextSearchByContent() async throws {
        let container = try makeContainer()
        try seedRecords(container: container)
        let actor = IndexingActor(modelContainer: container)
        let service = FileSearchService(indexingActor: actor)

        let results = try await service.search(query: "searchable")
        #expect(!results.isEmpty)
    }

    // MARK: - Filters

    @Test("Date range filter excludes old files")
    @MainActor
    func testDateFilter() async throws {
        let container = try makeContainer()
        try seedRecords(container: container)
        let actor = IndexingActor(modelContainer: container)
        let service = FileSearchService(indexingActor: actor)

        let filters = SearchFilters(
            modifiedAfter: Date.now.addingTimeInterval(-7200), // Last 2 hours
            maxResults: 20
        )
        let results = try await service.search(query: "file", filters: filters)
        // Only recent files should match
        #expect(results.count <= 3)
    }

    @Test("UTType filter returns matching types")
    @MainActor
    func testFileTypeFilter() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        // Seed mixed types
        let textFile = FileMetadataRecord(
            filePath: "/test/doc.txt", fileName: "doc.txt", fileExtension: "txt",
            fileType: "public.plain-text", fileSize: 100,
            createdDate: .now, modifiedDate: .now, contentHash: "h1"
        )
        let pdfFile = FileMetadataRecord(
            filePath: "/test/doc.pdf", fileName: "doc.pdf", fileExtension: "pdf",
            fileType: "com.adobe.pdf", fileSize: 200,
            createdDate: .now, modifiedDate: .now, contentHash: "h2"
        )
        context.insert(textFile)
        context.insert(pdfFile)
        try context.save()

        let actor = IndexingActor(modelContainer: container)
        let service = FileSearchService(indexingActor: actor)

        let filters = SearchFilters(fileTypes: ["public.plain-text"])
        let results = try await service.search(query: "doc", filters: filters)
        #expect(results.allSatisfy { $0.fileType == "public.plain-text" })
    }

    // MARK: - Sorting

    @Test("Results sorted by relevanceScore descending")
    @MainActor
    func testRelevanceSorting() async throws {
        let container = try makeContainer()
        try seedRecords(container: container)
        let actor = IndexingActor(modelContainer: container)
        let service = FileSearchService(indexingActor: actor)

        let results = try await service.search(query: "file")
        for i in 0..<(results.count - 1) {
            #expect(results[i].relevanceScore >= results[i + 1].relevanceScore)
        }
    }

    @Test("maxResults caps output")
    @MainActor
    func testMaxResults() async throws {
        let container = try makeContainer()
        try seedRecords(container: container, count: 50)
        let actor = IndexingActor(modelContainer: container)
        let service = FileSearchService(indexingActor: actor)

        let filters = SearchFilters(maxResults: 5)
        let results = try await service.search(query: "file", filters: filters)
        #expect(results.count <= 5)
    }

    // MARK: - Recent Files

    @Test("recentFiles returns correct order")
    @MainActor
    func testRecentFiles() async throws {
        let container = try makeContainer()
        try seedRecords(container: container)
        let actor = IndexingActor(modelContainer: container)
        let service = FileSearchService(indexingActor: actor)

        let results = await service.recentFiles(limit: 5)
        #expect(results.count == 5)
        for i in 0..<(results.count - 1) {
            #expect(results[i].lastModified >= results[i + 1].lastModified)
        }
    }

    // MARK: - Cache

    @Test("Empty query returns empty results")
    @MainActor
    func testEmptyQuery() async throws {
        let container = try makeContainer()
        let actor = IndexingActor(modelContainer: container)
        let service = FileSearchService(indexingActor: actor)

        let results = try await service.search(query: "")
        #expect(results.isEmpty)
    }

    @Test("Cache invalidation clears results")
    @MainActor
    func testCacheInvalidation() async throws {
        let container = try makeContainer()
        try seedRecords(container: container)
        let actor = IndexingActor(modelContainer: container)
        let service = FileSearchService(indexingActor: actor)

        _ = try await service.search(query: "file0")
        service.invalidateCache()
        #expect(service.cacheHitRate == 0.0)
    }
}
