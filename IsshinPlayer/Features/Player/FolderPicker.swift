import UIKit
import UniformTypeIdentifiers

/// Pre-warms DocumentManager so the first file pick isn't a multi-hundred-ms stall.
enum FilesImportWarmup {
    private static var didWarm = false

    @MainActor
    static func warmUp() {
        guard !didWarm else { return }
        didWarm = true
        _ = UIDocumentPickerViewController(
            forOpeningContentTypes: [.audiovisualContent, .audio, .movie],
            asCopy: true
        )
    }
}
