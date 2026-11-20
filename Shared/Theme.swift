import SwiftUI

// MARK: - Colour palette
// Dark, minimal, high-contrast.
// Green and red are reserved for Approve / Decline – never used for status or branding.

public struct Theme {
    // Surfaces
    public static let background   = Color(hex: "#0A0A0A")
    public static let surface      = Color(hex: "#1A1A1A")
    public static let surfaceHigh  = Color(hex: "#252525")

    // Text
    public static let textPrimary  = Color.white
    public static let textSecond   = Color(hex: "#A1A1AA")
    public static let textMuted    = Color(hex: "#52525B")

    // Approve / Decline – these two only
    public static let approve      = Color(hex: "#16A34A")
    public static let decline      = Color(hex: "#DC2626")

    // Status dots (not green/red)
    public static let idle         = Color(hex: "#52525B")
    public static let working      = Color(hex: "#F59E0B")
    public static let waiting      = Color(hex: "#6366F1")

    // Risk tints
    public static func riskColor(_ r: Risk) -> Color {
        switch r {
        case .low:    return Color(hex: "#6366F1")
        case .medium: return Color(hex: "#F59E0B")
        case .high:   return Color(hex: "#EF4444")
        }
    }

    // Provider accent
    public static func providerColor(_ p: Provider) -> Color {
        Color(hex: p.accentHex)
    }

    // Status dot colour (uses waiting colour for "working" state indicator dot)
    public static func statusColor(_ s: AgentStatus) -> Color {
        switch s {
        case .idle:    return idle
        case .working: return working
        case .waiting: return waiting
        }
    }
}

// MARK: - Hex initialiser

public extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let r, g, b: Double
        switch h.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255
            g = Double((int >>  8) & 0xFF) / 255
            b = Double( int        & 0xFF) / 255
        default:
            r = 0; g = 0; b = 0
        }
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - View helpers

public extension View {
    func cardStyle() -> some View {
        self
            .background(Theme.surface)
            .cornerRadius(12)
    }
}
