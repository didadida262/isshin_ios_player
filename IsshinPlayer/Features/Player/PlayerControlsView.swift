import SwiftUI

/// Foreground in-player overlay controls (not lock-screen / Control Center chrome).
struct PlayerControlsView: View {
    @Bindable var viewModel: PlayerViewModel
    @State private var visible = true
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            // Transparent hit target only — no dim/scrim over the video.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { toggleVisible() }

            if visible {
                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    centerTransport
                    Spacer()
                    bottomBar
                }
                .padding(12)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: visible)
        .onAppear { scheduleAutoHide() }
        .onChange(of: viewModel.isPlaying) { _, playing in
            if playing {
                scheduleAutoHide()
            } else {
                visible = true
                hideTask?.cancel()
            }
        }
        .onChange(of: viewModel.isSeeking) { _, seeking in
            if seeking {
                visible = true
                hideTask?.cancel()
            } else if viewModel.isPlaying {
                scheduleAutoHide()
            }
        }
    }

    private var topBar: some View {
        HStack {
            Text(viewModel.currentItem?.title ?? "Isshin")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.55), radius: 2, y: 1)
                .lineLimit(1)

            Spacer()

            Menu {
                ForEach(PlaybackRate.allCases) { rate in
                    Button {
                        viewModel.setRate(rate)
                        bumpInteraction()
                    } label: {
                        HStack {
                            Text(rate.label)
                            if abs(viewModel.playbackRate - rate.rawValue) < 0.01 {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Text(currentRateLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial.opacity(0.9))
                    .clipShape(Capsule())
            }

            Button {
                viewModel.startPiP()
                bumpInteraction()
            } label: {
                Image(systemName: viewModel.pipManager.isActive ? "pip.exit" : "pip.enter")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(.ultraThinMaterial.opacity(0.9))
                    .clipShape(Circle())
            }
            .opacity(viewModel.pipManager.isPossible || viewModel.pipManager.isActive ? 1 : 0.7)
        }
    }

    private var centerTransport: some View {
        HStack(spacing: 36) {
            Button {
                viewModel.playPrevious()
                bumpInteraction()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 20, weight: .semibold))
            }
            .disabled(!viewModel.hasPrevious && viewModel.currentTime <= 3)
            .opacity((!viewModel.hasPrevious && viewModel.currentTime <= 3) ? 0.35 : 1)

            Button {
                viewModel.togglePlayPause()
                bumpInteraction()
            } label: {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 28, weight: .bold))
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(.ultraThinMaterial))
                    .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
            }

            Button {
                viewModel.playNext()
                bumpInteraction()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 20, weight: .semibold))
            }
            .disabled(!viewModel.hasNext)
            .opacity(viewModel.hasNext ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            Slider(
                value: Binding(
                    get: { viewModel.currentTime },
                    set: { viewModel.updateSeekPreview($0) }
                ),
                in: 0...(max(viewModel.duration, 0.1)),
                onEditingChanged: { editing in
                    if editing {
                        viewModel.beginSeek()
                        bumpInteraction()
                    } else {
                        viewModel.endSeek(to: viewModel.currentTime)
                        bumpInteraction()
                    }
                }
            )
            .tint(Theme.brandBlue)

            HStack {
                Text(formatTime(viewModel.currentTime))
                Spacer()
                Text(formatTime(viewModel.duration))
            }
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.55), radius: 2, y: 1)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
    }

    private var currentRateLabel: String {
        PlaybackRate.allCases.first { abs($0.rawValue - viewModel.playbackRate) < 0.01 }?.label ?? "1x"
    }

    private func toggleVisible() {
        visible.toggle()
        if visible {
            scheduleAutoHide()
        } else {
            hideTask?.cancel()
        }
    }

    private func bumpInteraction() {
        visible = true
        scheduleAutoHide()
    }

    private func scheduleAutoHide() {
        hideTask?.cancel()
        guard viewModel.isPlaying else { return }
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, viewModel.isPlaying, !viewModel.isSeeking else { return }
            await MainActor.run { visible = false }
        }
    }

    private func formatTime(_ value: TimeInterval) -> String {
        guard value.isFinite, value >= 0 else { return "0:00" }
        let total = Int(value.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
