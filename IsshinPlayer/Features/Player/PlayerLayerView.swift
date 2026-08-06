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
        view.isUserInteractionEnabled = false
        let coordinator = context.coordinator
        view.onLayout = { layer in
            coordinator.emit(layer)
        }
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        context.coordinator.onLayerReady = onLayerReady
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
        uiView.playerLayer.videoGravity = .resizeAspect
        uiView.isUserInteractionEnabled = false
        // Do not re-emit from updateUIView — that thrashes PiP attach and can stall playback.
        let coordinator = context.coordinator
        uiView.onLayout = { layer in
            coordinator.emit(layer)
        }
    }

    final class Coordinator {
        var onLayerReady: ((AVPlayerLayer) -> Void)?
        private var lastSize: CGSize = .zero
        private var didEmitOnce = false

        init(onLayerReady: ((AVPlayerLayer) -> Void)?) {
            self.onLayerReady = onLayerReady
        }

        func emit(_ layer: AVPlayerLayer) {
            let size = layer.bounds.size
            guard size.width > 8, size.height > 8 else { return }

            if didEmitOnce,
               abs(size.width - lastSize.width) < 0.5,
               abs(size.height - lastSize.height) < 0.5 {
                return
            }
            lastSize = size
            didEmitOnce = true
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
