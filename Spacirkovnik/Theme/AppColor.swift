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
    static let textOnBeige = Color(rgb: 0x3D2314)
    static let textOnBeigeSecondary = Color(rgb: 0x6B4C35)

    /// Béžový podklad zoznamu špacírok — android `MainBackground`.
    static let mainBackground = LinearGradient(
        colors: [Color(rgb: 0xF0E9DF), Color(rgb: 0xE8D9C8), Color(rgb: 0xDDC9B4)],
        startPoint: .top,
        endPoint: .bottom
    )
}
