import Foundation

/// Состояние, которое приложение отдаёт наружу — в первую очередь будущему
/// WidgetKit extension'у. Формат — обычный JSON, одинаковый для чтения и записи.
struct SharedStatus: Codable, Equatable {
    var isActive: Bool
    var origin: CaffeinateOrigin?
    var startedAt: Date?
    var endsAt: Date?

    init(session: CaffeinateSession?) {
        isActive = session != nil
        origin = session?.origin
        startedAt = session?.startedAt
        endsAt = session?.endsAt
    }

    /// Остаток секунд; `nil` — не активно или бессрочный режим.
    func remainingSeconds(at now: Date = Date()) -> Int? {
        guard isActive, let endsAt else { return nil }
        return max(0, Int(endsAt.timeIntervalSince(now).rounded(.up)))
    }
}

/// Хранилище общего состояния.
///
/// Пишем сразу во все доступные места:
/// 1. контейнер App Group — его увидит виджет, но он существует только при подписи
///    с entitlements `com.apple.security.application-groups` (с team ID);
/// 2. `~/Library/Application Support/MagicCaffeinate/status.json` — запасной путь
///    для локальной сборки без App Group: приложение и ручная проверка его видят,
///    sandbox'ed виджет — нет.
enum SharedState {

    static let appGroupID = "group.local.magiccaffeinate"
    static let fileName = "status.json"

    /// Контейнер App Group. Без подписи с нужными entitlements возвращает `nil`.
    static var groupContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    /// Запасной путь для сборки без App Group.
    static var fallbackURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MagicCaffeinate", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    static func save(_ status: SharedStatus) {
        guard let data = try? encoder.encode(status) else { return }
        for url in destinationURLs() {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? data.write(to: url, options: .atomic)
        }
    }

    static func load() -> SharedStatus? {
        for url in destinationURLs() {
            guard let data = try? Data(contentsOf: url) else { continue }
            if let status = try? decoder.decode(SharedStatus.self, from: data) {
                return status
            }
        }
        return nil
    }

    private static func destinationURLs() -> [URL] {
        var urls: [URL] = []
        if let container = groupContainerURL {
            urls.append(container.appendingPathComponent(fileName))
        }
        urls.append(fallbackURL)
        return urls
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
