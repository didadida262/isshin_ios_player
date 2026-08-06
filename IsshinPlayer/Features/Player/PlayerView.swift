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
                    .frame(maxHeight: viewModel.isFullscreen ? .infinity : nil)
                    .layoutPriority(viewModel.isFullscreen ? 1 : 0)

                if !viewModel.isFullscreen {
                    PlaylistView(viewModel: viewModel) {
                        showVideoPicker = true
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .layoutPriority(1)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, viewModel.isFullscreen ? 0 : 16)
            .padding(.bottom, viewModel.isFullscreen ? 0 : 16)
            .padding(.top, viewModel.isFullscreen ? 0 : 8)
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
    }

    @ViewBuilder
    private var canvas: some View {
        ZStack {
            if !viewModel.isFullscreen {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Theme.border, lineWidth: 1)
                    )
            } else {
                Color.black
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
                // Keep a single PlayerLayerView identity across inline ↔ fullscreen.
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
                .padding(viewModel.isFullscreen ? 0 : 8)
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
        .frame(maxWidth: .infinity, maxHeight: viewModel.isFullscreen ? .infinity : nil)
        .aspectRatio(viewModel.isFullscreen ? nil : 16 / 10, contentMode: .fit)
        .animation(nil, value: viewModel.phase)
    }
}
