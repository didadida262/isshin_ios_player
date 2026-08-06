import AVKit

@MainActor
@Observable
final class PictureInPictureManager: NSObject, AVPictureInPictureControllerDelegate {
    var isSupported = AVPictureInPictureController.isPictureInPictureSupported()
    var isPossible = false
    var isActive = false
    var lastErrorMessage: String?

    private var controller: AVPictureInPictureController?
    private var observations: [NSKeyValueObservation] = []
    private weak var boundLayer: AVPlayerLayer?

    func attach(playerLayer: AVPlayerLayer) {
        guard playerLayer.bounds.width > 1, playerLayer.bounds.height > 1 else { return }

        // Same layer already bound — do nothing. Re-creating PiP thrash stalls AVPlayer.
        if boundLayer === playerLayer, controller != nil {
            return
        }

        tearDown()
        boundLayer = playerLayer

        guard isSupported else {
            isPossible = false
            return
        }

        // Don't reconfigure AVAudioSession here — PlayerViewModel owns the session.
        guard let pip = AVPictureInPictureController(playerLayer: playerLayer) else {
            isPossible = false
            lastErrorMessage = "无法创建画中画控制器"
            return
        }

        pip.delegate = self
        pip.canStartPictureInPictureAutomaticallyFromInline = false
        controller = pip

        observations.append(pip.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] ctrl, _ in
            Task { @MainActor in
                self?.isPossible = ctrl.isPictureInPicturePossible
            }
        })
        observations.append(pip.observe(\.isPictureInPictureActive, options: [.initial, .new]) { [weak self] ctrl, _ in
            Task { @MainActor in
                self?.isActive = ctrl.isPictureInPictureActive
            }
        })
    }

    @discardableResult
    func start() -> String? {
        guard isSupported else {
            return "当前环境不支持画中画"
        }
        guard let controller else {
            return "播放器未就绪，请稍后再试"
        }
        guard controller.isPictureInPicturePossible else {
            // Simulator commonly stays false forever.
            #if targetEnvironment(simulator)
            return "模拟器通常无法使用画中画，请用真机测试"
            #else
            return "画中画暂不可用，请确认视频已开始播放后再试"
            #endif
        }
        lastErrorMessage = nil
        controller.startPictureInPicture()
        return nil
    }

    func stop() {
        controller?.stopPictureInPicture()
    }

    private func refreshPossible() {
        isPossible = controller?.isPictureInPicturePossible ?? false
    }

    private func tearDown() {
        observations.forEach { $0.invalidate() }
        observations.removeAll()
        controller?.delegate = nil
        controller = nil
        boundLayer = nil
        isPossible = false
        isActive = false
    }

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor in
            isActive = true
            lastErrorMessage = nil
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor in isActive = false }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        Task { @MainActor in
            isActive = false
            lastErrorMessage = error.localizedDescription
        }
    }
}
