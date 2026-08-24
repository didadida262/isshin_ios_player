import Photos
import SwiftUI
import UIKit

struct PlaylistView: View {
    @Bindable var viewModel: PlayerViewModel
    /// True while a picker is presenting. The system Files picker takes several hundred
    /// milliseconds to appear, so the button has to acknowledge the tap immediately.
    var isImportPickerPending: Bool = false
    var onImportFromPhotos: () -> Void
    var onImportFromFiles: () -> Void

    @State private var showImportSource = false
    @State private var showClearConfirm = false
    @State private var isBulkDeleteMode = false
    @State private var selectedDeleteIDs: Set<UUID> = []
    @State private var pendingDeleteItemID: UUID?
    @State private var openSwipeItemID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if viewModel.playlist.isEmpty {
                Text("暂无内容，点 + 导入")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.vertical, 8)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        // Rebuild the stack on mode change — LazyVStack reuse otherwise
                        // keeps stale swipe/checkbox cells after toggling bulk delete.
                        LazyVStack(spacing: 10) {
                            ForEach(viewModel.playlist) { item in
                                let isCurrent = viewModel.currentItem?.id == item.id
                                playlistRow(item: item, isCurrent: isCurrent, proxy: proxy)
                            }
                        }
                        .id(isBulkDeleteMode)
                    }
                    .scrollIndicators(.visible)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .onChange(of: viewModel.currentItem?.id) { _, newID in
                        guard let newID else { return }
                        scrollPlaylistItemToCenter(proxy: proxy, id: newID)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
        .confirmationDialog(
            "选择导入来源",
            isPresented: $showImportSource,
            titleVisibility: .visible
        ) {
            Button("照片") {
                onImportFromPhotos()
            }
            Button("文件") {
                onImportFromFiles()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("照片：导入相册中的视频\n文件：从最近项目或浏览中多选音视频")
        }
        .fullScreenCover(isPresented: deleteDialogPresented) {
            BlurConfirmDialog(
                title: deleteDialogTitle,
                message: deleteDialogMessage,
                confirmTitle: deleteDialogConfirmTitle,
                onConfirm: {
                    performPendingDelete()
                },
                onCancel: {
                    dismissDeleteDialog()
                }
            )
            .presentationBackground(.clear)
        }
    }

    private var deleteDialogPresented: Binding<Bool> {
        Binding(
            get: { pendingDeleteItemID != nil || showClearConfirm },
            set: { presented in
                if !presented {
                    dismissDeleteDialog()
                }
            }
        )
    }

    private var pendingBulkDeleteItems: [PlaylistItem] {
        viewModel.playlist.filter { selectedDeleteIDs.contains($0.id) }
    }

    private var deleteDialogTitle: String {
        if showClearConfirm {
            let items = pendingBulkDeleteItems
            if items.count == viewModel.playlist.count {
                return "彻底清空播放列表？"
            }
            return "彻底删除所选？"
        }
        return "彻底删除？"
    }

    private var deleteDialogMessage: String {
        if showClearConfirm {
            return bulkDeleteWarning
        }
        return permanentDeleteWarning(forItemID: pendingDeleteItemID)
    }

    private var deleteDialogConfirmTitle: String {
        if showClearConfirm {
            return pendingBulkDeleteItems.count == viewModel.playlist.count
                ? "彻底删除全部"
                : "彻底删除"
        }
        return "彻底删除"
    }

    private func performPendingDelete() {
        if showClearConfirm {
            openSwipeItemID = nil
            viewModel.removeItems(ids: selectedDeleteIDs)
            exitBulkDeleteMode()
            showClearConfirm = false
            return
        }
        if let id = pendingDeleteItemID {
            viewModel.removeItem(id: id)
        }
        pendingDeleteItemID = nil
    }

    private func dismissDeleteDialog() {
        pendingDeleteItemID = nil
        showClearConfirm = false
    }

    private func enterBulkDeleteMode() {
        openSwipeItemID = nil
        selectedDeleteIDs = Set(viewModel.playlist.map(\.id))
        isBulkDeleteMode = true
    }

    private func exitBulkDeleteMode() {
        isBulkDeleteMode = false
        selectedDeleteIDs = []
    }

    private func toggleDeleteSelection(for id: UUID) {
        if selectedDeleteIDs.contains(id) {
            selectedDeleteIDs.remove(id)
        } else {
            selectedDeleteIDs.insert(id)
        }
    }

    @ViewBuilder
    private func playlistRow(
        item: PlaylistItem,
        isCurrent: Bool,
        proxy: ScrollViewProxy
    ) -> some View {
        let isSelected = selectedDeleteIDs.contains(item.id)

        HStack(spacing: isBulkDeleteMode ? 10 : 0) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isSelected ? Theme.danger : Theme.textTertiary)
                .frame(width: isBulkDeleteMode ? 24 : 0, height: 24)
                .clipped()
                .opacity(isBulkDeleteMode ? 1 : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(!isBulkDeleteMode)

            if isBulkDeleteMode {
                Button {
                    toggleDeleteSelection(for: item.id)
                } label: {
                    PlaylistCard(item: item, isCurrent: isCurrent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityValue(isSelected ? "已选中" : "未选中")
                .accessibilityHint("双击切换选中状态")
            } else {
                SwipeToDeleteRow(
                    itemID: item.id,
                    openItemID: $openSwipeItemID,
                    onDelete: {
                        openSwipeItemID = nil
                        pendingDeleteItemID = item.id
                    },
                    onTap: {
                        openSwipeItemID = nil
                        viewModel.selectItem(id: item.id)
                        scrollPlaylistItemToCenter(proxy: proxy, id: item.id)
                    }
                ) {
                    PlaylistCard(item: item, isCurrent: isCurrent)
                }
            }
        }
    }

    private var bulkDeleteWarning: String {
        let items = pendingBulkDeleteItems
        let photoCount = items.filter { $0.assetIdentifier != nil }.count
        if photoCount > 0 {
            return "将永久删除选中的 \(items.count) 个文件（含 \(photoCount) 个相册原片），且不可恢复。"
        }
        return "将永久删除选中的 \(items.count) 个文件，且不可恢复。"
    }

    private func permanentDeleteWarning(forItemID id: UUID?) -> String {
        let fromPhotos = id.flatMap { itemID in
            viewModel.playlist.first(where: { $0.id == itemID })?.assetIdentifier
        } != nil
        if fromPhotos {
            return "将永久删除该文件，并从相册移除原片，且不可恢复。"
        }
        return "将永久删除该文件，且不可恢复。"
    }

    private func scrollPlaylistItemToCenter(proxy: ScrollViewProxy, id: UUID) {
        withAnimation(.easeInOut(duration: 0.28)) {
            proxy.scrollTo(id, anchor: .center)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Text(isBulkDeleteMode ? "选择删除" : "播放列表")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(
                    isBulkDeleteMode
                        ? "\(selectedDeleteIDs.count)/\(viewModel.playlist.count)"
                        : "\(viewModel.playlist.count)"
                )
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            }

            if !isBulkDeleteMode {
                Button {
                    showImportSource = true
                } label: {
                    ImportButtonFace(
                        systemImage: "plus",
                        isPending: isImportPickerPending
                    )
                }
                .buttonStyle(.plain)
                .disabled(isImportPickerPending)
                .accessibilityLabel("导入")
                .accessibilityHint("从照片或文件导入")
            }

            Spacer(minLength: 0)

            if isBulkDeleteMode {
                Button("取消") {
                    exitBulkDeleteMode()
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .buttonStyle(.plain)
                .accessibilityLabel("取消删除选择")

                Button("确定") {
                    guard !selectedDeleteIDs.isEmpty else { return }
                    showClearConfirm = true
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(selectedDeleteIDs.isEmpty ? Theme.textTertiary : Theme.danger)
                .buttonStyle(.plain)
                .disabled(selectedDeleteIDs.isEmpty)
                .accessibilityLabel("确认删除所选")
            } else {
                Button {
                    openSwipeItemID = nil
                    viewModel.sortPlaylistByTitle()
                } label: {
                    Image(systemName: "textformat")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(
                            viewModel.playlist.count < 2 ? Theme.textTertiary : Theme.textSecondary
                        )
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(viewModel.playlist.count < 2)
                .accessibilityLabel("按名称排序")
                .accessibilityHint("将播放列表按文件名称排序")

                Button {
                    enterBulkDeleteMode()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(
                            viewModel.playlist.isEmpty ? Theme.textTertiary : Theme.danger
                        )
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(viewModel.playlist.isEmpty)
                .accessibilityLabel("选择要删除的项目")

                Button {
                    openSwipeItemID = nil
                    viewModel.cyclePlaybackMode()
                } label: {
                    Image(systemName: viewModel.playbackMode.systemImage)
                        .font(.system(size: 17, weight: .regular))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(viewModel.playbackMode.title)
                .accessibilityHint("点击切换播放模式")
                .animation(.easeInOut(duration: 0.18), value: viewModel.playbackMode)
            }
        }
    }
}

private struct ImportButtonFace: View {
    let systemImage: String
    let isPending: Bool

    var body: some View {
        ZStack {
            if isPending {
                ProgressView()
                    .controlSize(.mini)
                    .tint(Theme.textSecondary)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .frame(width: 28, height: 28)
        .background(Theme.surfaceElevated)
        .clipShape(Circle())
        .overlay(Circle().stroke(Theme.border, lineWidth: 1))
    }
}

/// Original red circular delete control, revealed by swiping left.
/// Pan uses UIKit and only begins when the gesture is clearly horizontal,
/// so vertical ScrollView flings are never stolen.
private struct SwipeToDeleteRow<Content: View>: View {
    let itemID: UUID
    @Binding var openItemID: UUID?
    var onDelete: () -> Void
    var onTap: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var dragBase: CGFloat = 0
    @State private var isDragging = false

    private let revealWidth: CGFloat = 48
    private let buttonSize: CGFloat = 34
    private let threshold: CGFloat = 28

    private var isOpen: Bool { openItemID == itemID }

    private var progress: CGFloat {
        min(1, max(0, -offset / revealWidth))
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button {
                openItemID = nil
                onDelete()
            } label: {
                Image(systemName: "trash.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: buttonSize, height: buttonSize)
                    .background(Circle().fill(Color.red))
                    .shadow(color: Color.red.opacity(0.35 * progress), radius: 6, y: 1)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("彻底删除")
            .opacity(progress)
            .scaleEffect(0.72 + 0.28 * progress)
            .offset(x: (1 - progress) * 10)
            .padding(.trailing, 7)
            .allowsHitTesting(isOpen && progress > 0.85)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(
                    RowGestureView(
                        isOpen: isOpen,
                        onTap: {
                            if isOpen {
                                close()
                            } else {
                                onTap()
                            }
                        },
                        onSwipeBegan: {
                            isDragging = true
                            dragBase = offset
                            if openItemID != itemID {
                                openItemID = itemID
                            }
                        },
                        onSwipeChanged: { translationX in
                            offset = min(0, max(-revealWidth, dragBase + translationX))
                        },
                        onSwipeEnded: { translationX, velocityX in
                            isDragging = false
                            let projected = dragBase + translationX + velocityX * 0.18
                            let shouldOpen = projected < -threshold
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.78, blendDuration: 0.15)) {
                                if shouldOpen {
                                    offset = -revealWidth
                                    openItemID = itemID
                                } else {
                                    offset = 0
                                    if openItemID == itemID {
                                        openItemID = nil
                                    }
                                }
                            }
                        },
                        onVerticalDismiss: {
                            if openItemID != nil {
                                openItemID = nil
                            }
                        }
                    )
                )
                .offset(x: offset)
        }
        .frame(maxWidth: .infinity)
        .clipped()
        .onChange(of: openItemID) { _, newValue in
            guard !isDragging, newValue != itemID, offset != 0 else { return }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                offset = 0
            }
        }
    }

    private func close() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
            offset = 0
        }
        if openItemID == itemID {
            openItemID = nil
        }
    }
}

/// Transparent touch layer over a row. Handles the row tap plus a pan that only
/// begins on a clearly horizontal drag, leaving vertical pans to the enclosing
/// scroll view (a SwiftUI `DragGesture` here would swallow fast flings instead).
private struct RowGestureView: UIViewRepresentable {
    var isOpen: Bool
    var onTap: () -> Void
    var onSwipeBegan: () -> Void
    var onSwipeChanged: (_ translationX: CGFloat) -> Void
    var onSwipeEnded: (_ translationX: CGFloat, _ velocityX: CGFloat) -> Void
    var onVerticalDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        pan.delegate = context.coordinator
        pan.cancelsTouchesInView = false
        pan.delaysTouchesBegan = false
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap)
        )
        tap.delegate = context.coordinator
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: RowGestureView
        private var isPanning = false

        init(parent: RowGestureView) {
            self.parent = parent
        }

        @objc func handleTap() {
            parent.onTap()
        }

        @objc func handlePan(_ pan: UIPanGestureRecognizer) {
            let translation = pan.translation(in: pan.view).x
            let velocity = pan.velocity(in: pan.view).x

            switch pan.state {
            case .began:
                isPanning = true
                parent.onSwipeBegan()
                parent.onSwipeChanged(translation)
            case .changed:
                guard isPanning else { return }
                parent.onSwipeChanged(translation)
            case .ended, .cancelled, .failed:
                guard isPanning else { return }
                isPanning = false
                parent.onSwipeEnded(translation, velocity)
            default:
                break
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)

            guard abs(velocity.x) > abs(velocity.y) * 1.4 else {
                if abs(velocity.y) > abs(velocity.x) {
                    let dismiss = parent.onVerticalDismiss
                    DispatchQueue.main.async(execute: dismiss)
                }
                return false
            }
            // A closed row only opens on a left swipe; an open one also closes on a right swipe.
            return parent.isOpen || velocity.x < 0
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // The tap coexists with everything; the pan must win outright over scrolling.
            gestureRecognizer is UITapGestureRecognizer
        }
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
                Image(systemName: isCurrent ? item.mediaKind.listSystemImageFilled : item.mediaKind.listSystemImage)
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
                .fill(isCurrent ? Theme.brandBlue.opacity(0.16) : Theme.surfaceElevated)
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
