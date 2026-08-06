import Photos
import SwiftUI
import UIKit

struct VideoLibraryPickerView: View {
    let loadedIdentifiers: Set<String>
    var maxSelection: Int = 20
    var onCancel: () -> Void
    var onConfirm: ([PHAsset]) -> Void

    @State private var assets: [PHAsset] = []
    @State private var selectedIDs: Set<String> = []
    @State private var authorization: PHAuthorizationStatus = .notDetermined
    @State private var isLoadingLibrary = true

    private let columns = [
        GridItem(.flexible(), spacing: 3),
        GridItem(.flexible(), spacing: 3),
        GridItem(.flexible(), spacing: 3)
    ]

    var body: some View {
        NavigationStack {
            Group {
                switch authorization {
                case .authorized, .limited:
                    libraryContent
                case .denied, .restricted:
                    permissionDenied
                case .notDetermined:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                @unknown default:
                    permissionDenied
                }
            }
            .background(Theme.background)
            .navigationTitle("选择视频")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消", action: onCancel)
                        .foregroundStyle(Theme.textPrimary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: confirm) {
                        Image(uiImage: Self.pureWhiteCheckOnGreenImage())
                            .resizable()
                            .frame(width: 30, height: 30)
                    }
                    .disabled(selectedIDs.isEmpty)
                    .opacity(selectedIDs.isEmpty ? 0.45 : 1)
                    .accessibilityLabel("完成")
                }
            }
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .task {
            await requestAndLoad()
        }
    }

    private var libraryContent: some View {
        VStack(spacing: 0) {
            Text(selectedIDs.isEmpty ? "选择最多 \(maxSelection) 个视频" : "已选 \(selectedIDs.count) / \(maxSelection)")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)

            if isLoadingLibrary {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if assets.isEmpty {
                Text("相册中没有视频")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 3) {
                        ForEach(assets, id: \.localIdentifier) { asset in
                            let id = asset.localIdentifier
                            let loaded = loadedIdentifiers.contains(id)
                            let selected = selectedIDs.contains(id)
                            VideoAssetCell(
                                asset: asset,
                                isLoaded: loaded,
                                isSelected: selected
                            )
                            .aspectRatio(1, contentMode: .fit)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                toggle(asset)
                            }
                            .accessibilityAddTraits(loaded ? .isStaticText : .isButton)
                            .accessibilityLabel(loaded ? "已加载" : (selected ? "已选中" : "未选中"))
                        }
                    }
                    .padding(3)
                }
            }
        }
    }

    private var permissionDenied: some View {
        VStack(spacing: 12) {
            Text("需要相册权限才能导入视频")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Text("请在设置中允许访问照片")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
            Button("打开设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .foregroundStyle(Theme.brandBlue)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func toggle(_ asset: PHAsset) {
        let id = asset.localIdentifier
        guard !loadedIdentifiers.contains(id) else { return }
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            guard selectedIDs.count < maxSelection else { return }
            selectedIDs.insert(id)
        }
    }

    private func confirm() {
        let chosen = assets.filter { selectedIDs.contains($0.localIdentifier) }
        onConfirm(chosen)
    }

    private func requestAndLoad() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorization = status
        guard status == .authorized || status == .limited else {
            isLoadingLibrary = false
            return
        }
        await loadAssets()
    }

    private func loadAssets() async {
        isLoadingLibrary = true
        let result: [PHAsset] = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let options = PHFetchOptions()
                options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
                let fetch = PHAsset.fetchAssets(with: options)
                var list: [PHAsset] = []
                list.reserveCapacity(fetch.count)
                fetch.enumerateObjects { asset, _, _ in
                    list.append(asset)
                }
                continuation.resume(returning: list)
            }
        }
        assets = result
        // Drop any stale selection that is no longer available / already loaded.
        selectedIDs = selectedIDs
            .intersection(Set(result.map(\.localIdentifier)))
            .subtracting(loadedIdentifiers)
        isLoadingLibrary = false
    }

    private static func pureWhiteCheckOnGreenImage() -> UIImage {
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
    }
}

private struct VideoAssetCell: View {
    let asset: PHAsset
    let isLoaded: Bool
    let isSelected: Bool

    @State private var thumbnail: UIImage?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Group {
                    if let thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle().fill(Theme.surfaceElevated)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()

                if isLoaded {
                    Color.black.opacity(0.48)
                    VStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(Theme.selectionGreen)
                        Text("已加载")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .overlay(alignment: .bottomLeading) {
                Text(formatDuration(asset.duration))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .padding(6)
            }
            .overlay(alignment: .bottomTrailing) {
                if !isLoaded {
                    ZStack {
                        Circle()
                            .fill(isSelected ? Theme.selectionGreen : Color.black.opacity(0.28))
                            .frame(width: 24, height: 24)
                        Circle()
                            .strokeBorder(Color.white.opacity(0.95), lineWidth: 1.5)
                            .frame(width: 24, height: 24)
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(8)
                }
            }
        }
        .clipped()
        .task(id: asset.localIdentifier) {
            thumbnail = await Self.requestThumbnail(for: asset)
        }
    }

    private func formatDuration(_ value: TimeInterval) -> String {
        let total = max(0, Int(value.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private static func requestThumbnail(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true

            final class ResumeBox: @unchecked Sendable {
                var resumed = false
                let lock = NSLock()
                func finish(_ image: UIImage?, resume: (UIImage?) -> Void) {
                    lock.lock()
                    defer { lock.unlock() }
                    guard !resumed else { return }
                    resumed = true
                    resume(image)
                }
            }
            let box = ResumeBox()
            let target = CGSize(width: 300, height: 300)

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: target,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                if cancelled {
                    box.finish(nil) { continuation.resume(returning: $0) }
                    return
                }
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                // Prefer final image; if only degraded arrives and then nothing, keep it.
                if let image, !degraded {
                    box.finish(image) { continuation.resume(returning: $0) }
                } else if let image {
                    // Keep degraded as fallback; don't resume yet unless error/no more.
                    let error = info?[PHImageErrorKey] as? Error
                    if error != nil {
                        box.finish(image) { continuation.resume(returning: $0) }
                    } else {
                        // Resume with degraded so UI isn't blank; final may still improve.
                        box.finish(image) { continuation.resume(returning: $0) }
                    }
                } else {
                    box.finish(nil) { continuation.resume(returning: $0) }
                }
            }
        }
    }
}
