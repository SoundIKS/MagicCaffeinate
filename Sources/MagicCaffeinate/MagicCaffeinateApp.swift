import AppKit
import Carbon

/// Точка входа приложения (AppKit, без SwiftUI — CLT не содержит плагин SwiftUIMacros).
///
/// NSApplication поднимается вручную и получает делегата: статус-бар приложению
/// не нужны ни main-menu, ни nib, ни окно.
@main
final class MagicCaffeinateApp: NSObject, NSApplicationDelegate {

    static func main() {
        let app = NSApplication.shared
        let delegate = MagicCaffeinateApp()
        app.delegate = delegate
        app.run()
    }

    private var controller: StatusMenuController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Страховка: даже если Info.plist с LSUIElement не применился — не показываемся в Dock.
        NSApp.setActivationPolicy(.accessory)

        controller = StatusMenuController()

        // В файле общего состояния мог остаться «активный» статус от аварийно
        // завершившегося запуска — публикуем правду.
        CaffeinateManager.shared.syncSharedState()

        // URL-схема magiccaffeinate://… — так виджет запускает таймер на час.
        // Обработчик AppleEvent'а надёжнее, чем application(_:open:): событие
        // приходит и сразу после запуска приложения по ссылке.
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Обязательно снимаем assertion'ы, иначе caffeinate переживёт приложение.
        CaffeinateManager.shared.terminateAll()
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: string) else { return }
        handle(url)
    }

    /// `magiccaffeinate://start?minutes=60` — таймер; `magiccaffeinate://stop` — стоп.
    /// Без `minutes` таймер запускается на час (так его дергает виджет).
    private func handle(_ url: URL) {
        guard url.scheme?.lowercased() == AppCommand.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }

        let minutes = components.queryItems?
            .first { $0.name == "minutes" }?
            .value
            .flatMap(Int.init)

        switch url.host?.lowercased() {
        case "start":
            CaffeinateManager.shared.startTimer(minutes: minutes ?? 60)
        case "stop":
            CaffeinateManager.shared.stop()
        default:
            break
        }
    }
}
