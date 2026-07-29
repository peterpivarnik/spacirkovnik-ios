import SwiftUI

/// Paleta appky — port android `ui/theme/Color.kt`, aby obe verzie vyzerali rovnako.
///
/// Farby sú natvrdo svetlé, rovnako ako na Androide. Hárky a dialógy si ich preto
/// vynucujú aj cez `.environment(\.colorScheme, .light)` — bez toho by v systémovom
/// tmavom režime prišlo pozadie z témy a tmavé texty by na ňom zmizli.
enum AppColor {
    static let amber = Color(rgb: 0xD4933E)
    static let cardBg = Color(rgb: 0xFAF6F1)
    static let textDark = Color(rgb: 0x1C2B25)
    static let textMedium = Color(rgb: 0x4A635A)
    static let primaryButton = Color(rgb: 0xC9761B)       // primárne tlačidlo (Prejsť, Prihlásiť…)
    static let primaryButtonText = Color.white
    static let purchaseButton = Color(rgb: 0x4E8E7A)      // kúpa a „ZADARMO" štítok
    static let secondaryButton = Color(rgb: 0x3A6B5A)     // kvízové odpovede v špacírke
    static let backButton = Color.white.opacity(0.25)     // tlačidlo „Späť" na tmavom podklade
    static let disabledButton = Color.white.opacity(0.19)
    static let textOnBeige = Color(rgb: 0x3D2314)
    static let textOnBeigeSecondary = Color(rgb: 0x6B4C35)

    static let textOnDark = Color(rgb: 0xF5F9F7)

    /// Béžový podklad zoznamu špacírok — android `MainBackground`.
    static let mainBackground = LinearGradient(
        colors: [Color(rgb: 0xF0E9DF), Color(rgb: 0xE8D9C8), Color(rgb: 0xDDC9B4)],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Tmavý podklad počas špacírky — android `GameBackground`.
    static let gameBackground = LinearGradient(
        colors: [
            Color(rgb: 0x1C3A2E), Color(rgb: 0x2D4A3E),
            Color(rgb: 0x3A6B5A), Color(rgb: 0x4E8E7A)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Podklad odvodený od farby špacírky (`colorHex` z katalógu) — android `gameGradient`.
    static func gameGradient(colorHex: String?) -> LinearGradient {
        guard let c = Color.rgbComponents(hex: colorHex) else { return gameBackground }
        return LinearGradient(
            colors: [
                Color(red: c.r * 0.7, green: c.g * 0.7, blue: c.b * 0.7),
                Color(red: c.r * 0.85, green: c.g * 0.85, blue: c.b * 0.85),
                Color(red: c.r, green: c.g, blue: c.b)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
