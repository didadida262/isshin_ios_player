import SwiftUI

/// Centered confirm card over a full-screen material blur.
struct BlurConfirmDialog: View {
    let title: String
    let message: String
    let confirmTitle: String
    var confirmRole: ConfirmRole = .destructive
    var onConfirm: () -> Void
    var onCancel: () -> Void

    enum ConfirmRole {
        case destructive
        case normal
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.28))
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)

                    Text(message)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 22)
                .padding(.top, 22)
                .padding(.bottom, 18)

                Rectangle()
                    .fill(Theme.border)
                    .frame(height: 1)

                HStack(spacing: 0) {
                    Button(action: onCancel) {
                        Text("取消")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Rectangle()
                        .fill(Theme.border)
                        .frame(width: 1)

                    Button(action: onConfirm) {
                        Text(confirmTitle)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(confirmRole == .destructive ? Theme.danger : Theme.brandBlue)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 300)
            .background(Theme.surfaceElevated.opacity(0.94))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.45), radius: 28, y: 12)
            .padding(.horizontal, 36)
        }
        .accessibilityAddTraits(.isModal)
    }
}
