import Foundation

/// Откуда взялся активный режим — влияет только на формулировки в интерфейсе.
enum CaffeinateOrigin: String, Codable, Equatable {
    case toggle      // переключатель «Не давать Mac спать»
    case timer       // таймер на N минут
    case untilTime   // «До времени»
}

/// Активный режим. Один режим = один процесс `caffeinate -i -d`.
/// `endsAt == nil` — режим бессрочный (переключатель).
struct CaffeinateSession: Codable, Equatable {
    var origin: CaffeinateOrigin
    var startedAt: Date
    var endsAt: Date?

    /// Сколько секунд осталось: `nil` — бессрочный режим, `0` — время уже вышло.
    func remainingSeconds(at now: Date = Date()) -> Int? {
        guard let endsAt else { return nil }
        return max(0, Int(endsAt.timeIntervalSince(now).rounded(.up)))
    }
}

/// Команды, которые приложение принимает по URL-схеме (в том числе из виджета).
enum AppCommand {
    static let scheme = "magiccaffeinate"

    /// `magiccaffeinate://start?minutes=60` — запустить таймер на N минут.
    static func startURL(minutes: Int) -> URL {
        URL(string: "\(scheme)://start?minutes=\(minutes)")!
    }

    /// `magiccaffeinate://stop` — остановить активный режим.
    static func stopURL() -> URL {
        URL(string: "\(scheme)://stop")!
    }
}
