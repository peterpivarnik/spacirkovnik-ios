import Foundation
import CoreLocation

/// Typ obrazovky v hre. Raw hodnoty zodpovedajú JSON (ekvivalent android `ScreenType`).
enum ScreenType: String, Codable {
    case `continue` = "CONTINUE"
    case browse = "BROWSE"
    case question = "QUESTION"
    case navigation = "NAVIGATION"
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ScreenType(rawValue: raw) ?? .unknown
    }
}

/// Jedna obrazovka hry. Zhodné s android `GameScreen`.
///
/// `directRoute` sa týka len obrazoviek typu NAVIGATION: predvolene sa kreslí skutočná trasa
/// po chodníkoch, s `true` sa kreslí priamka od hráča k cieľu. Hodí sa tam, kde chodníky
/// v mapových podkladoch nie sú alebo vedú okľukou — napríklad na dostihovej dráhe.
struct GameScreen: Codable {
    var text: String? = nil
    var type: ScreenType? = nil
    var buttonText: String? = nil
    var backButtonText: String? = nil
    var nextButtonText: String? = nil
    var fontSize: Int? = nil
    var answers: [GameAnswer]? = nil
    var targetLatitude: Double? = nil
    var targetLongitude: Double? = nil
    var imageUrl: String? = nil
    var directRoute: Bool = false

    enum CodingKeys: String, CodingKey {
        case text, type, buttonText, backButtonText, nextButtonText, fontSize
        case answers, targetLatitude, targetLongitude, imageUrl, directRoute
    }

    // Vlastné dekódovanie, lebo Swift pri chýbajúcom kľúči nepoužije default hodnotu
    // property — staršie hry bez `directRoute` by inak prestali ísť načítať.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decodeIfPresent(String.self, forKey: .text)
        type = try c.decodeIfPresent(ScreenType.self, forKey: .type)
        buttonText = try c.decodeIfPresent(String.self, forKey: .buttonText)
        backButtonText = try c.decodeIfPresent(String.self, forKey: .backButtonText)
        nextButtonText = try c.decodeIfPresent(String.self, forKey: .nextButtonText)
        fontSize = try c.decodeIfPresent(Int.self, forKey: .fontSize)
        answers = try c.decodeIfPresent([GameAnswer].self, forKey: .answers)
        targetLatitude = try c.decodeIfPresent(Double.self, forKey: .targetLatitude)
        targetLongitude = try c.decodeIfPresent(Double.self, forKey: .targetLongitude)
        imageUrl = try c.decodeIfPresent(String.self, forKey: .imageUrl)
        directRoute = try c.decodeIfPresent(Bool.self, forKey: .directRoute) ?? false
    }

    /// GPS cieľ pre NAVIGATION obrazovky, ak je definovaný.
    var targetCoordinate: CLLocationCoordinate2D? {
        guard let lat = targetLatitude, let lon = targetLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

/// Odpoveď na kvízovú otázku. Zhodné s android `GameAnswer`.
struct GameAnswer: Codable, Hashable {
    let text: String
    let correct: Bool
}
