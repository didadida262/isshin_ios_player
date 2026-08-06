import AVFoundation

/// Owns the shared `AVAudioSession`.
///
/// `setCategory` / `setActive` are synchronous IPC to mediaserverd and measured
/// 60–170 ms on the main thread, so the session is configured exactly once and
/// activation is only re-attempted after something actually deactivated it.
@MainActor
enum AudioSessionManager {
    private static var isActive = false

    /// Cheap and idempotent. Safe to call on every playback start.
    static func activatePlayback() {
        guard !isActive else { return }
        isActive = true
        applyOffMainThread()
    }

    /// Call when the session was torn down by the system (interruption, route loss).
    static func invalidate() {
        isActive = false
    }

    private static func applyOffMainThread() {
        Task.detached(priority: .userInitiated) {
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(.playback, mode: .moviePlayback, options: [])
                try session.setActive(true)
            } catch {
                // Non-fatal: foreground video may still work. Allow a later retry.
                print("AudioSession activate failed: \(error.localizedDescription)")
                await MainActor.run { isActive = false }
            }
        }
    }
}
