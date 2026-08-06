import MediaPlayer
import AVFoundation
import UIKit

@MainActor
final class NowPlayingManager {
    private weak var viewModel: PlayerViewModel?
    private var lastPublishedSecond: Int = -1

    func bind(to viewModel: PlayerViewModel) {
        self.viewModel = viewModel
        UIApplication.shared.beginReceivingRemoteControlEvents()
        setupRemoteCommands()
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

        if let artwork = brandArtwork() {
            info[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        lastPublishedSecond = Int(elapsed)
        refreshCommandAvailability()
    }

    /// Push elapsed time while playing so the lock-screen scrubber keeps moving.
    func publishProgressIfNeeded(force: Bool = false) {
        guard let viewModel, viewModel.isPlaying else { return }
        let second = Int(viewModel.currentTime)
        guard force || second != lastPublishedSecond else { return }
        updateNowPlaying()
    }

    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        lastPublishedSecond = -1
        refreshCommandAvailability()
    }

    private func refreshCommandAvailability() {
        let center = MPRemoteCommandCenter.shared()
        let hasItems = !(viewModel?.playlist.isEmpty ?? true)
        let hasNext = viewModel?.hasNext ?? false
        let hasPrevious = viewModel?.hasPrevious ?? false
        let currentTime = viewModel?.currentTime ?? 0

        center.playCommand.isEnabled = hasItems
        center.pauseCommand.isEnabled = hasItems
        center.togglePlayPauseCommand.isEnabled = hasItems
        // Always allow next/prev when there is something loaded — prev seeks to start,
        // next no-ops gracefully if this is the last item.
        center.nextTrackCommand.isEnabled = hasItems && (hasNext || (viewModel?.playlist.count ?? 0) > 1)
        center.previousTrackCommand.isEnabled = hasItems && (hasPrevious || currentTime > 0.5)
        center.changePlaybackPositionCommand.isEnabled = hasItems
    }

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        // Avoid duplicate handlers if bind is ever called again.
        [
            center.playCommand,
            center.pauseCommand,
            center.togglePlayPauseCommand,
            center.nextTrackCommand,
            center.previousTrackCommand,
            center.changePlaybackPositionCommand
        ].forEach { $0.removeTarget(nil) }

        center.playCommand.addTarget { [weak self] _ in
            self?.performOnMain { $0.play() } ?? .commandFailed
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.performOnMain { $0.pause() } ?? .commandFailed
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.performOnMain { $0.togglePlayPause() } ?? .commandFailed
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.performOnMain { vm in
                if vm.hasNext {
                    vm.playNext()
                } else if vm.playlist.count > 1, let first = vm.playlist.first {
                    vm.selectItem(id: first.id)
                }
            } ?? .commandFailed
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.performOnMain { vm in
                if vm.currentTime > 3 {
                    vm.seek(to: 0)
                } else if vm.hasPrevious {
                    vm.playPrevious()
                } else if vm.playlist.count > 1, let last = vm.playlist.last {
                    vm.selectItem(id: last.id)
                } else {
                    vm.seek(to: 0)
                }
            } ?? .commandFailed
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            return self?.performOnMain { $0.seek(to: event.positionTime) } ?? .commandFailed
        }
    }

    /// Remote callbacks arrive off the main actor; hop over and run synchronously.
    private func performOnMain(_ work: @escaping @MainActor (PlayerViewModel) -> Void) -> MPRemoteCommandHandlerStatus {
        guard viewModel != nil else { return .commandFailed }

        if Thread.isMainThread {
            if let vm = viewModel {
                MainActor.assumeIsolated {
                    work(vm)
                    updateNowPlaying()
                }
            }
            return .success
        }

        var status: MPRemoteCommandHandlerStatus = .commandFailed
        DispatchQueue.main.sync {
            if let vm = viewModel {
                work(vm)
                updateNowPlaying()
                status = .success
            }
        }
        return status
    }

    private func brandArtwork() -> MPMediaItemArtwork? {
        let image = UIImage(named: "BrandLogo")
            ?? UIImage(named: "IsshinLogo")
            ?? placeholderArtworkImage()
        let size = image.size
        return MPMediaItemArtwork(boundsSize: size) { _ in image }
    }

    private func placeholderArtworkImage() -> UIImage {
        let size = CGSize(width: 200, height: 200)
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
