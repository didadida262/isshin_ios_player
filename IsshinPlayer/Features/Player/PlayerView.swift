import SwiftUI

struct PlayerView: View {
    @State private var viewModel = PlayerViewModel()
    @State private var showVideoPicker = false

    var body: some View {
        ZStack {
            (viewModel.isFullscreen ? Color.black : Theme.background)
                .ignoresSafeArea()

            VStack(spacing: viewModel.isFullscreen ? 0 : 16) {
                canvas
                    .frame(maxWidth: .infinity)
                    .modifier(PlayerStageLayout(isFullscreen: viewModel.isFullscreen))
                    .layoutPriority(1)

                if !viewModel.isFullscreen {
                    PlaylistView(viewModel: viewModel) {
                        showVideoPicker = true
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .layoutPriority(0)
                }
            }
            .padding(.horizontal, viewModel.isFullscreen ? 0 : 16)
            .padding(.bottom, viewModel.isFullscreen ? 0 : 16)
            .padding(.top, viewModel.isFullscreen ? 0 : 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .statusBarHidden(viewModel.isFullscreen)
        .persistentSystemOverlays(viewModel.isFullscreen ? .hidden : .automatic)
        .sheet(isPresented: $showVideoPicker) {
            VideoLibraryPickerView(
                loadedIdentifiers: viewModel.loadedAssetIdentifiers,
                onCancel: { showVideoPicker = false },
                onConfirm: { assets in
                    showVideoPicker = false
                    Task {
                        await viewModel.importVideos(from: assets)
                    }
                }
            )
        }
        .preferredColorScheme(.dark)
        .tint(Theme.selectionGreen)
        .overlay(alignment: .bottom) {
            if let toast = viewModel.toastMessage, !viewModel.isFullscreen {
                Text(toast)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.toastMessage)
        // Invisible hook so UIKit re-queries orientation when fullscreen flips.
        .background(OrientationRefreshHook(isFullscreen: viewModel.isFullscreen))
    }

    @ViewBuilder
    private var canvas: some View {
        ZStack {
            if viewModel.isFullscreen {
                Color.black
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Theme.border, lineWidth: 1)
                    )
            }

            switch viewModel.phase {
            case .empty:
                EmptyStateView(
                    title: "还没有视频",
                    message: "从相册导入视频，支持多选加入播放列表",
                    actionTitle: nil,
                    action: nil
                )
            case .loading:
                SkeletonBlock(height: 240)
                    .padding(12)
            case .ready:
                ZStack {
                    PlayerLayerView(player: viewModel.player) { layer in
                        viewModel.pipManager.attach(playerLayer: layer)
                    }
                    .id("isshin-main-player-layer")

                    PlayerControlsView(
                        viewModel: viewModel,
                        isFullscreen: viewModel.isFullscreen
                    )
                }
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: viewModel.isFullscreen ? 0 : 14,
                        style: .continuous
                    )
                )
                .padding(viewModel.isFullscreen ? 0 : 4)
            case .error(let message):
                ErrorStateView(message: message, retryTitle: "知道了") {
                    if viewModel.playlist.isEmpty {
                        viewModel.phase = .empty
                    } else if viewModel.currentItem != nil {
                        viewModel.phase = .ready
                    } else {
                        viewModel.phase = .empty
                    }
                }
            }
        }
    }
}

/// Inline keeps 16:10. Fullscreen fills the whole window (after landscape rotation).
private struct PlayerStageLayout: ViewModifier {
    let isFullscreen: Bool

    func body(content: Content) -> some View {
        if isFullscreen {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
        } else {
            content
                .aspectRatio(16 / 10, contentMode: .fit)
                .frame(minHeight: 180)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Ensures AppDelegate orientation mask is re-read when entering/leaving fullscreen.
private struct OrientationRefreshHook: UIViewControllerRepresentable {
    let isFullscreen: Bool

    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.isFullscreen = isFullscreen
        controller.refreshOrientation()
    }

    final class Controller: UIViewController {
        var isFullscreen = false

        override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
            OrientationManager.supportedOrientations
        }

        override var shouldAutorotate: Bool { true }

        func refreshOrientation() {
            setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }
}
