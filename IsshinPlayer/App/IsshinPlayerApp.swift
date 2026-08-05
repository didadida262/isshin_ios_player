import SwiftUI

@main
struct IsshinPlayerApp: App {
    var body: some Scene {
        WindowGroup {
            PlayerView()
                .preferredColorScheme(.dark)
                .background(Theme.background.ignoresSafeArea())
        }
    }
}
