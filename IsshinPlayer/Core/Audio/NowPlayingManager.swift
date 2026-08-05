import MediaPlayer
import AVFoundation

@MainActor
final class NowPlayingManager {
    private weak var viewModel: PlayerViewModel?

    func bind(to viewModel: PlayerViewModel) {
        self.viewModel = viewModel
        setupRemoteCommands()
    }

    func updateNowPlaying() {
        guard let viewModel else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: viewModel.currentItem?.title ?? "Isshin",
            MPMediaItemPropertyArtist: "Isshin",
            MPNowPlayingInfoPropertyPlaybackRate: viewModel.isPlaying ? Double(viewModel.playbackRate) : 0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: viewModel.currentTime,
            MPMediaItemPropertyPlaybackDuration: viewModel.duration
        ]
        if viewModel.duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = viewModel.duration
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true
        center.changePlaybackPositionCommand.isEnabled = true

        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.viewModel?.play() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.viewModel?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.viewModel?.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let vm = self?.viewModel, vm.hasNext else { return }
                vm.playNext()
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
                } else {
                    vm.seek(to: 0)
                }
            }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor in self?.viewModel?.seek(to: event.positionTime) }
            return .success
        }
    }
}
