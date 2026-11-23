import Foundation

/// Čo môže hráč so špacírkou spraviť — jediné miesto, kde sa rozhoduje o odomknutí.
/// Karta v zozname podľa toho len vyberie, čo ukáže (ikonu, tlačidlo, text).
/// Ekvivalent android `GameAccess`.
enum GameAccess {
    /// Hrá sa: hra je voľná, zadarmo po prihlásení (a hráč je prihlásený), kúpená alebo testovacia.
    case unlocked
    /// Zadarmo po prihlásení, hráč ešte nie je prihlásený.
    case freeAfterSignIn
    /// Platená hra a hráč nie je prihlásený — bez prihlásenia nevieme, či ju už nemá kúpenú.
    case signInToBuy
    /// Platená hra, hráč je prihlásený a ešte ju nemá.
    case buy
    /// Pripravujeme.
    case comingSoon
    /// Iný zamknutý stav (neznámy stav z katalógu).
    case locked

    var isUnlocked: Bool { self == .unlocked }

    /// Hráč ju môže získať hneď — kúpou alebo prihlásením.
    var isOffer: Bool { self == .freeAfterSignIn || self == .signInToBuy || self == .buy }

    var needsSignIn: Bool { self == .freeAfterSignIn || self == .signInToBuy }

    static func resolve(
        status: GameStatus?,
        isSignedIn: Bool,
        isActivated: Bool,
        isTestGame: Bool
    ) -> GameAccess {
        if status == .active || isActivated || isTestGame { return .unlocked }
        switch status {
        case .freeWithLogin: return isSignedIn ? .unlocked : .freeAfterSignIn
        case .purchasable: return isSignedIn ? .buy : .signInToBuy
        case .comingSoon: return .comingSoon
        default: return .locked
        }
    }
}
