import Foundation

/// Čo ukáže obrazovka na konci špacírky. `durationMinutes` je nil, keď čas nedáva zmysel.
/// Ekvivalent android `FinishSummary`.
struct FinishSummary: Equatable {
    let title: String
    /// Úvodný obrázok špacírky (prvý obrázok v hre), alebo nil, ak žiadny nemá.
    let imageUrl: String?
    let stops: Int
    let questions: Int
    let durationMinutes: Int?

    /// Najdlhšia hra, ktorej čas ešte ukážeme; dlhší čas znamená prerušenie (napr. dohrané na druhý deň).
    static let maxShownDurationMinutes = 5 * 60

    init(title: String, screens: [GameScreen], startedAt: Date?, now: Date = Date()) {
        var minutes: Int?
        if let startedAt {
            let m = Int(now.timeIntervalSince(startedAt) / 60)
            if (1...Self.maxShownDurationMinutes).contains(m) { minutes = m }
        }
        self.title = title
        self.imageUrl = screens.lazy.compactMap { $0.imageUrl }.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        self.stops = screens.filter { $0.type == .navigation }.count
        self.questions = screens.filter { $0.type == .question }.count
        self.durationMinutes = minutes
    }
}

/// Slovenský tvar podľa počtu: 1 zastávka, 2–4 zastávky, 0 a 5+ zastávok.
func slovakPlural(_ count: Int, one: String, few: String, many: String) -> String {
    switch count {
    case 1: return one
    case 2...4: return few
    default: return many
    }
}

/// „45 min", „1 h", „1 h 25 min".
func formatDuration(minutes: Int) -> String {
    let h = minutes / 60
    let m = minutes % 60
    if h == 0 { return "\(m) min" }
    if m == 0 { return "\(h) h" }
    return "\(h) h \(m) min"
}
