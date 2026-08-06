import UIKit

enum OrientationManager {
    private(set) static var supportedOrientations: UIInterfaceOrientationMask = .portrait

    static func lockPortrait() {
        supportedOrientations = .portrait
        request(.portrait)
    }

    static func lockLandscape() {
        // Landscape-only while fullscreen so the system actually rotates.
        supportedOrientations = .landscape
        request(.landscape)
    }

    private static func request(_ orientations: UIInterfaceOrientationMask) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
                ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }

        // Tell every VC to re-query AppDelegate / supportedInterfaceOrientations.
        scene.windows.forEach { window in
            window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }

        let preferences = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: orientations)
        scene.requestGeometryUpdate(preferences) { _ in
            // Retry once after the mask has propagated.
            DispatchQueue.main.async {
                scene.windows.forEach { window in
                    window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
                }
                scene.requestGeometryUpdate(preferences) { _ in }
            }
        }
    }
}
