import SwiftUI

/// Visual stage for audio-only items (AVPlayer has no video track).
struct AudioStageView: View {
    let title: String
    let isPlaying: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Theme.surfaceElevated,
                    Theme.background,
                    Theme.brandBlue.opacity(0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Theme.brandBlue.opacity(0.12))
                        .frame(width: 108, height: 108)
                    Image(systemName: isPlaying ? "waveform" : "music.note")
                        .font(.system(size: isPlaying ? 36 : 40, weight: .semibold))
                        .foregroundStyle(Theme.brandBlue)
                        .symbolEffect(.variableColor, options: .repeating, isActive: isPlaying)
                }

                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
    }
}
