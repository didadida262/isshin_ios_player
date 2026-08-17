import Foundation

/// Holds security-scoped access for URLs returned by the system file picker
/// until the review sheet finishes importing or is cancelled.
@MainActor
final class SecurityScopedURLHold {
    private var started: [URL] = []

    func take(_ urls: [URL]) {
        release()
        for url in urls {
            if url.startAccessingSecurityScopedResource() {
                started.append(url)
            }
        }
    }

    func release() {
        for url in started {
            url.stopAccessingSecurityScopedResource()
        }
        started.removeAll()
    }
}
