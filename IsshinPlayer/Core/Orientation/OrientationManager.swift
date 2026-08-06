import UIKit

enum OrientationManager {
    /// Default: portrait for the main browsing UI.
    private(set) static var supportedOrientations: UIInterfaceOrientationMask = .portrait

    static func lockPortrait() {
        supportedOrientations = .portrait
        apply(.portrait)
    }

    /// Prefer landscape, but keep portrait allowed so a failed rotation
    /// cannot trap the UI in an unsupported-orientation limbo.
    static func preferLandscapeFullscreen() {
        supportedOrientations = .allButUpsideDown
        apply(.landscape)
    }

    private static func apply(_ orientations: UIInterfaceOrientationMask) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
                ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }

        let preferences = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: orientations)
        scene.requestGeometryUpdate(preferences) { _ in }

        scene.windows.forEach { window in
            window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }
}
