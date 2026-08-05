import AVFoundation
import SwiftUI

struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    var onLayerReady: ((AVPlayerLayer) -> Void)?

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.backgroundColor = .black
        DispatchQueue.main.async {
            onLayerReady?(view.playerLayer)
        }
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.playerLayer.player = player
        DispatchQueue.main.async {
            onLayerReady?(uiView.playerLayer)
        }
    }
}

final class PlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
