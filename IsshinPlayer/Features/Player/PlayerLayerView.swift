import AVFoundation
import SwiftUI

struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    var onLayerReady: ((AVPlayerLayer) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onLayerReady: onLayerReady)
    }

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.backgroundColor = .black
        let coordinator = context.coordinator
        view.onLayout = { layer in
            coordinator.emit(layer)
        }
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        context.coordinator.onLayerReady = onLayerReady
        // Keep the same AVPlayer attached — never bounce player to nil during layout updates.
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
        uiView.playerLayer.videoGravity = .resizeAspect
        uiView.backgroundColor = .black
        let coordinator = context.coordinator
        uiView.onLayout = { layer in
            coordinator.emit(layer)
        }
        if uiView.bounds.width > 1 {
            coordinator.emit(uiView.playerLayer)
        }
    }

    final class Coordinator {
        var onLayerReady: ((AVPlayerLayer) -> Void)?
        private var lastSize: CGSize = .zero

        init(onLayerReady: ((AVPlayerLayer) -> Void)?) {
            self.onLayerReady = onLayerReady
        }

        func emit(_ layer: AVPlayerLayer) {
            let size = layer.bounds.size
            guard size.width > 1, size.height > 1 else { return }
            // Avoid spamming attach on every tiny layout pass
            if abs(size.width - lastSize.width) < 0.5, abs(size.height - lastSize.height) < 0.5,
               lastSize != .zero {
                onLayerReady?(layer)
                return
            }
            lastSize = size
            onLayerReady?(layer)
        }
    }
}

final class PlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    var onLayout: ((AVPlayerLayer) -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?(playerLayer)
    }
}
