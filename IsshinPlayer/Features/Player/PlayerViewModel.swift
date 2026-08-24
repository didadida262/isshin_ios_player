import AVFoundation
import Foundation
import Photos
import SwiftUI

@MainActor
@Observable
final class PlayerViewModel {
    private(set) var playlist: [PlaylistItem] = []
    private(set) var currentIndex: Int?
    var phase: PlayerPhase = .empty
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var isSeeking = false

    var playbackRate: Float = PlaybackRate.x1.rawValue
    var playbackMode: PlaybackMode = .sequential
    var toastMessage: String?
    var isFullscreen = false

    let player = AVPlayer()
    let pipManager = PictureInPictureManager()
    let nowPlaying = NowPlayingManager()

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var rateObservation: NSKeyValueObservation?
    private var wasPlayingBeforeSeek = false
    private var importGeneration = 0
    private var loadTask: Task<Void, Never>?
    private var loadSequence = 0
    private var persistTask: Task<Void, Never>?
    private var didStart = false
    private var hasRestoredPlaylist = false
    private var pendingOpenURLs: [URL] = []

    var currentItem: PlaylistItem? {
        guard let currentIndex, playlist.indices.contains(currentIndex) else { return nil }
        return playlist[currentIndex]
    }

    /// Photos asset IDs already present in the playlist (for picker “已加载” state).
    var loadedAssetIdentifiers: Set<String> {
        Set(playlist.compactMap(\.assetIdentifier))
    }

    /// File fingerprints (size + original name) for folder-browser “已加载” state.
    var loadedFileFingerprints: Set<String> {
        Set(playlist.compactMap { FileImportIdentity.fingerprint(forPlaylistFileURL: $0.fileURL) })
    }

    var hasNext: Bool {
        currentItem != nil && !playlist.isEmpty
    }

    var hasPrevious: Bool {
        currentItem != nil && !playlist.isEmpty
    }

    /// `init` must stay free of global side effects.
    ///
    /// `@State`'s initial value is *not* an autoclosure, so `PlayerViewModel()` is
    /// constructed on every enclosing `View.init()` and most of those instances are
    /// thrown away immediately. Touching `AVAudioSession`, `MPRemoteCommandCenter` or
    /// the disk here previously invalidated the SwiftUI scene from a discarded
    /// instance, which produced an endless view-rebuild loop.
    init() {}

    deinit {
        // Avoid touching MainActor-isolated members from nonisolated deinit.
        // Call `teardown()` explicitly when a view model is retired.
    }

    /// Wires up everything with real side effects. Idempotent.
    func start() {
        guard !didStart else { return }
        didStart = true

        player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        AudioSessionManager.activatePlayback()
        nowPlaying.bind(to: self)
        observePlayer()
        observeInterruptions()

        Task { @MainActor in
            await restorePersistedState()
        }
    }

    func teardown() {
        loadTask?.cancel()
        persistTask?.cancel()
        removeEndObserver()
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
            self.interruptionObserver = nil
        }
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        statusObservation?.invalidate()
        statusObservation = nil
        rateObservation?.invalidate()
        rateObservation = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    private func restorePersistedState() async {
        // Disk read + file existence checks off the main actor.
        let restored = await Task.detached(priority: .userInitiated) {
            PlaylistStore.load()
        }.value

        playbackMode = restored.playbackMode
        playlist = restored.items
        guard let firstID = restored.currentItemID ?? playlist.first?.id,
              let item = playlist.first(where: { $0.id == firstID }) ?? playlist.first
        else {
            phase = .empty
            hasRestoredPlaylist = true
            await flushPendingOpenURLs()
            return
        }
        enqueueLoad(item, autoPlay: false)
        hasRestoredPlaylist = true
        await flushPendingOpenURLs()
    }

    /// Entry point for system “Open In / Share → Isshin Player”.
    /// Queues until playlist restore finishes so we don't race cold launch.
    func handleIncomingURLs(_ urls: [URL]) {
        let files = urls.filter { $0.isFileURL }
        guard !files.isEmpty else { return }
        pendingOpenURLs.append(contentsOf: files)
        start()
        Task { await flushPendingOpenURLs() }
    }

    private func flushPendingOpenURLs() async {
        guard hasRestoredPlaylist, !pendingOpenURLs.isEmpty else { return }
        let urls = pendingOpenURLs
        pendingOpenURLs.removeAll()
        await importOpenedFiles(from: urls)
    }

    /// Coalesced so a multi-item import doesn't encode + write JSON once per item.
    private func persistPlaylist() {
        let items = playlist
        let currentID = currentItem?.id
        let mode = playbackMode
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await Task.detached(priority: .utility) {
                PlaylistStore.save(items: items, currentItemID: currentID, playbackMode: mode)
            }.value
            _ = self
        }
    }

    // MARK: - Import

    func importVideos(from assets: [PHAsset]) async {
        guard !assets.isEmpty else { return }
        importGeneration += 1
        let generation = importGeneration
        let hadCurrent = currentItem != nil
        let alreadyLoaded = loadedAssetIdentifiers
        let startedEmpty = playlist.isEmpty

        // Never park the whole player canvas on `.loading` during import —
        // that black "加载中" screen eats all taps if export is slow.
        showToast(startedEmpty ? "正在导入…" : "正在导入 \(assets.count) 个视频…")

        var added: [PlaylistItem] = []
        var failed = 0

        defer {
            // Only clear a stuck skeleton when nothing was added and nothing is loaded.
            if phase == .loading, playlist.isEmpty, currentItem == nil {
                phase = .empty
            }
        }

        for asset in assets {
            guard generation == importGeneration else { return }
            let assetID = asset.localIdentifier
            if alreadyLoaded.contains(assetID) { continue }

            do {
                // Heavy Photos/file I/O off the main actor so the UI stays responsive.
                let movie: ImportedMovie? = try await Task.detached(priority: .userInitiated) {
                    try await Self.exportMovie(from: asset)
                }.value
                guard let movie else {
                    failed += 1
                    continue
                }
                let index = playlist.count + added.count + 1
                // `PHAssetResource.assetResources` is a synchronous Photos query;
                // keep it (and the duration probe) off the main actor.
                let title = await Task.detached(priority: .userInitiated) {
                    Self.displayTitle(for: asset, imported: movie, fallbackIndex: index)
                }.value
                let duration = await Self.loadDuration(url: movie.url) ?? asset.duration
                added.append(
                    PlaylistItem(
                        title: title,
                        fileURL: movie.url,
                        duration: duration,
                        mediaKind: .video,
                        assetIdentifier: assetID
                    )
                )
                // Surface each finished item immediately so the list isn't blank for minutes.
                playlist.append(added.last!)
                persistPlaylist()
                if !hadCurrent, currentItem == nil, let first = added.first, added.count == 1 {
                    enqueueLoad(first, autoPlay: true)
                }
            } catch {
                failed += 1
                print("Video import failed: \(error.localizedDescription)")
            }
        }

        guard generation == importGeneration else { return }

        if added.isEmpty {
            if startedEmpty {
                phase = .error("未能导入视频，请重试")
            } else {
                showToast("未能导入所选视频")
            }
            return
        }

        if failed > 0 {
            showToast("已导入 \(added.count) 个，跳过 \(failed) 个")
        } else if !startedEmpty {
            showToast("已导入 \(added.count) 个视频")
        }

        if phase == .loading, currentItem == nil, let first = added.first {
            enqueueLoad(first, autoPlay: true)
        } else if phase == .loading {
            phase = currentItem == nil ? .empty : .ready
        }
    }

    func importFiles(from urls: [URL]) async {
        guard !urls.isEmpty else { return }
        importGeneration += 1
        let generation = importGeneration
        let hadCurrent = currentItem != nil
        let startedEmpty = playlist.isEmpty
        var alreadyLoaded = loadedFileFingerprints

        showToast("正在导入…")

        var firstNew: PlaylistItem?
        var addedCount = 0
        var skipped = 0
        var failed = 0

        defer {
            if phase == .loading, playlist.isEmpty, currentItem == nil {
                phase = .empty
            }
        }

        for url in urls {
            guard generation == importGeneration else { return }
            if let fingerprint = FileImportIdentity.fingerprint(forSourceURL: url),
               alreadyLoaded.contains(fingerprint) {
                skipped += 1
                continue
            }

            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }

            do {
                let sourceURL = url
                let imported = try await Task.detached(priority: .userInitiated) {
                    try Self.copyImportFile(from: sourceURL)
                }.value
                let kind = MediaKind.infer(from: sourceURL)
                let index = playlist.count + 1
                let title = Self.displayTitle(
                    forOpenedURL: sourceURL,
                    imported: imported,
                    fallbackIndex: index,
                    mediaKind: kind
                )
                let duration = await Self.loadDuration(url: imported.url)
                let item = PlaylistItem(
                    title: title,
                    fileURL: imported.url,
                    duration: duration,
                    mediaKind: kind
                )
                playlist.append(item)
                addedCount += 1
                if let fingerprint = FileImportIdentity.fingerprint(forPlaylistFileURL: imported.url) {
                    alreadyLoaded.insert(fingerprint)
                }
                persistPlaylist()

                if firstNew == nil {
                    firstNew = item
                    if !hadCurrent {
                        enqueueLoad(item, autoPlay: true)
                    }
                }
            } catch {
                failed += 1
                print("File import failed: \(error.localizedDescription)")
            }
        }

        guard generation == importGeneration else { return }

        if addedCount == 0 {
            if skipped > 0, failed == 0 {
                showToast(skipped == urls.count ? "所选文件均已在列表中" : "没有新文件可导入")
            } else if startedEmpty {
                phase = .error("未能导入文件，请重试")
            } else {
                showToast("未能导入所选文件")
            }
            return
        }

        if phase == .loading, currentItem == nil {
            phase = .empty
        }

        if failed > 0 {
            showToast("已导入 \(addedCount) 个，\(failed) 个失败")
        } else if skipped > 0 {
            showToast("已导入 \(addedCount) 个，跳过 \(skipped) 个已加载")
        } else {
            showToast("已导入 \(addedCount) 个文件")
        }
    }

    /// Import files handed over by another app (Open In / document open).
    /// Always starts playback on the first successfully imported item.
    func importOpenedFiles(from urls: [URL]) async {
        guard !urls.isEmpty else { return }
        importGeneration += 1
        let generation = importGeneration
        let startedEmpty = playlist.isEmpty

        if isFullscreen {
            exitFullscreen()
        }
        showToast(urls.count == 1 ? "正在打开…" : "正在导入 \(urls.count) 个文件…")

        var firstNew: PlaylistItem?
        var addedCount = 0
        var failed = 0

        defer {
            if phase == .loading, playlist.isEmpty, currentItem == nil {
                phase = .empty
            }
        }

        for url in urls {
            guard generation == importGeneration else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }

            do {
                let sourceURL = url
                let imported = try await Task.detached(priority: .userInitiated) {
                    try Self.copyImportFile(from: sourceURL)
                }.value
                let kind = MediaKind.infer(from: sourceURL)
                let index = playlist.count + 1
                let title = Self.displayTitle(
                    forOpenedURL: sourceURL,
                    imported: imported,
                    fallbackIndex: index,
                    mediaKind: kind
                )
                let duration = await Self.loadDuration(url: imported.url)
                let item = PlaylistItem(
                    title: title,
                    fileURL: imported.url,
                    duration: duration,
                    mediaKind: kind
                )
                playlist.append(item)
                addedCount += 1
                persistPlaylist()

                if firstNew == nil {
                    firstNew = item
                }
            } catch {
                failed += 1
                print("Open-in import failed: \(error.localizedDescription)")
            }
        }

        guard generation == importGeneration else { return }

        if addedCount == 0 {
            if startedEmpty {
                phase = .error("未能打开文件，请重试")
            } else {
                showToast("未能打开所选文件")
            }
            return
        }

        if let firstNew {
            enqueueLoad(firstNew, autoPlay: true)
        }

        if failed > 0 {
            showToast("已打开 \(addedCount) 个，\(failed) 个失败")
        } else if urls.count > 1 {
            showToast("已打开 \(addedCount) 个文件")
        }
    }

    private static func displayTitle(
        forOpenedURL source: URL,
        imported: ImportedMovie,
        fallbackIndex: Int,
        mediaKind: MediaKind
    ) -> String {
        var candidates: [String] = []

        // Prefer the system-provided display name while the security scope is active.
        if let values = try? source.resourceValues(forKeys: [.localizedNameKey, .nameKey]) {
            if let name = values.localizedName { candidates.append(name) }
            if let name = values.name { candidates.append(name) }
        }
        candidates.append(source.lastPathComponent)
        if let suggested = imported.suggestedName {
            candidates.append(suggested)
        }

        // Dest is `UUID_originalName.ext` — recover the original portion.
        let destName = imported.url.lastPathComponent
        let withoutUUIDPrefix = destName.replacingOccurrences(
            of: #"^[0-9A-Fa-f]{8}-([0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}_"#,
            with: "",
            options: String.CompareOptions.regularExpression
        )
        if withoutUUIDPrefix != destName {
            candidates.append(withoutUUIDPrefix)
        }
        candidates.append(destName)

        for name in candidates {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let base = stripExtension(trimmed)
            guard !base.isEmpty, !looksLikeGeneratedName(base) else { continue }
            // Percent-encoded leftovers from some providers.
            let decoded = base.removingPercentEncoding ?? base
            let final = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !final.isEmpty else { continue }
            return final
        }

        return mediaKind == .audio ? "音频 \(fallbackIndex)" : "视频 \(fallbackIndex)"
    }

    private nonisolated static func copyImportFile(from sourceURL: URL) throws -> ImportedMovie {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Imports", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent("\(UUID().uuidString)_\(sourceURL.lastPathComponent)")
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: sourceURL, to: dest)
        return ImportedMovie(
            url: dest,
            suggestedName: sourceURL.deletingPathExtension().lastPathComponent
        )
    }

    private nonisolated static func displayTitle(
        for asset: PHAsset,
        imported: ImportedMovie,
        fallbackIndex: Int
    ) -> String {
        if let photosName = originalFilename(for: asset) {
            return stripExtension(photosName)
        }

        if let importedName = imported.suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !importedName.isEmpty,
           !looksLikeGeneratedName(importedName) {
            return stripExtension(importedName)
        }

        let fileName = imported.url.deletingPathExtension().lastPathComponent
        let cleaned = fileName.replacingOccurrences(
            of: #"^[0-9A-Fa-f-]{36}_"#,
            with: "",
            options: String.CompareOptions.regularExpression
        )
        if !cleaned.isEmpty, !looksLikeGeneratedName(cleaned) {
            return cleaned
        }

        return "视频 \(fallbackIndex)"
    }

    private nonisolated static func originalFilename(for asset: PHAsset) -> String? {
        let resources = PHAssetResource.assetResources(for: asset)
        if let video = resources.first(where: { $0.type == .video }) {
            return video.originalFilename
        }
        return resources.first?.originalFilename
    }

    private nonisolated static func stripExtension(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = (trimmed as NSString).deletingPathExtension
        return base.isEmpty ? trimmed : base
    }

    private nonisolated static func looksLikeGeneratedName(_ name: String) -> Bool {
        let base = (name as NSString).deletingPathExtension
        let target = base.isEmpty ? name : base
        // Only reject pure UUID filenames — Chinese titles often contain " - " / "-BV…"
        // and were previously misclassified by a hyphen-count heuristic.
        return target.range(
            of: #"^[0-9A-Fa-f]{8}-([0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}$"#,
            options: String.CompareOptions.regularExpression
        ) != nil
    }

    private nonisolated static func exportMovie(from asset: PHAsset) async throws -> ImportedMovie? {
        // Prefer resource export — avoids iOS 18+ AVAssetExportSession completion hangs.
        if let exported = try await exportMovieViaResourceManager(from: asset) {
            return exported
        }
        return try await exportMovieViaAVAsset(from: asset)
    }

    private nonisolated static func exportMovieViaResourceManager(from asset: PHAsset) async throws -> ImportedMovie? {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first(where: { $0.type == .video })
                ?? resources.first(where: { $0.type == .fullSizeVideo })
                ?? resources.first
        else {
            return nil
        }

        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Imports", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let filename = resource.originalFilename.isEmpty ? "video.mov" : resource.originalFilename
        let dest = dir.appendingPathComponent("\(UUID().uuidString)_\(filename)")
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    PHAssetResourceManager.default().writeData(for: resource, toFile: dest, options: options) { error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume()
                        }
                    }
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(90))
                throw NSError(
                    domain: "IsshinPlayer",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "视频导出超时"]
                )
            }
            try await group.next()
            group.cancelAll()
        }

        guard FileManager.default.fileExists(atPath: dest.path) else { return nil }
        return ImportedMovie(
            url: dest,
            suggestedName: (filename as NSString).deletingPathExtension
        )
    }

    private nonisolated static func exportMovieViaAVAsset(from asset: PHAsset) async throws -> ImportedMovie? {
        try await withThrowingTaskGroup(of: ImportedMovie?.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    let options = PHVideoRequestOptions()
                    options.isNetworkAccessAllowed = true
                    options.deliveryMode = .highQualityFormat

                    PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, info in
                        if let cancelled = info?[PHImageCancelledKey] as? Bool, cancelled {
                            continuation.resume(returning: nil)
                            return
                        }
                        if let error = info?[PHImageErrorKey] as? Error {
                            continuation.resume(throwing: error)
                            return
                        }
                        guard let urlAsset = avAsset as? AVURLAsset else {
                            continuation.resume(returning: nil)
                            return
                        }

                        do {
                            let sourceURL = urlAsset.url
                            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                                .appendingPathComponent("Imports", isDirectory: true)
                            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                            let dest = dir.appendingPathComponent("\(UUID().uuidString)_\(sourceURL.lastPathComponent)")
                            if FileManager.default.fileExists(atPath: dest.path) {
                                try FileManager.default.removeItem(at: dest)
                            }
                            try FileManager.default.copyItem(at: sourceURL, to: dest)
                            let suggested = Self.originalFilename(for: asset)
                                ?? sourceURL.deletingPathExtension().lastPathComponent
                            continuation.resume(
                                returning: ImportedMovie(url: dest, suggestedName: suggested)
                            )
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(90))
                throw NSError(
                    domain: "IsshinPlayer",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "视频导出超时"]
                )
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    // MARK: - Playlist

    /// One-shot Finder-style name sort. Import order is otherwise preserved.
    func sortPlaylistByTitle() {
        guard playlist.count > 1 else { return }
        let currentID = currentItem?.id
        playlist.sort { lhs, rhs in
            lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
        if let currentID {
            currentIndex = playlist.firstIndex(where: { $0.id == currentID })
        }
        persistPlaylist()
        showToast("已按名称排序")
    }

    func selectItem(id: UUID) {
        guard let index = playlist.firstIndex(where: { $0.id == id }) else { return }
        if index == currentIndex, phase == .ready {
            // Tapping the current row should still start playback if paused.
            if !isPlaying { play() }
            return
        }
        // Any non-ready phase (error / timeout) reloads, so a failed row is never a dead end.
        enqueueLoad(playlist[index], autoPlay: true)
        persistPlaylist()
    }

    /// Retry the current item after a load failure.
    func retryCurrent() {
        guard let item = currentItem ?? playlist.first else {
            phase = .empty
            return
        }
        enqueueLoad(item, autoPlay: true)
    }

    func removeItem(id: UUID) {
        guard let item = playlist.first(where: { $0.id == id }) else { return }
        Task { await permanentlyRemove(item) }
    }

    func removeItems(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let snapshot = playlist.filter { ids.contains($0.id) }
        guard !snapshot.isEmpty else { return }
        Task { await permanentlyRemoveItems(snapshot) }
    }

    func clearPlaylist() {
        removeItems(ids: Set(playlist.map(\.id)))
    }

    private func permanentlyRemove(_ item: PlaylistItem) async {
        guard playlist.contains(where: { $0.id == item.id }) else { return }

        if let assetID = item.assetIdentifier {
            switch await deleteFromPhotoLibrary(identifiers: [assetID]) {
            case .deleted, .nothingToDelete:
                break
            case .denied:
                showToast("需要相册权限才能彻底删除原片")
                return
            case .cancelled:
                showToast("已取消删除")
                return
            case .failed:
                showToast("未能从相册删除原片")
                return
            }
        }

        guard let index = playlist.firstIndex(where: { $0.id == item.id }) else { return }
        finishLocalRemoval(at: index)
        showToast("已彻底删除")
    }

    private func permanentlyRemoveItems(_ snapshot: [PlaylistItem]) async {
        let deletingAll = snapshot.count == playlist.count
        let photoIDs = snapshot.compactMap(\.assetIdentifier)
        if !photoIDs.isEmpty {
            switch await deleteFromPhotoLibrary(identifiers: photoIDs) {
            case .deleted, .nothingToDelete:
                break
            case .denied:
                showToast("需要相册权限才能彻底删除原片")
                return
            case .cancelled:
                showToast("已取消删除")
                return
            case .failed:
                showToast("未能从相册删除原片")
                return
            }
        }

        loadTask?.cancel()
        let urls = snapshot.map(\.fileURL)
        // Only clear items that were in the confirmed snapshot (avoid wiping newer imports).
        let ids = Set(snapshot.map(\.id))
        playlist.removeAll { ids.contains($0.id) }
        if playlist.isEmpty {
            currentIndex = nil
            stopAndClear()
            phase = .empty
            nowPlaying.clear()
        } else if let current = currentItem, let idx = playlist.firstIndex(where: { $0.id == current.id }) {
            currentIndex = idx
        } else if let first = playlist.first {
            enqueueLoad(first, autoPlay: true)
        } else {
            currentIndex = nil
            stopAndClear()
            phase = .empty
        }
        persistPlaylist()
        for url in urls {
            Self.permanentlyDeleteImportedFile(at: url)
        }
        if deletingAll {
            showToast("已彻底删除全部文件")
        } else {
            showToast("已彻底删除 \(snapshot.count) 个文件")
        }
    }

    private func finishLocalRemoval(at index: Int) {
        let removingCurrent = index == currentIndex
        let fileURL = playlist[index].fileURL

        // Release AVPlayer's hold before unlinking — otherwise removeItem can fail
        // silently while the file stays on disk.
        if removingCurrent {
            loadTask?.cancel()
            stopAndClear()
        }

        playlist.remove(at: index)
        Self.permanentlyDeleteImportedFile(at: fileURL)
        persistPlaylist()

        if playlist.isEmpty {
            loadTask?.cancel()
            currentIndex = nil
            stopAndClear()
            phase = .empty
            nowPlaying.clear()
            return
        }

        if removingCurrent {
            let nextIndex = min(index, playlist.count - 1)
            enqueueLoad(playlist[nextIndex], autoPlay: true)
            persistPlaylist()
        } else if let currentIndex, index < currentIndex {
            self.currentIndex = currentIndex - 1
            persistPlaylist()
        }
    }

    private enum PhotoDeleteResult {
        case deleted
        case nothingToDelete
        case denied
        case cancelled
        case failed
    }

    /// Deletes the original PHAssets. iOS shows its own system confirmation sheet.
    private func deleteFromPhotoLibrary(identifiers: [String]) async -> PhotoDeleteResult {
        let unique = Array(Set(identifiers))
        guard !unique.isEmpty else { return .nothingToDelete }

        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        guard status == .authorized || status == .limited else {
            return .denied
        }

        let assets = PHAsset.fetchAssets(withLocalIdentifiers: unique, options: nil)
        guard assets.count > 0 else { return .nothingToDelete }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets)
            }
            return .deleted
        } catch {
            let nsError = error as NSError
            // User dismissed the system "Delete from Photo Library?" sheet.
            if nsError.code == NSUserCancelledError
                || (nsError.domain == NSCocoaErrorDomain && nsError.code == 3072) {
                return .cancelled
            }
            print("Photos delete failed: \(error.localizedDescription)")
            return .failed
        }
    }

    /// Deletes the sandboxed import copy under Documents/Imports.
    private nonisolated static func permanentlyDeleteImportedFile(at url: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return }
        do {
            try fm.removeItem(at: url)
        } catch {
            print("Permanent delete failed: \(error.localizedDescription)")
        }
    }

    func playNext() {
        guard !playlist.isEmpty, let currentIndex else { return }
        switch playbackMode {
        case .sequential, .repeatOne:
            let next = (currentIndex + 1) % playlist.count
            enqueueLoad(playlist[next], autoPlay: true)
        case .shuffle:
            enqueueLoad(playlist[randomIndex(excluding: currentIndex)], autoPlay: true)
        }
    }

    func playPrevious() {
        guard !playlist.isEmpty, let currentIndex else { return }
        switch playbackMode {
        case .sequential, .repeatOne:
            let previous = (currentIndex - 1 + playlist.count) % playlist.count
            enqueueLoad(playlist[previous], autoPlay: true)
        case .shuffle:
            enqueueLoad(playlist[randomIndex(excluding: currentIndex)], autoPlay: true)
        }
    }

    /// Prefer a different index when the list has 2+ items.
    private func randomIndex(excluding current: Int) -> Int {
        guard playlist.count > 1 else { return max(0, min(current, playlist.count - 1)) }
        var next = Int.random(in: 0..<playlist.count)
        var attempts = 0
        while next == current, attempts < 12 {
            next = Int.random(in: 0..<playlist.count)
            attempts += 1
        }
        return next
    }

    private func enqueueLoad(_ item: PlaylistItem, autoPlay: Bool) {
        loadTask?.cancel()
        loadTask = Task { await load(item: item, autoPlay: autoPlay) }
    }

    // MARK: - Transport

    func play() {
        guard let item = player.currentItem else {
            if let current = currentItem {
                enqueueLoad(current, autoPlay: true)
            }
            return
        }
        guard item.status != .failed else {
            phase = .error(item.error?.localizedDescription ?? "无法播放该文件")
            return
        }
        if phase != .ready {
            phase = .ready
        }
        AudioSessionManager.activatePlayback()
        let rate = max(playbackRate, 0.1)
        // playImmediately is more reliable than play()+rate on recent iOS.
        player.playImmediately(atRate: rate)
        isPlaying = true
        nowPlaying.updateNowPlaying()
    }

    func pause() {
        player.pause()
        isPlaying = false
        nowPlaying.updateNowPlaying()
    }

    func togglePlayPause() {
        if isPlaying || player.rate > 0 {
            pause()
        } else {
            play()
        }
    }

    func setRate(_ rate: PlaybackRate) {
        playbackRate = rate.rawValue
        if isPlaying {
            player.rate = playbackRate
        }
        nowPlaying.updateNowPlaying()
    }

    func cyclePlaybackMode() {
        playbackMode = playbackMode.next
        persistPlaylist()
        showToast(playbackMode.title)
    }

    func beginSeek() {
        wasPlayingBeforeSeek = isPlaying
        isSeeking = true
        if isPlaying { player.pause() }
    }

    func updateSeekPreview(_ time: TimeInterval) {
        currentTime = max(0, min(time, duration > 0 ? duration : time))
    }

    func endSeek(to time: TimeInterval) {
        seek(to: time)
        isSeeking = false
        if wasPlayingBeforeSeek {
            play()
        } else {
            nowPlaying.updateNowPlaying()
        }
    }

    func seek(to time: TimeInterval) {
        let clamped = max(0, min(time, duration > 0 ? duration : time))
        let cm = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            guard finished else { return }
            Task { @MainActor in
                self?.currentTime = clamped
                self?.nowPlaying.updateNowPlaying()
            }
        }
    }

    func startPiP() {
        // Prefer playing before requesting PiP — improves isPictureInPicturePossible.
        if !isPlaying { play() }
        if let message = pipManager.start() {
            showToast(message)
        }
    }

    func enterFullscreen() {
        guard phase == .ready else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isFullscreen = true
        }
        OrientationManager.lockLandscape()
        if !isPlaying {
            play()
        }
    }

    func exitFullscreen() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isFullscreen = false
        }
        OrientationManager.lockPortrait()
    }

    func showToast(_ message: String) {
        toastMessage = message
        Task {
            try? await Task.sleep(for: .seconds(2.4))
            if toastMessage == message {
                toastMessage = nil
            }
        }
    }

    // MARK: - Load

    /// Escape hatch if anything still parks on `.loading`.
    func cancelLoading() {
        loadTask?.cancel()
        loadTask = nil
        player.pause()
        isPlaying = false
        phase = playlist.isEmpty ? .empty : .error("加载失败，点列表重试")
    }

    func dismissError() {
        phase = .empty
    }

    private func load(item: PlaylistItem, autoPlay: Bool) async {
        loadSequence += 1
        let sequence = loadSequence

        // Keep canvas interactive: never park on full-screen `.loading`.
        if case .error = phase {
            phase = .empty
        }

        player.pause()
        isPlaying = false
        currentTime = 0
        duration = item.duration ?? 0
        currentIndex = playlist.firstIndex(where: { $0.id == item.id })

        removeEndObserver()
        statusObservation?.invalidate()
        statusObservation = nil

        guard FileManager.default.isReadableFile(atPath: item.fileURL.path) else {
            guard sequence == loadSequence else { return }
            phase = .error("文件不存在或无法读取")
            isPlaying = false
            return
        }

        let asset = AVURLAsset(url: item.fileURL)
        let playerItem = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: playerItem)

        let status = await Self.waitForReady(playerItem, seconds: 8)

        guard sequence == loadSequence else { return }
        if Task.isCancelled {
            if playlist.isEmpty { phase = .empty }
            return
        }
        guard currentIndex == playlist.firstIndex(where: { $0.id == item.id }) else { return }

        switch status {
        case .readyToPlay:
            let seconds = playerItem.duration.seconds
            if seconds.isFinite && !seconds.isNaN && seconds > 0 {
                duration = seconds
                if let idx = currentIndex {
                    playlist[idx].duration = seconds
                }
            }
            phase = .ready
            nowPlaying.updateNowPlaying()
            installEndObserver(for: playerItem)
            persistPlaylist()
            if autoPlay {
                play()
            }
        case .failed:
            let message = playerItem.error?.localizedDescription ?? "无法播放该文件"
            phase = .error(message)
            isPlaying = false
        default:
            phase = .error("加载超时，请点列表重试")
            isPlaying = false
        }
    }

    private static func waitForReady(_ item: AVPlayerItem, seconds: Double) async -> AVPlayerItem.Status {
        if item.status == .readyToPlay || item.status == .failed {
            return item.status
        }

        return await withCheckedContinuation { continuation in
            final class Box: @unchecked Sendable {
                var resumed = false
                var observation: NSKeyValueObservation?
                var timeoutTask: Task<Void, Never>?
                let lock = NSLock()

                func finish(_ status: AVPlayerItem.Status, resume: (AVPlayerItem.Status) -> Void) {
                    lock.lock()
                    defer { lock.unlock() }
                    guard !resumed else { return }
                    resumed = true
                    observation?.invalidate()
                    observation = nil
                    timeoutTask?.cancel()
                    timeoutTask = nil
                    resume(status)
                }
            }
            let box = Box()

            box.observation = item.observe(\.status, options: [.initial, .new]) { observed, _ in
                if observed.status == .readyToPlay || observed.status == .failed {
                    box.finish(observed.status) { continuation.resume(returning: $0) }
                }
            }

            // Detached so a cancelled load Task cannot kill the failsafe timeout.
            box.timeoutTask = Task.detached {
                try? await Task.sleep(for: .seconds(seconds))
                let status = item.status
                box.finish(status == .unknown ? .unknown : status) { continuation.resume(returning: $0) }
            }
        }
    }

    private func installEndObserver(for playerItem: AVPlayerItem) {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handlePlaybackEnded()
            }
        }
    }

    private func handlePlaybackEnded() {
        isPlaying = false

        switch playbackMode {
        case .sequential, .shuffle:
            playNext()
        case .repeatOne:
            rewindToStart(andPlay: true)
        }
    }

    private func rewindToStart(andPlay: Bool) {
        let endItem = player.currentItem
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            guard finished else { return }
            Task { @MainActor in
                guard let self else { return }
                guard self.player.currentItem === endItem else { return }
                self.currentTime = 0
                self.nowPlaying.updateNowPlaying()
                if andPlay {
                    self.play()
                }
            }
        }
    }

    private func stopAndClear() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        isPlaying = false
        currentTime = 0
        duration = 0
        removeEndObserver()
        statusObservation?.invalidate()
        statusObservation = nil
    }

    private func observePlayer() {
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self, !self.isSeeking else { return }
                let seconds = time.seconds
                if seconds.isFinite {
                    self.currentTime = seconds
                }
                // Prefer rate as source of truth, but don't flap UI while still buffering after play().
                let ratePlaying = self.player.rate > 0.01
                if ratePlaying != self.isPlaying {
                    // Only auto-clear "playing" when rate is truly stopped; keep true while rate > 0.
                    if ratePlaying {
                        self.isPlaying = true
                    } else if self.player.timeControlStatus == .paused {
                        self.isPlaying = false
                    }
                }
                self.nowPlaying.publishProgressIfNeeded()
            }
        }

        rateObservation = player.observe(\.rate, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in
                guard let self else { return }
                let playing = player.rate > 0.01
                let changed = self.isPlaying != playing
                if playing {
                    self.isPlaying = true
                } else if player.timeControlStatus == .paused {
                    self.isPlaying = false
                }
                if changed {
                    self.nowPlaying.updateNowPlaying()
                }
            }
        }
    }

    private func observeInterruptions() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            let userInfo = notification.userInfo
            Task { @MainActor in
                guard
                    let info = userInfo,
                    let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                    let type = AVAudioSession.InterruptionType(rawValue: typeValue)
                else { return }

                if type == .began {
                    // The system deactivated our session; the next play() must re-activate.
                    AudioSessionManager.invalidate()
                    self?.pause()
                }
                // PRD: after interruption ends, stay paused
            }
        }
    }

    private func removeEndObserver() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }

    private static func loadDuration(url: URL) async -> TimeInterval? {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            let seconds = duration.seconds
            return seconds.isFinite ? seconds : nil
        } catch {
            return nil
        }
    }
}

struct ImportedMovie {
    let url: URL
    let suggestedName: String?
}
