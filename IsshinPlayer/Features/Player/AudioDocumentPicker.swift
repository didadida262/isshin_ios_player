import ObjectiveC
import UniformTypeIdentifiers
import UIKit

/// Presents the system Files picker from the key window — never from a Menu / dialog VC
/// (those dismiss and would cancel the picker with them).
enum AudioImportPresenter {
    @MainActor
    static func present(onPick: @escaping ([URL]) -> Void) {
        guard let root = keyWindowRootViewController() else {
            print("AudioImportPresenter: no root VC")
            return
        }

        // Always present from the stable root (or its already-visible top that is NOT mid-dismiss).
        let host = topStableViewController(from: root)

        var types: [UTType] = [.audio, .mp3, .mpeg4Audio, .wav, .aiff]
        if let flac = UTType(filenameExtension: "flac") { types.append(flac) }
        if let caf = UTType(filenameExtension: "caf") { types.append(caf) }
        if let m4a = UTType(filenameExtension: "m4a") { types.append(m4a) }

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = true
        picker.modalPresentationStyle = .formSheet

        let delegate = Delegate(onPick: onPick)
        objc_setAssociatedObject(
            picker,
            &Delegate.assocKey,
            delegate,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        picker.delegate = delegate

        if host.presentedViewController != nil {
            // Something still covering (e.g. Menu animation) — dismiss then present.
            host.dismiss(animated: false) {
                host.present(picker, animated: true)
            }
        } else {
            host.present(picker, animated: true)
        }
    }

    @MainActor
    private static func keyWindowRootViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow)
            ?? scenes.first?.windows.first
        return window?.rootViewController
    }

    @MainActor
    private static func topStableViewController(from base: UIViewController) -> UIViewController {
        if let nav = base as? UINavigationController {
            return topStableViewController(from: nav.visibleViewController ?? nav)
        }
        if let tab = base as? UITabBarController {
            return topStableViewController(from: tab.selectedViewController ?? tab)
        }
        // Do not walk into transient presented controllers (SwiftUI Menu / popover).
        // Presenting from root avoids the picker being dismissed with the Menu.
        return base
    }

    private final class Delegate: NSObject, UIDocumentPickerDelegate {
        static var assocKey: UInt8 = 0
        let onPick: ([URL]) -> Void

        init(onPick: @escaping ([URL]) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
    }
}
