import Foundation

/// Voliteľný per-game súhlas zobrazený pred štartom hry (napr. zdieľanie e-mailu
/// s organizátorom podujatia). Autorovaný v katalógu, takže text sa dá meniť vo
/// Firebase bez novej verzie appky. Zhodné s android `GameConsent`.
///
/// Pri zmene znenia zvýš `version` — hráči, ktorí prijali staršiu verziu, budú
/// požiadaní o súhlas znova.
struct GameConsent: Codable, Hashable {
    var version: Int = 1
    var title: String? = nil
    var summary: String? = nil
    var organizer: String? = nil
    var url: String? = nil
    var required: Bool = true

    enum CodingKeys: String, CodingKey {
        case version, title, summary, organizer, url, required
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        title = try c.decodeIfPresent(String.self, forKey: .title)
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
        organizer = try c.decodeIfPresent(String.self, forKey: .organizer)
        url = try c.decodeIfPresent(String.self, forKey: .url)
        required = try c.decodeIfPresent(Bool.self, forKey: .required) ?? true
    }
}
