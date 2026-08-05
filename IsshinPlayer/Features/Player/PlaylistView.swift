import SwiftUI

struct PlaylistView: View {
    @Bindable var viewModel: PlayerViewModel
    var onImport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("播放列表")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(viewModel.playlist.count)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)

                Button(action: onImport) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 28, height: 28)
                        .background(Theme.surfaceElevated)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Theme.border, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Spacer()

                Toggle(isOn: $viewModel.autoPlayNext) {
                    Text("自动连播")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                .toggleStyle(.switch)
                .labelsHidden()
                .scaleEffect(0.72)
                .padding(.trailing, -6)
                Text("自动连播")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }

            if viewModel.playlist.isEmpty {
                Text("暂无视频，点击 + 导入")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 10) {
                    ForEach(viewModel.playlist) { item in
                        let isCurrent = viewModel.currentItem?.id == item.id
                        Button {
                            viewModel.selectItem(id: item.id)
                        } label: {
                            PlaylistCard(item: item, isCurrent: isCurrent)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                viewModel.removeItem(id: item.id)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
    }
}

private struct PlaylistCard: View {
    let item: PlaylistItem
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isCurrent ? Theme.brandBlue.opacity(0.18) : Theme.surfaceElevated)
                    .frame(width: 40, height: 40)
                Image(systemName: isCurrent ? "video.fill" : "video")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isCurrent ? Theme.brandBlue : Theme.textTertiary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 14, weight: isCurrent ? .semibold : .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if let duration = item.duration {
                        Text(formatDuration(duration))
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(Theme.textSecondary)
                    }
                    if isCurrent {
                        Text("播放中")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.brandBlue)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Theme.brandBlue.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
            }

            Spacer(minLength: 0)

            Image(systemName: isCurrent ? "waveform" : "chevron.right")
                .font(.system(size: isCurrent ? 12 : 11, weight: .semibold))
                .foregroundStyle(isCurrent ? Theme.brandBlue : Theme.textTertiary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isCurrent ? Theme.brandBlue.opacity(0.08) : Theme.background.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    isCurrent ? Theme.brandBlue.opacity(0.55) : Theme.border,
                    lineWidth: isCurrent ? 1.2 : 1
                )
        )
        .shadow(color: isCurrent ? Theme.brandBlue.opacity(0.18) : .clear, radius: 10, y: 2)
    }

    private func formatDuration(_ value: TimeInterval) -> String {
        let total = Int(value.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
