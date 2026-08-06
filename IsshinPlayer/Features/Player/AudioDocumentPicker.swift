import UIKit
import UniformTypeIdentifiers

/// Pre-loads the Files picker machinery.
///
/// The first `.fileImporter` presentation lazily brings up DocumentManager and reads
/// several preference domains, which lands as main-thread work while the user is
/// waiting on their tap. Building one throwaway controller ahead of time costs ~4 ms
/// and measurably cuts that work; it must happen off the launch critical path.
enum AudioImportWarmup {
    private static var didWarm = false

    @MainActor
    static func warmUp() {
        guard !didWarm else { return }
        didWarm = true
        _ = UIDocumentPickerViewController(forOpeningContentTypes: [.audio], asCopy: true)
    }
}
