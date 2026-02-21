import Foundation
import os

@MainActor @Observable
final class FileSearchService {
    private static let logger = Logger(subsystem: "com.nexuscommand", category: "search")
    private static let signposter = OSSignposter(subsystem: "com.nexuscommand", category: "search")

    private let indexingActor: IndexingActor
    private let cache = LRUCache<String, [FileSearchResult]>(capacity: 100)

    var cacheHitRate: Double { cache.hitRate }

    init(indexingActor: IndexingActor) {
        self.indexingActor = indexingActor
    }

    func search(query: String, filters: SearchFilters? = nil) async throws -> [FileSearchResult] {
        let signpostID = Self.signposter.makeSignpostID()
        let state = Self.signposter.beginInterval("DataQuery", id: signpostID)
        defer { Self.signposter.endInterval("DataQuery", state) }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let cacheKey = "\(trimmed)|\(filters?.hashValue ?? 0)"
        if let cached = cache.get(cacheKey) {
            Self.logger.debug("Cache hit for query: \(trimmed, privacy: .private)")
            return cached
        }

        Self.logger.debug("Searching for: \(trimmed, privacy: .private)")

        let maxResults = filters?.maxResults ?? 20

        let records = try await indexingActor.search(
            query: trimmed,
            fileTypes: filters?.fileTypes,
            modifiedAfter: filters?.modifiedAfter,
            modifiedBefore: filters?.modifiedBefore,
            maxResults: maxResults * 2  // Fetch extra for scoring
        )

        // Score and sort results
        var results = records.map { record in
            scoreResult(record: record, query: trimmed)
        }

        // Apply additional filters in-memory if needed
        if let fileTypes = filters?.fileTypes, !fileTypes.isEmpty {
            results = results.filter { fileTypes.contains($0.fileType) }
        }
        if let after = filters?.modifiedAfter {
            results = results.filter { $0.lastModified >= after }
        }
        if let before = filters?.modifiedBefore {
            results = results.filter { $0.lastModified <= before }
        }

        results.sort { $0.relevanceScore > $1.relevanceScore }
        let capped = Array(results.prefix(maxResults))

        cache.set(cacheKey, value: capped)
        return capped
    }

    func recentFiles(limit: Int = 10) async -> [FileSearchResult] {
        do {
            let records = try await indexingActor.recentFiles(limit: limit)
            return records.map { record in
                FileSearchResult(
                    path: record.filePath,
                    fileName: record.fileName,
                    fileType: record.fileType,
                    lastModified: record.modifiedDate,
                    contentSnippet: record.contentSnippet,
                    relevanceScore: 1.0
                )
            }
        } catch {
            Self.logger.error("Failed to fetch recent files: \(error.localizedDescription)")
            return []
        }
    }

    func invalidateCache() {
        cache.invalidate()
        Self.logger.debug("Search cache invalidated")
    }

    // MARK: - Relevance Scoring

    private func scoreResult(record: FileMetadataDTO, query: String) -> FileSearchResult {
        let textScore = computeTextScore(fileName: record.fileName, snippet: record.contentSnippet, query: query)
        let recencyScore = computeRecencyScore(modifiedDate: record.modifiedDate)
        let relevanceScore = textScore * 0.7 + recencyScore * 0.3

        return FileSearchResult(
            path: record.filePath,
            fileName: record.fileName,
            fileType: record.fileType,
            lastModified: record.modifiedDate,
            contentSnippet: record.contentSnippet,
            relevanceScore: Float(relevanceScore)
        )
    }

    private func computeTextScore(fileName: String, snippet: String?, query: String) -> Double {
        let lowerName = fileName.lowercased()
        let lowerQuery = query.lowercased()

        // Exact match
        if lowerName == lowerQuery { return 1.0 }
        // Prefix match
        if lowerName.hasPrefix(lowerQuery) { return 0.9 }
        // Contains match
        if lowerName.contains(lowerQuery) { return 0.7 }
        // Snippet match
        if let snippet = snippet?.lowercased(), snippet.contains(lowerQuery) { return 0.4 }
        // Fuzzy token overlap
        let queryTokens = Set(lowerQuery.split(separator: " ").map(String.init))
        var nameTokenArray: [String] = []
        nameTokenArray.append(contentsOf: lowerName.split(separator: " ").map(String.init))
        nameTokenArray.append(contentsOf: lowerName.split(separator: ".").map(String.init))
        nameTokenArray.append(contentsOf: lowerName.split(separator: "-").map(String.init))
        nameTokenArray.append(contentsOf: lowerName.split(separator: "_").map(String.init))
        let nameTokens = Set(nameTokenArray)
        let overlap = queryTokens.intersection(nameTokens).count
        if overlap > 0 { return Double(overlap) / Double(queryTokens.count) * 0.5 }

        return 0.1
    }

    private func computeRecencyScore(modifiedDate: Date) -> Double {
        let hoursSinceModified = Date.now.timeIntervalSince(modifiedDate) / 3600
        switch hoursSinceModified {
        case ..<1: return 1.0
        case ..<24: return 0.9
        case ..<168: return 0.7  // 1 week
        case ..<720: return 0.5  // 30 days
        case ..<8760: return 0.3 // 1 year
        default: return 0.1
        }
    }
}
