import SwiftUI

struct PlaylistView: View {
    @Bindable var viewModel: PlayerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("播放列表")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Toggle(isOn: $viewModel.autoPlayNext) {
                    Text("自动连播")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                .toggleStyle(.switch)
                .labelsHidden()
                Text("自动连播")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }

            if viewModel.playlist.isEmpty {
                Text("暂无视频，点击右上角导入")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                List {
                    ForEach(viewModel.playlist) { item in
                        Button {
                            viewModel.selectItem(id: item.id)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: viewModel.currentItem?.id == item.id ? "waveform" : "film")
                                    .font(.system(size: 14))
                                    .foregroundStyle(
                                        viewModel.currentItem?.id == item.id
                                        ? Theme.accent
                                        : Theme.textTertiary
                                    )
                                    .frame(width: 20)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(Theme.textPrimary)
                                        .lineLimit(1)
                                    if let duration = item.duration {
                                        Text(formatDuration(duration))
                                            .font(.system(size: 11).monospacedDigit())
                                            .foregroundStyle(Theme.textSecondary)
                                    }
                                }
                                Spacer()
                                if viewModel.currentItem?.id == item.id {
                                    Text("播放中")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowBackground(
                            viewModel.currentItem?.id == item.id
                            ? Theme.surfaceElevated
                            : Theme.surface
                        )
                        .listRowSeparatorTint(Theme.border)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            let id = viewModel.playlist[index].id
                            viewModel.removeItem(id: id)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 120, maxHeight: 260)
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

    private func formatDuration(_ value: TimeInterval) -> String {
        let total = Int(value.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
