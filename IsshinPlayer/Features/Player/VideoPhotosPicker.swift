import PhotosUI
import SwiftUI
import UIKit

struct VideoPhotosPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var maxSelectionCount: Int = 20
    var onPicked: ([PHPickerResult]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> PresenterViewController {
        let controller = PresenterViewController()
        controller.coordinator = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: PresenterViewController, context: Context) {
        context.coordinator.parent = self
        uiViewController.coordinator = context.coordinator
        if isPresented {
            uiViewController.presentPickerIfNeeded()
        }
    }

    final class PresenterViewController: UIViewController {
        weak var coordinator: Coordinator?

        func presentPickerIfNeeded() {
            guard presentedViewController == nil else { return }
            coordinator?.present(from: self)
        }
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        var parent: VideoPhotosPicker

        init(parent: VideoPhotosPicker) {
            self.parent = parent
        }

        func present(from host: UIViewController) {
            var configuration = PHPickerConfiguration(photoLibrary: .shared())
            configuration.filter = .videos
            configuration.selectionLimit = parent.maxSelectionCount
            configuration.preferredAssetRepresentationMode = .current

            let picker = PHPickerViewController(configuration: configuration)
            picker.delegate = self
            host.present(picker, animated: true) { [weak self, weak picker] in
                guard let self, let picker else { return }
                self.styleDoneButton(in: picker.view)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    self.styleDoneButton(in: picker.view)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    self.styleDoneButton(in: picker.view)
                }
            }
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.isPresented = false
            picker.dismiss(animated: true) {
                if !results.isEmpty {
                    self.parent.onPicked(results)
                }
            }
        }

        private func styleDoneButton(in root: UIView) {
            var queue: [UIView] = [root]
            while let view = queue.first {
                queue.removeFirst()
                queue.append(contentsOf: view.subviews)
                if let button = view as? UIButton {
                    restyleConfirmButton(button)
                }
            }

            if let nav = closestNavigationController(from: root) {
                nav.navigationBar.tintColor = UIColor(Theme.selectionGreen)
                if let item = nav.topViewController?.navigationItem.rightBarButtonItem {
                    item.image = Self.whiteCheckOnGreenImage()
                    item.tintColor = nil
                }
            }
        }

        private func restyleConfirmButton(_ button: UIButton) {
            let label = button.accessibilityLabel?.lowercased() ?? ""
            let imageDesc = button.configuration?.image?.description.lowercased()
                ?? button.image(for: .normal)?.description.lowercased()
                ?? ""

            let looksLikeConfirm =
                imageDesc.contains("check")
                || label.contains("完成")
                || label.contains("done")
                || label.contains("add")

            guard looksLikeConfirm else { return }

            var config = UIButton.Configuration.filled()
            config.image = UIImage(
                systemName: "checkmark",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)
            )
            config.baseForegroundColor = .white
            config.baseBackgroundColor = UIColor(Theme.selectionGreen)
            config.cornerStyle = .capsule
            config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
            button.configuration = config
            button.tintColor = .white
        }

        private func closestNavigationController(from view: UIView) -> UINavigationController? {
            var responder: UIResponder? = view
            while let current = responder {
                if let nav = current as? UINavigationController { return nav }
                if let vc = current as? UIViewController, let nav = vc.navigationController { return nav }
                responder = current.next
            }
            return nil
        }

        private static func whiteCheckOnGreenImage() -> UIImage {
            let side: CGFloat = 30
            let size = CGSize(width: side, height: side)
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { _ in
                UIColor(Theme.selectionGreen).setFill()
                UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()

                let symbol = UIImage(
                    systemName: "checkmark",
                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)
                )?
                .withTintColor(.white, renderingMode: .alwaysOriginal)

                if let symbol {
                    symbol.draw(
                        at: CGPoint(
                            x: (side - symbol.size.width) / 2,
                            y: (side - symbol.size.height) / 2
                        )
                    )
                }
            }.withRenderingMode(.alwaysOriginal)
        }
    }
}
