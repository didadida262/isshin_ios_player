import AVKit

@MainActor
@Observable
final class PictureInPictureManager: NSObject, AVPictureInPictureControllerDelegate {
    var isPossible = false
    var isActive = false

    private var controller: AVPictureInPictureController?
    private var observations: [NSKeyValueObservation] = []

    func attach(playerLayer: AVPlayerLayer) {
        // Re-attach only when layer identity changes
        if controller?.playerLayer === playerLayer { return }

        tearDown()

        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            isPossible = false
            return
        }

        let pip = AVPictureInPictureController(playerLayer: playerLayer)
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

    func start() {
        guard let controller, controller.isPictureInPicturePossible else { return }
        controller.startPictureInPicture()
    }

    func stop() {
        controller?.stopPictureInPicture()
    }

    private func tearDown() {
        observations.forEach { $0.invalidate() }
        observations.removeAll()
        controller?.delegate = nil
        controller = nil
        isPossible = false
        isActive = false
    }

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor in isActive = true }
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
        Task { @MainActor in isActive = false }
    }
}
