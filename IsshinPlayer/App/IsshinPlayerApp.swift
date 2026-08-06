import SwiftUI

@main
struct IsshinPlayerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            PlayerView()
                .preferredColorScheme(.dark)
                .tint(Theme.selectionGreen)
                .background(Theme.background.ignoresSafeArea())
        }
    }
}
