import SwiftUI

@main
struct IsshinPlayerApp: App {
    var body: some Scene {
        WindowGroup {
            PlayerView()
                .preferredColorScheme(.dark)
                .tint(Theme.selectionGreen)
                .background(Theme.background.ignoresSafeArea())
        }
    }
}
