import PhotosUI
import SwiftUI

struct PlayerView: View {
    @State private var viewModel = PlayerViewModel()
    @State private var showVideoPicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    canvas
                    PlaylistView(viewModel: viewModel)
                }
                .padding(16)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showVideoPicker = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
            }
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .background {
                VideoPhotosPicker(isPresented: $showVideoPicker) { results in
                    Task {
                        await viewModel.importVideos(from: results)
                    }
                }
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.selectionGreen)
        .overlay(alignment: .bottom) {
            if let toast = viewModel.toastMessage {
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
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Theme.border, lineWidth: 1)
                )

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
                    PlayerControlsView(viewModel: viewModel)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(8)
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
        .frame(minHeight: 280)
        .aspectRatio(16 / 10, contentMode: .fit)
        .animation(.easeInOut(duration: 0.2), value: viewModel.phase)
    }
}
