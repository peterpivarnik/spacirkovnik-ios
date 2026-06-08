import Foundation

/// Rod hráča pre rodovo citlivé texty. Zhodné s android `Gender`.
enum Gender: String, Codable, CaseIterable {
    case male = "MALE"
    case female = "FEMALE"

    var displayName: String {
        switch self {
        case .male: return "Chlapec / muž"
        case .female: return "Dievča / žena"
        }
    }
}

extension String {
    /// Nahradí rodové placeholdery `{mužský|ženský}` podľa zvoleného rodu.
    /// Ekvivalent android `String.applyGender`.
    func applyGender(_ gender: Gender) -> String {
        guard let regex = try? NSRegularExpression(pattern: "\\{([^|{}]*)\\|([^|{}]+)\\}") else {
            return self
        }
        let ns = self as NSString
        var result = self
        let matches = regex.matches(in: self, range: NSRange(location: 0, length: ns.length))
        // Nahrádzame od konca, aby sa neposúvali rozsahy.
        for match in matches.reversed() {
            let maleRange = match.range(at: 1)
            let femaleRange = match.range(at: 2)
            let replacement = gender == .male
                ? ns.substring(with: maleRange)
                : ns.substring(with: femaleRange)
            let full = match.range(at: 0)
            result = (result as NSString).replacingCharacters(in: full, with: replacement)
        }
        return result
    }
}
