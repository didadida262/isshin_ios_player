import SwiftUI

@main
struct IsshinPlayerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Owned here, not in `PlayerView`. SwiftUI re-invokes the `WindowGroup` content
    /// closure on scene updates, which re-runs `PlayerView.init()` — and `@State`
    /// eagerly evaluates its initial value, so a view-owned model would be
    /// reconstructed on every one of those passes.
    @State private var viewModel = PlayerViewModel()

    var body: some Scene {
        WindowGroup {
            PlayerView(viewModel: viewModel)
                .preferredColorScheme(.dark)
                .tint(Theme.selectionGreen)
                .background(Theme.background.ignoresSafeArea())
        }
    }
}
