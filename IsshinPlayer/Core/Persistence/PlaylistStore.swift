import Foundation

/// Persists playlist metadata under Documents. Video files already live in Documents/Imports.
enum PlaylistStore {
    private static let fileName = "playlist.json"

    private struct Snapshot: Codable {
        var items: [Record]
        var currentItemID: UUID?
        var playbackMode: String
    }

    private struct Record: Codable {
        var id: UUID
        var title: String
        /// Path relative to the app Documents directory.
        var relativePath: String
        var duration: TimeInterval?
        var assetIdentifier: String?
    }

    static func load() -> (items: [PlaylistItem], currentItemID: UUID?, playbackMode: PlaybackMode) {
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
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            items.append(
                PlaylistItem(
                    id: record.id,
                    title: record.title,
                    fileURL: url,
                    duration: record.duration,
                    assetIdentifier: record.assetIdentifier
                )
            )
        }

        let mode = PlaybackMode(rawValue: snapshot.playbackMode) ?? .sequential
        let currentID = snapshot.currentItemID.flatMap { id in
            items.contains(where: { $0.id == id }) ? id : items.first?.id
        }

        // Rewrite if some files were missing, so the store stays clean.
        if items.count != snapshot.items.count {
            save(items: items, currentItemID: currentID, playbackMode: mode)
        }

        return (items, currentID, mode)
    }

    static func save(items: [PlaylistItem], currentItemID: UUID?, playbackMode: PlaybackMode) {
        let docs = documentsDirectory
        let records: [Record] = items.compactMap { item in
            guard let relative = relativePath(for: item.fileURL, documents: docs) else {
                return Record(
                    id: item.id,
                    title: item.title,
                    relativePath: "Imports/\(item.fileURL.lastPathComponent)",
                    duration: item.duration,
                    assetIdentifier: item.assetIdentifier
                )
            }
            return Record(
                id: item.id,
                title: item.title,
                relativePath: relative,
                duration: item.duration,
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
