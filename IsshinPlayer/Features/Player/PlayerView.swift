import SwiftUI
import UniformTypeIdentifiers

struct PlayerView: View {
    let viewModel: PlayerViewModel
    @State private var showVideoPicker = false
    @State private var showAudioPicker = false

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
                    PlaylistView(
                        viewModel: viewModel,
                        isVideoPickerPending: showVideoPicker,
                        isAudioPickerPending: showAudioPicker,
                        onImportVideo: { showVideoPicker = true },
                        onImportAudio: { showAudioPicker = true }
                    )
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
        .fileImporter(
            isPresented: $showAudioPicker,
            allowedContentTypes: [.audio, .mp3, .mpeg4Audio, .wav, .aiff],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task { await viewModel.importAudio(from: urls) }
            case .failure(let error):
                print("Audio fileImporter failed: \(error.localizedDescription)")
                viewModel.showToast("无法打开文件选择器")
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.selectionGreen)
        .overlay(alignment: .bottom) {
            // Scoped to the overlay: on the root it animated every unrelated state
            // change in the whole tree, including picker presentation.
            ZStack {
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
        .background(OrientationRefreshHook(isFullscreen: viewModel.isFullscreen))
        .task {
            viewModel.start()
            // Off the launch critical path: the first Files-picker presentation
            // otherwise pays for DocumentManager bring-up on the user's tap.
            try? await Task.sleep(for: .seconds(2))
            AudioImportWarmup.warmUp()
        }
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
                    title: "还没有内容",
                    message: "点上方视频/音符按钮导入",
                    actionTitle: nil,
                    action: nil
                )
            case .loading:
                VStack(spacing: 14) {
                    ProgressView()
                        .tint(Theme.brandBlue)
                    Text("加载中…")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                    Button("取消") {
                        viewModel.cancelLoading()
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.brandBlue)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(12)
            case .ready:
                ZStack {
                    if viewModel.currentItem?.mediaKind == .audio {
                        AudioStageView(
                            title: viewModel.currentItem?.title ?? "音频",
                            isPlaying: viewModel.isPlaying
                        )
                        .allowsHitTesting(false)
                    } else {
                        PlayerLayerView(player: viewModel.player) { layer in
                            viewModel.pipManager.attach(playerLayer: layer)
                        }
                        .allowsHitTesting(false)
                    }

                    PlayerControlsView(
                        viewModel: viewModel,
                        isFullscreen: viewModel.isFullscreen
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: viewModel.isFullscreen ? 0 : 14,
                        style: .continuous
                    )
                )
                .padding(viewModel.isFullscreen ? 0 : 4)
            case .error(let message):
                ErrorStateView(
                    message: message,
                    retryTitle: viewModel.currentItem == nil ? "知道了" : "重试"
                ) {
                    if viewModel.currentItem == nil {
                        viewModel.dismissError()
                    } else {
                        viewModel.retryCurrent()
                    }
                }
            }
        }
    }
}

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
                .frame(maxWidth: .infinity)
                .frame(minHeight: 180)
        }
    }
}

private struct OrientationRefreshHook: UIViewControllerRepresentable {
    let isFullscreen: Bool

    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        // Only on a real change: `setNeedsUpdateOfSupportedInterfaceOrientations()`
        // triggers a geometry pass, which would feed back into this update.
        guard controller.isFullscreen != isFullscreen else { return }
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
