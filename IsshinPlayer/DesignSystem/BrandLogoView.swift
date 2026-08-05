import SwiftUI

struct BrandLogoView: View {
    enum Size {
        case nav
        case hero

        var side: CGFloat {
            switch self {
            case .nav: return 40
            case .hero: return 148
            }
        }

        var corner: CGFloat {
            switch self {
            case .nav: return 10
            case .hero: return 28
            }
        }

        var glowRadius: CGFloat {
            switch self {
            case .nav: return 8
            case .hero: return 22
            }
        }

        var ringWidth: CGFloat {
            switch self {
            case .nav: return 1.2
            case .hero: return 1.5
            }
        }
    }

    var size: Size = .nav

    var body: some View {
        Image("IsshinLogo")
            .resizable()
            .scaledToFit()
            .frame(width: size.side, height: size.side)
            .clipShape(RoundedRectangle(cornerRadius: size.corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: size.corner, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Theme.brandBlue.opacity(0.95),
                                Theme.brandBlue.opacity(0.35),
                                Color.white.opacity(0.25)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: size.ringWidth
                    )
            )
            .shadow(color: Theme.brandBlue.opacity(0.55), radius: size.glowRadius, y: 0)
            .shadow(color: Theme.brandBlue.opacity(0.25), radius: size.glowRadius * 1.6, y: 2)
    }
}
