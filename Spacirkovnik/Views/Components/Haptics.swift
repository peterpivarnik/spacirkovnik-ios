import UIKit

/// Krátke vibrácie počas hry. Hráč má telefón často v ruke alebo vo vrecku a díva sa okolo seba —
/// vibrácia mu povie „si na mieste" alebo „správne" bez pozerania na displej.
/// Ekvivalent android `Haptics`. Zariadenie bez vibrácie (iPad) jednoducho nič neurobí.
@MainActor
enum Haptics {
    /// Hráč došiel k cieľu.
    static func arrived() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Správna odpoveď.
    static func correct() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// Zlá odpoveď.
    static func wrong() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
