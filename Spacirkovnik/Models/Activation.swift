import Foundation

/// Hodnota záznamu `activations/{uid}/{gameId}` v databáze. Platia dva tvary:
///  - `true` — starý tvar (nákupy pred zavedením typov, ručné aktivácie),
///  - `{ active: true, type: "purchase" | "prize", note: "..." }` — nový tvar; `note` je len
///    poznámka pre prevádzkovateľa (napr. „Výhra – Dni Petržalky 2026"), appka ju nečíta.
///
/// Vráti `true`, ak záznam hru odomyká. Čokoľvek iné (false, chýbajúce `active`, iný typ hodnoty)
/// hru neodomkne, ale ani nezhodí načítanie ostatných aktivácií. Ekvivalent android `isActivationActive`.
func isActivationActive(_ value: Any?) -> Bool {
    if let dict = value as? [String: Any] {
        return (dict["active"] as? Bool) == true
    }
    if let flag = value as? Bool {
        return flag
    }
    return false
}
