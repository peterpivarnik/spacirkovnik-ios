import Foundation

/// Lokálna cache prijatých verzií per-game súhlasu, aby hráč, ktorý už súhlasil, nedostal
/// dialóg znova — offline alebo kým sa nedotiahne stav z Firebase. Autoritatívny záznam
/// žije vo Firebase (`consents/{uid}/{gameId}`), toto je len jeho odraz v zariadení.
/// Ekvivalent android `ConsentManager`.
///
/// Navyše si pamätá odmietnutie **nepovinného** súhlasu (`required: false`), aby sa hráča,
/// ktorý povedal nie, pri každom štarte špacírky nepýtalo znova. Pri novej verzii súhlasu
/// sa opýta znova.
struct ConsentStore {
    static let shared = ConsentStore()

    private let defaults = UserDefaults.standard

    private func key(_ gameId: String) -> String { "game_consent.\(gameId)" }
    private func declinedKey(_ gameId: String) -> String { "game_consent_declined.\(gameId)" }

    /// Najvyššia verzia súhlasu prijatá na tomto zariadení, alebo -1 ak žiadna.
    func acceptedVersion(gameId: String) -> Int {
        defaults.object(forKey: key(gameId)) as? Int ?? -1
    }

    func setAccepted(gameId: String, version: Int) {
        defaults.set(version, forKey: key(gameId))
    }

    /// Najvyššia verzia nepovinného súhlasu, ktorú hráč na tomto zariadení odmietol, alebo -1.
    func declinedVersion(gameId: String) -> Int {
        defaults.object(forKey: declinedKey(gameId)) as? Int ?? -1
    }

    func setDeclined(gameId: String, version: Int) {
        defaults.set(version, forKey: declinedKey(gameId))
    }
}
