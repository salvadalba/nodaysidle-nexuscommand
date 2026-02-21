import Foundation
import SwiftData
import os

@ModelActor
actor IndexingActor {
    private static let logger = Logger(subsystem: "com.nexuscommand", category: "indexing")

    func insertRecord(_ dto: FileMetadataDTO) throws {
        let record = FileMetadataRecord(
            filePath: dto.filePath,
            fileName: dto.fileName,
            fileExtension: dto.fileExtension,
            fileType: dto.fileType,
            fileSize: dto.fileSize,
            createdDate: dto.modifiedDate,
            modifiedDate: dto.modifiedDate,
            contentSnippet: dto.contentSnippet,
            contentHash: dto.contentHash
        )
        modelContext.insert(record)
        try modelContext.save()
    }

    func upsertRecord(filePath: String, dto: FileMetadataDTO) throws {
        let descriptor = FetchDescriptor<FileMetadataRecord>(
            predicate: #Predicate { $0.filePath == filePath }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            existing.fileName = dto.fileName
            existing.fileExtension = dto.fileExtension
            existing.fileType = dto.fileType
            existing.fileSize = dto.fileSize
            existing.modifiedDate = dto.modifiedDate
            existing.contentSnippet = dto.contentSnippet
            existing.contentHash = dto.contentHash
        } else {
            let record = FileMetadataRecord(
                filePath: dto.filePath,
                fileName: dto.fileName,
                fileExtension: dto.fileExtension,
                fileType: dto.fileType,
                fileSize: dto.fileSize,
                createdDate: dto.modifiedDate,
                modifiedDate: dto.modifiedDate,
                contentSnippet: dto.contentSnippet,
                contentHash: dto.contentHash
            )
            modelContext.insert(record)
        }
        try modelContext.save()
    }

    func deleteRecord(filePath: String) throws {
        let descriptor = FetchDescriptor<FileMetadataRecord>(
            predicate: #Predicate { $0.filePath == filePath }
        )
        if let record = try modelContext.fetch(descriptor).first {
            modelContext.delete(record)
            try modelContext.save()
        }
    }

    func totalCount() throws -> Int {
        let descriptor = FetchDescriptor<FileMetadataRecord>()
        return try modelContext.fetchCount(descriptor)
    }

    func deleteAll() throws {
        try modelContext.delete(model: FileMetadataRecord.self)
        try modelContext.save()
    }

    func fetchRecord(filePath: String) throws -> FileMetadataDTO? {
        let descriptor = FetchDescriptor<FileMetadataRecord>(
            predicate: #Predicate { $0.filePath == filePath }
        )
        return try modelContext.fetch(descriptor).first?.toDTO
    }

    func search(
        query: String,
        fileTypes: [String]?,
        modifiedAfter: Date?,
        modifiedBefore: Date?,
        maxResults: Int
    ) throws -> [FileMetadataDTO] {
        var descriptor = FetchDescriptor<FileMetadataRecord>()
        descriptor.fetchLimit = maxResults

        let lowercaseQuery = query.lowercased()
        descriptor.predicate = #Predicate<FileMetadataRecord> { record in
            record.fileName.localizedStandardContains(lowercaseQuery) ||
            (record.contentSnippet?.localizedStandardContains(lowercaseQuery) ?? false)
        }

        descriptor.sortBy = [SortDescriptor(\.modifiedDate, order: .reverse)]
        return try modelContext.fetch(descriptor).map(\.toDTO)
    }

    func recentFiles(limit: Int) throws -> [FileMetadataDTO] {
        var descriptor = FetchDescriptor<FileMetadataRecord>(
            sortBy: [SortDescriptor(\.modifiedDate, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor).map(\.toDTO)
    }

    func isStoreHealthy() -> Bool {
        do {
            _ = try totalCount()
            return true
        } catch {
            Self.logger.fault("SwiftData store appears corrupted: \(error.localizedDescription)")
            return false
        }
    }
}

// MARK: - Model to DTO conversion

extension FileMetadataRecord {
    var toDTO: FileMetadataDTO {
        FileMetadataDTO(
            filePath: filePath,
            fileName: fileName,
            fileExtension: fileExtension,
            fileType: fileType,
            fileSize: fileSize,
            modifiedDate: modifiedDate,
            contentSnippet: contentSnippet,
            contentHash: contentHash
        )
    }
}
