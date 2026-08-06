import UIKit

enum OrientationManager {
    private(set) static var supportedOrientations: UIInterfaceOrientationMask = .portrait

    static func lockPortrait() {
        supportedOrientations = .portrait
        apply(.portrait)
    }

    static func lockLandscape() {
        supportedOrientations = .landscape
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
