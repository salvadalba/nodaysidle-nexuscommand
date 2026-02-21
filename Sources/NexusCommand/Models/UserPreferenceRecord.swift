import Foundation
import SwiftData

@Model
final class UserPreferenceRecord {
    @Attribute(.unique) var id: UUID
    var hotkeyKeyCode: Int      // UInt16 stored as Int for SwiftData
    var hotkeyModifiers: Int    // UInt stored as Int for SwiftData
    var indexingPaths: [String]
    var maxIndexedFiles: Int
    var historyRetentionDays: Int
    var appearanceMode: String
    var commandBarWidth: Double
    var showMenuBarIcon: Bool

    init(
        id: UUID = UUID(),
        hotkeyKeyCode: Int = 49,          // Space
        hotkeyModifiers: Int = 524288,    // Option
        indexingPaths: [String] = [
            "~/Documents", "~/Desktop", "~/Downloads", "/Applications"
        ],
        maxIndexedFiles: Int = 500_000,
        historyRetentionDays: Int = 90,
        appearanceMode: String = "system",
        commandBarWidth: Double = 680.0,
        showMenuBarIcon: Bool = true
    ) {
        self.id = id
        self.hotkeyKeyCode = hotkeyKeyCode
        self.hotkeyModifiers = hotkeyModifiers
        self.indexingPaths = indexingPaths
        self.maxIndexedFiles = maxIndexedFiles
        self.historyRetentionDays = historyRetentionDays
        self.appearanceMode = appearanceMode
        self.commandBarWidth = commandBarWidth
        self.showMenuBarIcon = showMenuBarIcon
    }

    var hotkeyCombo: HotkeyCombo {
        HotkeyCombo(keyCode: UInt16(hotkeyKeyCode), modifiers: UInt(hotkeyModifiers))
    }

    var resolvedIndexingPaths: [URL] {
        indexingPaths.compactMap { path in
            let expanded = NSString(string: path).expandingTildeInPath
            return URL(fileURLWithPath: expanded, isDirectory: true)
        }
    }
}

// MARK: - Schema Versioning

enum NexusSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [FileMetadataRecord.self, CommandHistoryRecord.self, UserPreferenceRecord.self]
    }
}

enum NexusMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [NexusSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
