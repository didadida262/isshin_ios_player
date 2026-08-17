import SwiftUI
import UIKit

/// Step 2 of file import: review system-picked URLs, mark already-loaded, confirm.
struct FileImportReviewView: View {
    let viewModel: PlayerViewModel
    let urls: [URL]
    var onCancel: () -> Void
    var onConfirm: ([URL]) -> Void

    @State private var selectedPaths: Set<String> = []
    @State private var isImporting = false
    @State private var rows: [Row] = []

    private struct Row: Identifiable {
        let url: URL
        let name: String
        let byteCount: Int64?
        let mediaKind: MediaKind
        let isLoaded: Bool
        var id: String { url.standardizedFileURL.path }
    }

    private var loadedFingerprints: Set<String> {
        viewModel.loadedFileFingerprints
    }

    private var confirmableURLs: [URL] {
        rows.filter { !$0.isLoaded && selectedPaths.contains($0.id) }.map(\.url)
    }

    var body: some View {
        NavigationStack {
            Group {
                if rows.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    listContent
                }
            }
            .background(Theme.background)
            .navigationTitle("确认导入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消", action: cancel)
                        .foregroundStyle(Theme.textPrimary)
                        .disabled(isImporting)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: confirm) {
                        if isImporting {
                            ProgressView()
                                .frame(width: 30, height: 30)
                        } else {
                            Image(uiImage: Self.confirmCheckImage)
                                .resizable()
                                .frame(width: 30, height: 30)
                        }
                    }
                    .disabled(confirmableURLs.isEmpty || isImporting)
                    .opacity(confirmableURLs.isEmpty || isImporting ? 0.45 : 1)
                    .accessibilityLabel("完成")
                }
            }
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(isImporting)
        .task(id: urls.map(\.path).joined(separator: "\n")) {
            rebuildRows()
        }
    }

    private var listContent: some View {
        VStack(spacing: 0) {
            Text(headerText)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)

            List {
                ForEach(rows) { row in
                    rowView(row)
                        .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
                        .listRowSeparatorTint(Theme.border)
                        .listRowBackground(Theme.background)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .disabled(isImporting)
        }
    }

    private var headerText: String {
        if isImporting { return "正在导入…" }
        let loaded = rows.filter(\.isLoaded).count
        let selectable = rows.count - loaded
        if selectable == 0 {
            return "所选文件均已在播放列表中"
        }
        if loaded == 0 {
            return selectedPaths.isEmpty ? "点选要导入的文件" : "已选 \(selectedPaths.count) 个"
        }
        return "已选 \(selectedPaths.count) 个，\(loaded) 个已加载"
    }

    private func rowView(_ row: Row) -> some View {
        let selected = selectedPaths.contains(row.id)
        return Button {
            toggle(row)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: row.mediaKind == .audio ? "music.note" : "film")
                    .font(.system(size: 17))
                    .foregroundStyle(row.isLoaded ? Theme.textTertiary : Theme.textSecondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(row.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(row.isLoaded ? Theme.textTertiary : Theme.textPrimary)
                        .lineLimit(2)
                    if let bytes = row.byteCount {
                        Text(byteLabel(bytes))
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(Theme.textTertiary)
                    }
                }

                Spacer(minLength: 8)

                if row.isLoaded {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.selectionGreen)
                        Text("已加载")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.selectionGreen)
                    }
                } else {
                    ZStack {
                        Circle()
                            .fill(selected ? Theme.selectionGreen : Color.white.opacity(0.08))
                            .frame(width: 24, height: 24)
                        Circle()
                            .strokeBorder(Color.white.opacity(0.9), lineWidth: 1.5)
                            .frame(width: 24, height: 24)
                        if selected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .opacity(row.isLoaded ? 0.72 : 1)
        }
        .buttonStyle(.plain)
        .disabled(row.isLoaded)
        .accessibilityLabel(row.isLoaded ? "已加载" : (selected ? "已选中" : "未选中"))
    }

    private func rebuildRows() {
        let loaded = loadedFingerprints
        var next: [Row] = []
        var autoSelect: Set<String> = []
        next.reserveCapacity(urls.count)

        for url in urls {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .nameKey])
            let name = values?.name ?? url.lastPathComponent
            let size = values?.fileSize.map(Int64.init)
            let fingerprint = FileImportIdentity.fingerprint(forSourceURL: url)
            let isLoaded = fingerprint.map { loaded.contains($0) } ?? false
            let row = Row(
                url: url,
                name: name,
                byteCount: size,
                mediaKind: MediaKind.infer(from: url),
                isLoaded: isLoaded
            )
            next.append(row)
            if !isLoaded {
                autoSelect.insert(row.id)
            }
        }

        rows = next
        selectedPaths = autoSelect
    }

    private func toggle(_ row: Row) {
        guard !row.isLoaded else { return }
        if selectedPaths.contains(row.id) {
            selectedPaths.remove(row.id)
        } else {
            selectedPaths.insert(row.id)
        }
    }

    private func confirm() {
        let chosen = confirmableURLs
        guard !chosen.isEmpty, !isImporting else { return }
        isImporting = true
        onConfirm(chosen)
    }

    private func cancel() {
        onCancel()
    }

    private func byteLabel(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: bytes)
    }

    private static let confirmCheckImage: UIImage = {
        let side: CGFloat = 30
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        return renderer.image { _ in
            UIColor(Theme.selectionGreen).setFill()
            UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: side, height: side)).fill()
            let check = UIBezierPath()
            check.lineWidth = 2.8
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            UIColor.white.setStroke()
            check.move(to: CGPoint(x: side * 0.27, y: side * 0.52))
            check.addLine(to: CGPoint(x: side * 0.43, y: side * 0.67))
            check.addLine(to: CGPoint(x: side * 0.73, y: side * 0.33))
            check.stroke()
        }.withRenderingMode(.alwaysOriginal)
    }()
}
