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
