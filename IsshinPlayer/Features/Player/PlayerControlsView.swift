import SwiftUI

struct PlayerControlsView: View {
    @Bindable var viewModel: PlayerViewModel

    var body: some View {
        VStack(spacing: 14) {
            progressRow
            buttonRow
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    private var progressRow: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { viewModel.currentTime },
                    set: { viewModel.updateSeekPreview($0) }
                ),
                in: 0...(max(viewModel.duration, 0.1)),
                onEditingChanged: { editing in
                    if editing {
                        viewModel.beginSeek()
                    } else {
                        viewModel.endSeek(to: viewModel.currentTime)
                    }
                }
            )
            .tint(Theme.accent)
            .disabled(viewModel.duration <= 0 || viewModel.phase != .ready)

            HStack {
                Text(formatTime(viewModel.currentTime))
                Spacer()
                Text(formatTime(viewModel.duration))
            }
            .font(.system(size: 12, weight: .medium).monospacedDigit())
            .foregroundStyle(Theme.textSecondary)
        }
    }

    private var buttonRow: some View {
        HStack(spacing: 18) {
            Button {
                viewModel.playPrevious()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 16))
            }
            .disabled(!viewModel.hasPrevious && viewModel.currentTime <= 3)
            .opacity((!viewModel.hasPrevious && viewModel.currentTime <= 3) ? 0.35 : 1)

            Button {
                viewModel.togglePlayPause()
            } label: {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 22))
                    .frame(width: 44, height: 44)
                    .background(Theme.surfaceElevated)
                    .clipShape(Circle())
            }
            .disabled(viewModel.phase != .ready)

            Button {
                viewModel.playNext()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 16))
            }
            .disabled(!viewModel.hasNext)
            .opacity(viewModel.hasNext ? 1 : 0.35)

            Spacer()

            Menu {
                ForEach(PlaybackRate.allCases) { rate in
                    Button {
                        viewModel.setRate(rate)
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
                Label(currentRateLabel, systemImage: "gauge.with.dots.needle.33percent")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Theme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Button {
                viewModel.startPiP()
            } label: {
                Image(systemName: viewModel.pipManager.isActive ? "pip.exit" : "pip.enter")
                    .font(.system(size: 15, weight: .medium))
                    .padding(8)
                    .background(Theme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .disabled(!viewModel.pipManager.isPossible && !viewModel.pipManager.isActive)
            .opacity((viewModel.pipManager.isPossible || viewModel.pipManager.isActive) ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.textPrimary)
    }

    private var currentRateLabel: String {
        PlaybackRate.allCases.first { abs($0.rawValue - viewModel.playbackRate) < 0.01 }?.label ?? "1x"
    }

    private func formatTime(_ value: TimeInterval) -> String {
        guard value.isFinite, value >= 0 else { return "0:00" }
        let total = Int(value.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
