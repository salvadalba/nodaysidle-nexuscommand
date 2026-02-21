import Foundation
import SwiftData

@Model
final class FileMetadataRecord {
    #Unique<FileMetadataRecord>([\.id])

    @Attribute(.unique) var id: UUID
    @Attribute(.spotlight) var filePath: String
    @Attribute(.spotlight) var fileName: String
    @Attribute(.spotlight) var fileExtension: String
    var fileType: String
    var fileSize: Int64
    var createdDate: Date
    @Attribute(.spotlight) var modifiedDate: Date
    @Attribute(.spotlight) var contentSnippet: String?
    var contentHash: String

    init(
        id: UUID = UUID(),
        filePath: String,
        fileName: String,
        fileExtension: String,
        fileType: String,
        fileSize: Int64,
        createdDate: Date,
        modifiedDate: Date,
        contentSnippet: String? = nil,
        contentHash: String
    ) {
        self.id = id
        self.filePath = filePath
        self.fileName = fileName
        self.fileExtension = fileExtension
        self.fileType = fileType
        self.fileSize = fileSize
        self.createdDate = createdDate
        self.modifiedDate = modifiedDate
        self.contentSnippet = contentSnippet
        self.contentHash = contentHash
    }
}
