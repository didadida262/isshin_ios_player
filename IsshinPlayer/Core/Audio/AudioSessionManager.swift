import AVFoundation

enum AudioSessionManager {
    static func activatePlayback() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true)
        } catch {
            // Non-fatal: foreground video may still work
            print("AudioSession activate failed: \(error.localizedDescription)")
        }
    }
}
