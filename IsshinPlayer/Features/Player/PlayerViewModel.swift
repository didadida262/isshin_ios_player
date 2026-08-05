import AVFoundation
import Foundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

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
    var autoPlayNext = true
    var toastMessage: String?

    let player = AVPlayer()
    let pipManager = PictureInPictureManager()
    let nowPlaying = NowPlayingManager()

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var rateObservation: NSKeyValueObservation?
    private var wasPlayingBeforeSeek = false
    private var importGeneration = 0
    private var loadTask: Task<Void, Never>?
    private var loadSequence = 0

    var currentItem: PlaylistItem? {
        guard let currentIndex, playlist.indices.contains(currentIndex) else { return nil }
        return playlist[currentIndex]
    }

    var hasNext: Bool {
        guard let currentIndex else { return false }
        return currentIndex + 1 < playlist.count
    }

    var hasPrevious: Bool {
        guard let currentIndex else { return false }
        return currentIndex > 0
    }

    init() {
        AudioSessionManager.activatePlayback()
        player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        nowPlaying.bind(to: self)
        observePlayer()
        observeInterruptions()
    }

    deinit {
        // Avoid touching MainActor-isolated members from nonisolated deinit.
        // Observers are cleaned when replacing items / app teardown via explicit calls.
    }

    // MARK: - Import

    func importVideos(from items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        importGeneration += 1
        let generation = importGeneration
        let hadCurrent = currentItem != nil

        phase = playlist.isEmpty ? .loading : phase

        var added: [PlaylistItem] = []
        var failed = 0

        for item in items {
            guard generation == importGeneration else { return }
            do {
                guard let movie = try await Self.resolveMovie(from: item) else {
                    failed += 1
                    continue
                }
                let index = playlist.count + added.count + 1
                let rawName = movie.suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines)
                let title: String = {
                    guard let rawName, !rawName.isEmpty, !looksLikeUUIDFileName(rawName) else {
                        return "视频 \(index)"
                    }
                    return rawName
                }()
                let duration = await Self.loadDuration(url: movie.url)
                added.append(PlaylistItem(title: title, fileURL: movie.url, duration: duration))
            } catch {
                failed += 1
            }
        }

        guard generation == importGeneration else { return }

        if added.isEmpty {
            if playlist.isEmpty {
                phase = .error("未能导入视频，请重试")
            }
            return
        }

        playlist.append(contentsOf: added)
        if !hadCurrent, let first = added.first ?? playlist.first {
            enqueueLoad(first, autoPlay: true)
        } else if phase == .loading {
            phase = currentItem == nil ? .empty : .ready
        }

        if failed > 0 {
            // Keep playing; surface soft notice via phase only when nothing was playing
            print("Import partial failure: \(failed)/\(items.count) skipped")
        }
    }

    private func looksLikeUUIDFileName(_ name: String) -> Bool {
        name.count >= 16 && name.filter { $0 == "-" }.count >= 2
    }

    private static func resolveMovie(from item: PhotosPickerItem) async throws -> ImportedMovie? {
        if let movie = try await item.loadTransferable(type: ImportedMovie.self) {
            return movie
        }
        // Fallback: some Photos assets don't match UTType.movie cleanly
        if let data = try await item.loadTransferable(type: Data.self), !data.isEmpty {
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Imports", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appendingPathComponent("\(UUID().uuidString).mp4")
            try data.write(to: dest, options: .atomic)
            return ImportedMovie(url: dest, suggestedName: nil)
        }
        return nil
    }

    // MARK: - Playlist

    func selectItem(id: UUID) {
        guard let index = playlist.firstIndex(where: { $0.id == id }) else { return }
        guard index != currentIndex else { return }
        enqueueLoad(playlist[index], autoPlay: true)
    }

    func removeItem(id: UUID) {
        guard let index = playlist.firstIndex(where: { $0.id == id }) else { return }
        let removingCurrent = index == currentIndex
        let fileURL = playlist[index].fileURL
        playlist.remove(at: index)

        try? FileManager.default.removeItem(at: fileURL)

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
        } else if let currentIndex, index < currentIndex {
            self.currentIndex = currentIndex - 1
        }
    }

    func playNext() {
        guard let currentIndex, currentIndex + 1 < playlist.count else { return }
        enqueueLoad(playlist[currentIndex + 1], autoPlay: true)
    }

    func playPrevious() {
        guard let currentIndex, currentIndex > 0 else { return }
        enqueueLoad(playlist[currentIndex - 1], autoPlay: true)
    }

    private func enqueueLoad(_ item: PlaylistItem, autoPlay: Bool) {
        loadTask?.cancel()
        loadTask = Task { await load(item: item, autoPlay: autoPlay) }
    }

    // MARK: - Transport

    func play() {
        guard phase == .ready else { return }
        player.play()
        player.rate = playbackRate
        isPlaying = true
        nowPlaying.updateNowPlaying()
    }

    func pause() {
        player.pause()
        isPlaying = false
        nowPlaying.updateNowPlaying()
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { play() }
    }

    func setRate(_ rate: PlaybackRate) {
        playbackRate = rate.rawValue
        if isPlaying {
            player.rate = playbackRate
        }
        nowPlaying.updateNowPlaying()
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

    private func load(item: PlaylistItem, autoPlay: Bool) async {
        loadSequence += 1
        let sequence = loadSequence

        // Switching tracks: keep `.ready` so the player layer is not torn down (avoids UI freeze).
        if case .empty = phase {
            phase = .loading
        } else if case .error = phase {
            phase = .loading
        }

        player.pause()
        isPlaying = false
        currentTime = 0
        duration = item.duration ?? 0
        currentIndex = playlist.firstIndex(where: { $0.id == item.id })

        removeEndObserver()
        statusObservation?.invalidate()
        statusObservation = nil

        let playerItem = AVPlayerItem(url: item.fileURL)
        player.replaceCurrentItem(with: playerItem)

        let status = await Self.waitForReady(playerItem)
        guard !Task.isCancelled, sequence == loadSequence else { return }
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
            if autoPlay {
                play()
            }
        case .failed:
            let message = playerItem.error?.localizedDescription ?? "无法播放该视频"
            phase = .error(message)
            isPlaying = false
        default:
            phase = .error("加载超时，请重试")
            isPlaying = false
        }
    }

    private static func waitForReady(_ item: AVPlayerItem) async -> AVPlayerItem.Status {
        if item.status == .readyToPlay || item.status == .failed {
            return item.status
        }

        return await withCheckedContinuation { continuation in
            final class Box: @unchecked Sendable {
                var resumed = false
                var observation: NSKeyValueObservation?
                var timeoutTask: Task<Void, Never>?
            }
            let box = Box()

            let finish: @Sendable (AVPlayerItem.Status) -> Void = { status in
                guard !box.resumed else { return }
                box.resumed = true
                box.observation?.invalidate()
                box.timeoutTask?.cancel()
                continuation.resume(returning: status)
            }

            box.observation = item.observe(\.status, options: [.initial, .new]) { observed, _ in
                if observed.status == .readyToPlay || observed.status == .failed {
                    finish(observed.status)
                }
            }

            box.timeoutTask = Task {
                try? await Task.sleep(for: .seconds(10))
                finish(item.status == .unknown ? .unknown : item.status)
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
        if autoPlayNext, hasNext {
            playNext()
        } else {
            nowPlaying.updateNowPlaying()
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
                self.isPlaying = self.player.rate > 0
            }
        }

        rateObservation = player.observe(\.rate, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in
                self?.isPlaying = player.rate > 0
                self?.nowPlaying.updateNowPlaying()
            }
        }
    }

    private func observeInterruptions() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard
                    let info = notification.userInfo,
                    let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                    let type = AVAudioSession.InterruptionType(rawValue: typeValue)
                else { return }

                if type == .began {
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

// MARK: - Transferable movie

struct ImportedMovie: Transferable {
    let url: URL
    let suggestedName: String?

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            try Self.importFile(received)
        }
        FileRepresentation(contentType: .mpeg4Movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            try Self.importFile(received)
        }
        FileRepresentation(contentType: .quickTimeMovie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            try Self.importFile(received)
        }
        FileRepresentation(contentType: .avi) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            try Self.importFile(received)
        }
    }

    private static func importFile(_ received: ReceivedTransferredFile) throws -> ImportedMovie {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Imports", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = received.file.lastPathComponent
        let dest = dir.appendingPathComponent("\(UUID().uuidString)_\(name)")
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: received.file, to: dest)
        return ImportedMovie(
            url: dest,
            suggestedName: received.file.deletingPathExtension().lastPathComponent
        )
    }
}
