import Foundation
import UniformTypeIdentifiers
import CryptoKit
import os

@MainActor @Observable
final class IndexingService {
    private static let logger = Logger(subsystem: "com.nexuscommand", category: "indexing")
    private static let signposter = OSSignposter(subsystem: "com.nexuscommand", category: "indexing")

    private(set) var indexStatus: IndexStatus = .idle
    private(set) var totalRecordCount: Int = 0
    private(set) var currentProgress: IndexProgress?

    private let indexingActor: IndexingActor
    private var indexingTask: Task<Void, Never>?
    private var fsEventStream: FSEventStreamRef?
    private var monitoredPaths: [URL] = []

    // Callback for cache invalidation
    var onFileEvent: (() -> Void)?

    init(indexingActor: IndexingActor) {
        self.indexingActor = indexingActor
    }

    func startIndexing(paths: [URL]) async {
        guard indexStatus != .indexing else { return }
        indexStatus = .indexing
        Self.logger.info("Starting indexing for \(paths.count) paths")

        let signpostID = Self.signposter.makeSignpostID()
        let state = Self.signposter.beginInterval("FSIndex", id: signpostID)

        indexingTask = Task { [weak self] in
            guard let self else { return }
            let maxConcurrency = max(ProcessInfo.processInfo.activeProcessorCount - 2, 1)

            for path in paths {
                guard !Task.isCancelled else { break }
                await self.crawlDirectory(path, maxConcurrency: maxConcurrency)
            }

            await MainActor.run {
                Self.signposter.endInterval("FSIndex", state)
                self.indexStatus = .idle
                Self.logger.info("Indexing complete")
            }

            if let count = try? await self.indexingActor.totalCount() {
                await MainActor.run {
                    self.totalRecordCount = count
                }
            }
        }

        await indexingTask?.value
    }

    func stopIndexing() {
        indexingTask?.cancel()
        indexingTask = nil
        indexStatus = .idle
        Self.logger.info("Indexing stopped")
    }

    func handleFileEvent(_ event: FileSystemEvent) async {
        let signpostID = Self.signposter.makeSignpostID()
        let state = Self.signposter.beginInterval("FSIndex.event", id: signpostID)
        defer { Self.signposter.endInterval("FSIndex.event", state) }

        let path = event.path.path(percentEncoded: false)

        do {
            switch event.eventType {
            case .created, .modified, .renamed:
                let dto = try extractMetadata(from: event.path)
                try await indexingActor.upsertRecord(filePath: path, dto: dto)
            case .deleted:
                try await indexingActor.deleteRecord(filePath: path)
            }
            onFileEvent?()
            totalRecordCount = (try? await indexingActor.totalCount()) ?? totalRecordCount
        } catch {
            Self.logger.error("Failed to handle file event at \(path): \(error.localizedDescription)")
        }
    }

    func startMonitoring(paths: [URL]) {
        stopMonitoring()
        monitoredPaths = paths
        let pathStrings = paths.map { $0.path(percentEncoded: false) } as [NSString] as CFArray

        var context = FSEventStreamContext()
        let unmanaged = Unmanaged.passUnretained(self)
        context.info = unmanaged.toOpaque()

        guard let stream = FSEventStreamCreate(
            nil,
            fsEventCallback,
            &context,
            pathStrings,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,  // 500ms latency
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        ) else {
            Self.logger.error("Failed to create FSEvent stream")
            return
        }

        fsEventStream = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
        Self.logger.info("FSEvent monitoring started for \(paths.count) paths")
    }

    func stopMonitoring() {
        if let stream = fsEventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            fsEventStream = nil
        }
    }

    func checkStoreHealth() async -> Bool {
        await indexingActor.isStoreHealthy()
    }

    // MARK: - Private

    private func crawlDirectory(_ root: URL, maxConcurrency: Int) async {
        // Collect file URLs synchronously to avoid async iterator issue
        let files = collectFiles(root: root)

        let totalFiles = files.count
        var processed = 0

        let actor = self.indexingActor
        await withTaskGroup(of: Void.self) { group in
            var running = 0
            for fileURL in files {
                if Task.isCancelled { break }

                if running >= maxConcurrency {
                    await group.next()
                    running -= 1
                }

                group.addTask {
                    do {
                        let record = try self.extractMetadata(from: fileURL)
                        try await actor.insertRecord(record)
                    } catch {
                        // Log skipped files (nonisolated-safe logging)
                    }
                }
                running += 1

                processed += 1
                if processed % 100 == 0 {
                    let current = fileURL.lastPathComponent
                    let prog = processed
                    self.currentProgress = IndexProgress(
                        totalFiles: totalFiles,
                        processedFiles: prog,
                        currentPath: current
                    )
                }
            }
        }
    }

    private nonisolated func collectFiles(root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.nameKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey, .typeIdentifierKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var files: [URL] = []
        while let item = enumerator.nextObject() as? URL {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: item.path(percentEncoded: false), isDirectory: &isDir), !isDir.boolValue {
                files.append(item)
            }
        }
        return files
    }

    /// Skip content reads for files larger than 50 MB to avoid memory pressure.
    private nonisolated static let maxContentReadSize: Int64 = 50 * 1024 * 1024

    private nonisolated func extractMetadata(from url: URL) throws -> FileMetadataDTO {
        let resourceValues = try url.resourceValues(forKeys: [
            .nameKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey, .typeIdentifierKey
        ])

        let fileName = resourceValues.name ?? url.lastPathComponent
        let fileExtension = url.pathExtension
        let fileType = resourceValues.typeIdentifier ?? UTType.data.identifier
        let fileSize = Int64(resourceValues.fileSize ?? 0)
        let modifiedDate = resourceValues.contentModificationDate ?? .now

        // Content snippet for text files (skip large files)
        var contentSnippet: String?
        if fileSize <= Self.maxContentReadSize,
           let utType = UTType(fileType), utType.conforms(to: .plainText) {
            if let data = try? Data(contentsOf: url, options: .mappedIfSafe),
               let text = String(data: data, encoding: .utf8) {
                contentSnippet = String(text.prefix(500))
            }
        }

        // SHA256 content hash (skip large files)
        let contentHash: String
        if fileSize <= Self.maxContentReadSize,
           let data = try? Data(contentsOf: url, options: .mappedIfSafe) {
            contentHash = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
        } else {
            contentHash = ""
        }

        return FileMetadataDTO(
            filePath: url.path(percentEncoded: false),
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

// MARK: - FSEvents Callback

private func fsEventCallback(
    _ streamRef: ConstFSEventStreamRef,
    _ clientCallBackInfo: UnsafeMutableRawPointer?,
    _ numEvents: Int,
    _ eventPaths: UnsafeMutableRawPointer,
    _ eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    _ eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let info = clientCallBackInfo else { return }
    let service = Unmanaged<IndexingService>.fromOpaque(info).takeUnretainedValue()

    let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
    for i in 0..<numEvents {
        guard let pathString = CFArrayGetValueAtIndex(paths, i) else { continue }
        let path = Unmanaged<CFString>.fromOpaque(pathString).takeUnretainedValue() as String
        let url = URL(fileURLWithPath: path)
        let flags = eventFlags[i]

        let eventType: FileEventType
        if flags & UInt32(kFSEventStreamEventFlagItemRemoved) != 0 {
            eventType = .deleted
        } else if flags & UInt32(kFSEventStreamEventFlagItemRenamed) != 0 {
            eventType = .renamed
        } else if flags & UInt32(kFSEventStreamEventFlagItemCreated) != 0 {
            eventType = .created
        } else {
            eventType = .modified
        }

        let event = FileSystemEvent(path: url, eventType: eventType)
        Task { @MainActor in
            await service.handleFileEvent(event)
        }
    }
}
