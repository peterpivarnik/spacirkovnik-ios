import Foundation

/// Plná definícia hry (`games/{id}.json`). Zhodné s android `GameDefinition`.
struct GameDefinition: Codable, Identifiable {
    let id: String
    let title: String
    var version: Int = 1
    let screens: [GameScreen]

    enum CodingKeys: String, CodingKey {
        case id, title, version, screens
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        screens = try c.decode([GameScreen].self, forKey: .screens)
    }
}
