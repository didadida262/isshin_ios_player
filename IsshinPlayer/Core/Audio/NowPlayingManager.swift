import MediaPlayer
import AVFoundation
import UIKit

@MainActor
final class NowPlayingManager {
    private weak var viewModel: PlayerViewModel?
    private var lastPublishedSecond: Int = -1
    private var cachedArtwork: MPMediaItemArtwork?
    private var didBind = false
    private var lastCommandState: CommandState?

    /// Writing `MPRemoteCommand.isEnabled` notifies the system that the app's remote
    /// control capabilities changed, which invalidates the SwiftUI scene. Writing it
    /// unconditionally therefore creates an update → scene-invalidate → update loop,
    /// so the last published values are cached and only real changes are pushed.
    private struct CommandState: Equatable {
        var hasItems: Bool
        var canNext: Bool
        var canPrevious: Bool
    }

    func bind(to viewModel: PlayerViewModel) {
        guard !didBind else { return }
        didBind = true
        self.viewModel = viewModel
        UIApplication.shared.beginReceivingRemoteControlEvents()
        setupRemoteCommands()
        // Build artwork once off the main actor so launch/play stay responsive.
        Task.detached(priority: .utility) {
            let artwork = NowPlayingManager.makeArtwork()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.cachedArtwork = artwork
                self.updateNowPlaying()
            }
        }
        refreshCommandAvailability()
    }

    func updateNowPlaying() {
        guard let viewModel else { return }

        let rate = viewModel.isPlaying ? Double(viewModel.playbackRate) : 0
        let elapsed = max(0, viewModel.currentTime)
        let duration = viewModel.duration

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: viewModel.currentItem?.title ?? "Isshin",
            MPMediaItemPropertyArtist: "Isshin Player",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: rate,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: Double(max(viewModel.playbackRate, 0.1))
        ]

        if duration.isFinite, duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }

        if let artwork = cachedArtwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        lastPublishedSecond = Int(elapsed)
        refreshCommandAvailability()
    }

    /// Lightweight lock-screen progress update — never reloads artwork.
    func publishProgressIfNeeded() {
        guard let viewModel, viewModel.isPlaying else { return }
        let second = Int(viewModel.currentTime)
        guard second != lastPublishedSecond else { return }
        lastPublishedSecond = second

        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = max(0, viewModel.currentTime)
        info[MPNowPlayingInfoPropertyPlaybackRate] = Double(viewModel.playbackRate)
        if viewModel.duration.isFinite, viewModel.duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = viewModel.duration
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        lastPublishedSecond = -1
        lastCommandState = nil
        refreshCommandAvailability()
    }

    private func refreshCommandAvailability() {
        let count = viewModel?.playlist.count ?? 0
        let state = CommandState(
            hasItems: count > 0,
            canNext: count > 0 && ((viewModel?.hasNext ?? false) || count > 1),
            canPrevious: count > 0 && ((viewModel?.hasPrevious ?? false) || (viewModel?.currentTime ?? 0) > 0.5)
        )
        guard state != lastCommandState else { return }
        lastCommandState = state

        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = state.hasItems
        center.pauseCommand.isEnabled = state.hasItems
        center.togglePlayPauseCommand.isEnabled = state.hasItems
        center.nextTrackCommand.isEnabled = state.canNext
        center.previousTrackCommand.isEnabled = state.canPrevious
        center.changePlaybackPositionCommand.isEnabled = state.hasItems
    }

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        [
            center.playCommand,
            center.pauseCommand,
            center.togglePlayPauseCommand,
            center.nextTrackCommand,
            center.previousTrackCommand,
            center.changePlaybackPositionCommand
        ].forEach { $0.removeTarget(nil) }

        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.viewModel?.play()
                self?.updateNowPlaying()
            }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.viewModel?.pause()
                self?.updateNowPlaying()
            }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.viewModel?.togglePlayPause()
                self?.updateNowPlaying()
            }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let vm = self?.viewModel else { return }
                if vm.hasNext {
                    vm.playNext()
                } else if vm.playlist.count > 1, let first = vm.playlist.first {
                    vm.selectItem(id: first.id)
                }
                self?.updateNowPlaying()
            }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let vm = self?.viewModel else { return }
                if vm.currentTime > 3 {
                    vm.seek(to: 0)
                } else if vm.hasPrevious {
                    vm.playPrevious()
                } else if vm.playlist.count > 1, let last = vm.playlist.last {
                    vm.selectItem(id: last.id)
                } else {
                    vm.seek(to: 0)
                }
                self?.updateNowPlaying()
            }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor in
                self?.viewModel?.seek(to: event.positionTime)
                self?.updateNowPlaying()
            }
            return .success
        }
    }

    nonisolated private static func makeArtwork() -> MPMediaItemArtwork {
        let side: CGFloat = 200
        let size = CGSize(width: side, height: side)
        let image: UIImage
        if let source = UIImage(named: "BrandLogo") ?? UIImage(named: "IsshinLogo") {
            let renderer = UIGraphicsImageRenderer(size: size)
            image = renderer.image { _ in
                source.draw(in: CGRect(origin: .zero, size: size))
            }
        } else {
            image = placeholderArtworkImage(size: size)
        }
        return MPMediaItemArtwork(boundsSize: size) { _ in image }
    }

    nonisolated private static func placeholderArtworkImage(size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor(white: 0.12, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.15, green: 0.72, blue: 1.0, alpha: 1).setFill()
            let inset = size.width * 0.28
            UIBezierPath(
                roundedRect: CGRect(
                    x: inset,
                    y: inset,
                    width: size.width - inset * 2,
                    height: size.height - inset * 2
                ),
                cornerRadius: 16
            ).fill()
        }
    }
}
