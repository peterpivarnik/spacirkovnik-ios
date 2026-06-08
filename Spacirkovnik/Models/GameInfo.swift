import Foundation

/// Stav hry v katalógu. Raw hodnoty zodpovedajú reťazcom vo Firebase `games-info.json`
/// (ekvivalent android `GameStatus` enumu so `@SerializedName`).
enum GameStatus: String, Codable {
    case active
    case comingSoon = "coming_soon"
    case purchasable
    case hidden
    case freeWithLogin = "free_with_login"
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = GameStatus(rawValue: raw) ?? .unknown
    }
}

/// Položka katalógu hier (`catalog/games-info.json`). Zhodné s android `GameInfo`.
struct GameInfo: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let description: String
    var imageUrl: String? = nil
    var colorHex: String? = nil
    var version: Int = 1
    var region: String? = nil
    var estimatedDurationMinutes: Int? = nil
    var distanceKm: Double? = nil
    var status: GameStatus? = nil
    var startName: String? = nil
    var endName: String? = nil
    var googlePlayProductId: String? = nil
    var consent: GameConsent? = nil

    enum CodingKeys: String, CodingKey {
        case id, title, description, imageUrl, colorHex, version, region
        case estimatedDurationMinutes, distanceKm, status, startName, endName
        case googlePlayProductId, consent
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        imageUrl = try c.decodeIfPresent(String.self, forKey: .imageUrl)
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        region = try c.decodeIfPresent(String.self, forKey: .region)
        estimatedDurationMinutes = try c.decodeIfPresent(Int.self, forKey: .estimatedDurationMinutes)
        distanceKm = try c.decodeIfPresent(Double.self, forKey: .distanceKm)
        status = try c.decodeIfPresent(GameStatus.self, forKey: .status)
        startName = try c.decodeIfPresent(String.self, forKey: .startName)
        endName = try c.decodeIfPresent(String.self, forKey: .endName)
        googlePlayProductId = try c.decodeIfPresent(String.self, forKey: .googlePlayProductId)
        consent = try c.decodeIfPresent(GameConsent.self, forKey: .consent)
    }
}
