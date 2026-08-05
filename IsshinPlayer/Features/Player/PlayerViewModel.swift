import AVFoundation
import Foundation
import PhotosUI
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
    var autoPlayNext = true

    let player = AVPlayer()
    let pipManager = PictureInPictureManager()
    let nowPlaying = NowPlayingManager()

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var rateObservation: NSKeyValueObservation?
    private var wasPlayingBeforeSeek = false
    private var importGeneration = 0

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
        for (offset, item) in items.enumerated() {
            guard generation == importGeneration else { return }
            do {
                guard let movie = try await item.loadTransferable(type: ImportedMovie.self) else {
                    continue
                }
                let title = movie.suggestedName ?? "视频 \(playlist.count + added.count + 1)"
                let duration = await Self.loadDuration(url: movie.url)
                added.append(PlaylistItem(title: title, fileURL: movie.url, duration: duration))
            } catch {
                if playlist.isEmpty && added.isEmpty && offset == items.count - 1 {
                    phase = .error("导入失败：\(error.localizedDescription)")
                }
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
        if !hadCurrent, let first = playlist.first {
            await load(item: first, autoPlay: true)
        }
    }

    // MARK: - Playlist

    func selectItem(id: UUID) {
        guard let index = playlist.firstIndex(where: { $0.id == id }) else { return }
        guard index != currentIndex else { return }
        Task { await load(item: playlist[index], autoPlay: true) }
    }

    func removeItem(id: UUID) {
        guard let index = playlist.firstIndex(where: { $0.id == id }) else { return }
        let removingCurrent = index == currentIndex
        let fileURL = playlist[index].fileURL
        playlist.remove(at: index)

        try? FileManager.default.removeItem(at: fileURL)

        if playlist.isEmpty {
            currentIndex = nil
            stopAndClear()
            phase = .empty
            nowPlaying.clear()
            return
        }

        if removingCurrent {
            let nextIndex = min(index, playlist.count - 1)
            Task { await load(item: playlist[nextIndex], autoPlay: true) }
        } else if let currentIndex, index < currentIndex {
            self.currentIndex = currentIndex - 1
        }
    }

    func playNext() {
        guard let currentIndex, currentIndex + 1 < playlist.count else { return }
        Task { await load(item: playlist[currentIndex + 1], autoPlay: true) }
    }

    func playPrevious() {
        guard let currentIndex, currentIndex > 0 else { return }
        Task { await load(item: playlist[currentIndex - 1], autoPlay: true) }
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
        pipManager.start()
    }

    // MARK: - Load

    private func load(item: PlaylistItem, autoPlay: Bool) async {
        phase = .loading
        currentTime = 0
        duration = item.duration ?? 0
        currentIndex = playlist.firstIndex(where: { $0.id == item.id })

        removeEndObserver()
        statusObservation?.invalidate()

        let playerItem = AVPlayerItem(url: item.fileURL)
        player.replaceCurrentItem(with: playerItem)

        statusObservation = playerItem.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    let seconds = item.duration.seconds
                    if seconds.isFinite && !seconds.isNaN {
                        self.duration = seconds
                        if let idx = self.currentIndex {
                            self.playlist[idx].duration = seconds
                        }
                    }
                    self.phase = .ready
                    self.nowPlaying.updateNowPlaying()
                    if autoPlay {
                        self.play()
                    }
                case .failed:
                    let message = item.error?.localizedDescription ?? "无法播放该视频"
                    self.phase = .error(message)
                    self.isPlaying = false
                default:
                    break
                }
            }
        }

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
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Imports", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let name = received.file.lastPathComponent
            let dest = dir.appendingPathComponent("\(UUID().uuidString)_\(name)")
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: received.file, to: dest)
            return ImportedMovie(url: dest, suggestedName: received.file.deletingPathExtension().lastPathComponent)
        }
    }
}
