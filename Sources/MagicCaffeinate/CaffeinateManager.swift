import AppKit
import Foundation
import Observation

/// Обёртка над `/usr/bin/caffeinate -i -d`: одновременно живёт не больше одного процесса.
///
/// Класс не изолирован к главному актору намеренно: все команды приходят с главного потока
/// (меню/панель/Timer на main runloop), а terminationHandler перебрасывается на главный
/// поток через DispatchQueue.main.
@Observable
final class CaffeinateManager {

    static let shared = CaffeinateManager()

    private init() {}

    // MARK: - Наблюдаемое состояние

    /// Активный режим; `nil` — ничего не держим.
    private(set) var session: CaffeinateSession?

    var isActive: Bool { session != nil }

    /// Остаток секунд: `nil` — не активно или бессрочный режим.
    var remainingSeconds: Int? { session?.remainingSeconds() }

    // MARK: - Процесс

    private var process: Process?
    private let caffeinatePath = "/usr/bin/caffeinate"

    // MARK: - Управление

    /// Бессрочный режим: включён, пока не выключишь.
    func startIndefinitely() {
        start(CaffeinateSession(origin: .toggle, startedAt: Date(), endsAt: nil))
    }

    /// Таймер на N минут: `caffeinate -i -d -t N*60`.
    func startTimer(minutes: Int) {
        guard minutes > 0 else { return }
        let now = Date()
        start(CaffeinateSession(
            origin: .timer,
            startedAt: now,
            endsAt: now.addingTimeInterval(TimeInterval(minutes * 60))
        ))
    }

    /// «Бодрствовать до» указанного момента.
    func startUntil(_ date: Date) {
        guard date.timeIntervalSinceNow > 0 else { return }
        start(CaffeinateSession(origin: .untilTime, startedAt: Date(), endsAt: date))
    }

    /// Переключатель: включить бессрочный режим или выключить текущий.
    func toggle() {
        if isActive {
            stop()
        } else {
            startIndefinitely()
        }
    }

    func stop() {
        guard process != nil || session != nil else { return }
        stopProcess()
        session = nil
        publish()
    }

    private func start(_ newSession: CaffeinateSession) {
        stopProcess() // одновременно держим только один caffeinate

        var arguments = ["-i", "-d"]
        if let seconds = newSession.remainingSeconds(), seconds > 0 {
            arguments += ["-t", String(seconds)]
        }

        let child = Process()
        child.executableURL = URL(fileURLWithPath: caffeinatePath)
        child.arguments = arguments
        child.terminationHandler = { [weak self] finished in
            // Вызывается не на главном потоке — переключаемся.
            DispatchQueue.main.async { self?.handleSelfExit(finished) }
        }

        do {
            try child.run()
        } catch {
            // Запустить не удалось — состояние не меняем, но снаружи показываем правду.
            publish()
            return
        }

        process = child
        session = newSession
        publish()
    }

    /// Завершает дочерний процесс, не трогая опубликованное состояние.
    /// SIGTERM: caffeinate сам снимает свои assertion'ы.
    private func stopProcess() {
        guard let child = process else { return }
        process = nil
        child.terminationHandler = nil // не даём handler'у чистить состояние дважды
        child.terminate()
    }

    /// caffeinate вышел сам: истёк `-t` или процесс упал.
    private func handleSelfExit(_ finished: Process) {
        guard process === finished else { return } // уже остановлен вручную
        process = nil
        session = nil
        publish()
    }

    // MARK: - Выход приложения

    /// Снимает assertion'ы при выходе: шлёт SIGTERM дочернему процессу и ждёт его.
    /// Иначе caffeinate переживёт родителя, «репарнется» к launchd и Mac останется
    /// бодрым после выхода из приложения.
    func terminateAll() {
        if let child = process {
            process = nil
            child.terminationHandler = nil
            child.terminate()

            // Небольшое grace-окно на обработку SIGTERM, затем жёсткий SIGKILL.
            let deadline = Date().addingTimeInterval(2)
            while child.isRunning, Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            }
            if child.isRunning {
                kill(child.processIdentifier, SIGKILL)
            }
        }

        guard session != nil else { return }
        session = nil
        publish()
    }

    // MARK: - Публикация состояния

    /// Перепубликовать текущее состояние. Нужно на старте приложения: в файле мог
    /// остаться «активный» статус от процесса, который завершился аварийно.
    func syncSharedState() {
        publish()
    }

    private func publish() {
        SharedState.save(SharedStatus(session: session))
    }
}
