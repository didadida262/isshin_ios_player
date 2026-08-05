import SwiftUI

enum Theme {
    static let background = Color(red: 0.04, green: 0.04, blue: 0.05) // near black
    static let surface = Color(red: 0.10, green: 0.10, blue: 0.11) // zinc-900-ish
    static let surfaceElevated = Color(red: 0.14, green: 0.14, blue: 0.16)
    static let border = Color.white.opacity(0.08)
    static let textPrimary = Color.white.opacity(0.92)
    static let textSecondary = Color.white.opacity(0.55)
    static let textTertiary = Color.white.opacity(0.35)
    static let accent = Color(red: 0.85, green: 0.85, blue: 0.87) // low-sat highlight
    static let brandBlue = Color(red: 0.15, green: 0.72, blue: 1.0) // neon cyan from logo
    static let selectionGreen = Color(red: 0.20, green: 0.78, blue: 0.35) // Photos-style check
    static let danger = Color(red: 0.75, green: 0.35, blue: 0.35)
    static let skeleton = Color.white.opacity(0.06)
}
