import Foundation

/// Persists playlist metadata under Documents. Media files live in Documents/Imports.
enum PlaylistStore {
    private static let fileName = "playlist.json"
    /// Bump when the on-disk format or restore semantics change in a breaking way.
    /// Triggers a one-time wipe of playlist metadata + Imports so stale data
    /// from buggy builds cannot brick a fresh install path.
    private static let schemaVersion = 4
    private static let schemaVersionKey = "isshin.playlistStore.schemaVersion"

    private struct Snapshot: Codable {
        var items: [Record]
        var currentItemID: UUID?
        var playbackMode: String
    }

    private struct Record: Codable {
        var id: UUID
        var title: String
        var relativePath: String
        var duration: TimeInterval?
        var mediaKind: String?
        var assetIdentifier: String?
    }

    static func load() -> (items: [PlaylistItem], currentItemID: UUID?, playbackMode: PlaybackMode) {
        migrateSchemaIfNeeded()

        guard let data = try? Data(contentsOf: storeURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
        else {
            return ([], nil, .sequential)
        }

        let docs = documentsDirectory
        var items: [PlaylistItem] = []
        items.reserveCapacity(snapshot.items.count)

        for record in snapshot.items {
            let url = docs.appendingPathComponent(record.relativePath)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue
            else { continue }

            // Skip empty / clearly broken leftovers from failed imports.
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? NSNumber,
               size.intValue < 64 {
                continue
            }

            let kind = record.mediaKind.flatMap(MediaKind.init(rawValue:)) ?? .infer(from: url)
            items.append(
                PlaylistItem(
                    id: record.id,
                    title: record.title,
                    fileURL: url,
                    duration: record.duration,
                    mediaKind: kind,
                    assetIdentifier: record.assetIdentifier
                )
            )
        }

        let mode = PlaybackMode(rawValue: snapshot.playbackMode) ?? .sequential
        let currentID = snapshot.currentItemID.flatMap { id in
            items.contains(where: { $0.id == id }) ? id : items.first?.id
        }

        if items.count != snapshot.items.count {
            save(items: items, currentItemID: currentID, playbackMode: mode)
        }

        return (items, currentID, mode)
    }

    static func save(items: [PlaylistItem], currentItemID: UUID?, playbackMode: PlaybackMode) {
        let docs = documentsDirectory
        let records: [Record] = items.compactMap { item in
            let relative = relativePath(for: item.fileURL, documents: docs)
                ?? "Imports/\(item.fileURL.lastPathComponent)"
            return Record(
                id: item.id,
                title: item.title,
                relativePath: relative,
                duration: item.duration,
                mediaKind: item.mediaKind.rawValue,
                assetIdentifier: item.assetIdentifier
            )
        }

        let snapshot = Snapshot(
            items: records,
            currentItemID: currentItemID,
            playbackMode: playbackMode.rawValue
        )

        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: storeURL, options: [.atomic])
        } catch {
            print("PlaylistStore save failed: \(error)")
        }
    }

    /// One-time cleanup after schema bumps (and for recovering from corrupt local state).
    private static func migrateSchemaIfNeeded() {
        let current = UserDefaults.standard.integer(forKey: schemaVersionKey)
        guard current < schemaVersion else { return }

        let fm = FileManager.default
        try? fm.removeItem(at: storeURL)
        let imports = documentsDirectory.appendingPathComponent("Imports", isDirectory: true)
        try? fm.removeItem(at: imports)
        try? fm.createDirectory(at: imports, withIntermediateDirectories: true)

        UserDefaults.standard.set(schemaVersion, forKey: schemaVersionKey)
        print("PlaylistStore: wiped local media for schema \(current) → \(schemaVersion)")
    }

    private static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private static var storeURL: URL {
        documentsDirectory.appendingPathComponent(fileName)
    }

    private static func relativePath(for fileURL: URL, documents: URL) -> String? {
        let filePath = fileURL.standardizedFileURL.path
        let docsPath = documents.standardizedFileURL.path
        guard filePath.hasPrefix(docsPath) else { return nil }
        var relative = String(filePath.dropFirst(docsPath.count))
        if relative.hasPrefix("/") {
            relative.removeFirst()
        }
        return relative.isEmpty ? nil : relative
    }
}
