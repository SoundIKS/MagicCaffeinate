import AppKit
import Observation

/// Статус-бар иконка + раскрывающаяся панель на NSPopover.
///
/// Обычный NSMenu не даёт нормально кликать NSPopUpButton/NSDatePicker внутри кастомных
/// ячеек (меню перехватывает события мыши), поэтому интерактивные контролы живут в popover'е
/// с обычной Auto Layout раскладкой. Панель пересобирается по изменениям
/// CaffeinateManager (withObservationTracking), отсчёт обновляется секундным тикером,
/// пока панель открыта.
///
/// `@unchecked Sendable` — осознанно: контроллер и панель создаются и живут только
/// на главном потоке (статус-бар, popover, Timer на main runloop), поэтому их состояние
/// не пересекает границы потоков. Пометка нужна лишь чтобы `withObservationTracking`
/// не жаловался на захват `self` в @Sendable onChange-замыкании.
final class StatusMenuController: NSObject, NSPopoverDelegate, @unchecked Sendable {

    private let manager = CaffeinateManager.shared
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let panel = MenuPanelViewController()
    private var ticker: Timer?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel(_:))

        popover.behavior = .transient
        popover.contentViewController = panel
        popover.delegate = self

        updateStatusItem()
        observeState()
    }

    // MARK: - Статус-бар

    private func updateStatusItem() {
        let name = manager.isActive ? "cup.and.saucer.fill" : "cup.and.saucer"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "MagicCaffeinate")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = manager.isActive
            ? "MagicCaffeinate — не даёт Mac спать"
            : "MagicCaffeinate — выключено"
    }

    @objc private func togglePanel(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let button = statusItem.button else { return }
        // «До времени» пересчитывается при каждом открытии панели: сегодня 18:00,
        // а если 18:00 уже прошло — 18:00 следующего дня.
        panel.prepareForDisplay()
        popover.contentSize = panel.fittingContentSize
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        startTicker()
    }

    // MARK: - Наблюдение за состоянием

    private func observeState() {
        withObservationTracking {
            _ = manager.session
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.updateStatusItem()
                self.panel.refresh()
                if self.popover.isShown {
                    self.popover.contentSize = self.panel.fittingContentSize
                }
                self.observeState()
            }
        }
    }

    // MARK: - Тикер отсчёта

    private func startTicker() {
        guard ticker == nil else { return }
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.panel.tickRemaining()
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    func popoverDidClose(_ notification: Notification) {
        stopTicker()
    }
}

// MARK: - Панель

/// Содержимое панели: главный переключатель, таймер, «до времени» и активный режим.
/// Все интерактивные контролы — обычные AppKit-вью в реальном окне, поэтому кликабельны.
final class MenuPanelViewController: NSViewController {

    private let manager = CaffeinateManager.shared
    private let panelWidth: CGFloat = 340
    private let durations = [5, 10, 15, 30, 45, 60, 90, 120]

    private var rootView = NSView()
    private var mainStack = NSStackView()

    // Шапка
    private let statusDot = NSView()
    private let statusLabel = NSTextField(labelWithString: "")

    // Контролы создаём один раз и переиспользуем между пересборками — так выбор
    // в пикерах и введённое время не сбрасываются.
    private let wakeSwitch = NSSwitch()
    private let durationPopUp = NSPopUpButton()
    private let startTimerButton = NSButton(title: "Запустить", target: nil, action: nil)
    private let datePicker = NSDatePicker()
    private let startUntilButton = NSButton(title: "Запустить", target: nil, action: nil)

    private let activeTitleLabel = NSTextField(labelWithString: "")
    private let activeRemainingLabel = NSTextField(labelWithString: "")
    private let stopButton = NSButton(title: "Остановить", target: nil, action: nil)

    override func loadView() {
        rootView = NSView()
        configureControls()
        refresh()
        view = rootView
    }

    // MARK: - Публичный API

    /// Вызывается при открытии панели: подставляет актуальное значение «До времени»
    /// и пересобирает содержимое.
    func prepareForDisplay() {
        if let session = manager.session, session.origin == .untilTime, let endsAt = session.endsAt {
            datePicker.dateValue = endsAt
        } else {
            datePicker.dateValue = Self.defaultUntilDate()
        }
        refresh()
    }

    /// Пересобирает иерархию по текущему состоянию менеджера и обновляет размер popover.
    func refresh() {
        updateHeader()
        updateControls()
        rebuildHierarchy()
        preferredContentSize = fittingContentSize
    }

    /// Обновляет только отсчёт (вызывается из тикера каждую секунду).
    func tickRemaining() {
        guard manager.isActive else { return }
        activeRemainingLabel.stringValue = Self.remainingText(for: manager.session)
    }

    /// Актуальный желаемый размер контента (для popover.contentSize).
    var fittingContentSize: NSSize {
        rootView.layoutSubtreeIfNeeded()
        let height = rootView.fittingSize.height
        return NSSize(width: panelWidth, height: max(120, ceil(height)))
    }

    // MARK: - Настройка контролов

    private func configureControls() {
        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 4
        statusDot.translatesAutoresizingMaskIntoConstraints = false
        statusDot.widthAnchor.constraint(equalToConstant: 8).isActive = true
        statusDot.heightAnchor.constraint(equalToConstant: 8).isActive = true

        statusLabel.font = .systemFont(ofSize: 12)

        wakeSwitch.target = self
        wakeSwitch.action = #selector(toggleWake(_:))

        for minutes in durations {
            durationPopUp.addItem(withTitle: Self.durationLabel(minutes))
        }
        durationPopUp.selectItem(at: 3) // 30 минут
        durationPopUp.widthAnchor.constraint(equalToConstant: 120).isActive = true

        startTimerButton.bezelStyle = .rounded
        startTimerButton.target = self
        startTimerButton.action = #selector(startTimerFromUI(_:))

        datePicker.datePickerStyle = .textFieldAndStepper
        datePicker.datePickerElements = [.hourMinute]
        datePicker.dateValue = Self.defaultUntilDate()
        datePicker.widthAnchor.constraint(equalToConstant: 110).isActive = true

        startUntilButton.bezelStyle = .rounded
        startUntilButton.target = self
        startUntilButton.action = #selector(startUntilFromUI(_:))

        stopButton.bezelStyle = .rounded
        stopButton.target = self
        stopButton.action = #selector(stopSession(_:))

        activeTitleLabel.font = .systemFont(ofSize: 12)
        activeRemainingLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        activeRemainingLabel.textColor = .secondaryLabelColor
    }

    // MARK: - Состояние контролов

    private func updateHeader() {
        let active = manager.isActive
        statusLabel.stringValue = active ? "Активно" : "Не активно"
        statusLabel.textColor = active ? .systemGreen : .secondaryLabelColor
        statusDot.layer?.backgroundColor = (active ? NSColor.systemGreen : NSColor.secondaryLabelColor).cgColor
    }

    private func updateControls() {
        wakeSwitch.state = manager.isActive ? .on : .off
        activeTitleLabel.stringValue = Self.activeTitle(for: manager.session)
        activeRemainingLabel.stringValue = Self.remainingText(for: manager.session)
    }

    // MARK: - Сборка иерархии

    private func rebuildHierarchy() {
        mainStack.removeFromSuperview()
        mainStack = NSStackView()
        mainStack.orientation = .vertical
        mainStack.alignment = .width
        mainStack.spacing = 8
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        // Шапка
        let header = hStack()
        let titleLabel = NSTextField(labelWithString: "MagicCaffeinate")
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        header.addArrangedSubview(titleLabel)
        let headerSpacer = flexSpacer()
        header.addArrangedSubview(headerSpacer)
        header.setCustomSpacing(6, after: headerSpacer)
        header.addArrangedSubview(statusDot)
        header.setCustomSpacing(5, after: statusDot)
        header.addArrangedSubview(statusLabel)
        mainStack.addArrangedSubview(header)

        mainStack.addArrangedSubview(separator())

        // Главный переключатель
        let switchRow = hStack()
        switchRow.addArrangedSubview(wakeSwitch)
        let switchLabel = NSTextField(labelWithString: "Не давать Mac спать")
        switchLabel.font = .systemFont(ofSize: 13)
        switchRow.addArrangedSubview(switchLabel)
        switchRow.addArrangedSubview(flexSpacer())
        mainStack.addArrangedSubview(switchRow)
        mainStack.addArrangedSubview(caption("caffeinate -i -d · система и дисплей не спят"))

        mainStack.addArrangedSubview(separator())

        // Таймер
        mainStack.addArrangedSubview(caption("Таймер"))
        mainStack.addArrangedSubview(inputRow(leading: "Длительность",
                                              controls: [durationPopUp, startTimerButton]))

        mainStack.addArrangedSubview(separator())

        // «До времени»
        mainStack.addArrangedSubview(caption("Бодрствовать до времени"))
        mainStack.addArrangedSubview(inputRow(leading: "До",
                                              controls: [datePicker, startUntilButton]))

        mainStack.addArrangedSubview(separator())

        // Активный режим
        mainStack.addArrangedSubview(caption("Активный режим"))
        mainStack.addArrangedSubview(buildActiveRow())

        mainStack.addArrangedSubview(separator())

        // Подвал
        let footer = hStack()
        footer.addArrangedSubview(shrinkable(caption("Обёртка над /usr/bin/caffeinate")))
        footer.addArrangedSubview(flexSpacer())
        let quitButton = NSButton(title: "Выйти", target: self, action: #selector(quit(_:)))
        quitButton.bezelStyle = .rounded
        footer.addArrangedSubview(quitButton)
        mainStack.addArrangedSubview(footer)

        rootView.addSubview(mainStack)
        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 14),
            mainStack.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 14),
            mainStack.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -14),
            mainStack.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -14),
            rootView.widthAnchor.constraint(equalToConstant: panelWidth),
        ])
    }

    /// Строка активного режима: название, остаток и кнопка «Остановить».
    private func buildActiveRow() -> NSView {
        guard manager.isActive else {
            return caption("Не активно")
        }

        let titles = NSStackView()
        titles.orientation = .vertical
        titles.alignment = .leading
        titles.spacing = 2

        activeTitleLabel.lineBreakMode = .byTruncatingTail
        activeRemainingLabel.lineBreakMode = .byTruncatingTail
        titles.addArrangedSubview(activeTitleLabel)
        titles.addArrangedSubview(activeRemainingLabel)

        let row = hStack()
        row.spacing = 6
        row.addArrangedSubview(shrinkable(titles))
        row.addArrangedSubview(flexSpacer())
        row.addArrangedSubview(stopButton)
        return row
    }

    // MARK: - Действия

    @objc private func toggleWake(_ sender: NSSwitch) {
        if sender.state == .on {
            manager.startIndefinitely()
        } else {
            manager.stop()
        }
    }

    @objc private func startTimerFromUI(_ sender: Any?) {
        let index = durationPopUp.indexOfSelectedItem
        guard durations.indices.contains(index) else { return }
        manager.startTimer(minutes: durations[index])
    }

    @objc private func startUntilFromUI(_ sender: Any?) {
        // Пикер знает только часы и минуты. Если выбранное время уже прошло,
        // трактуем его как те же часы следующих суток — иначе кнопка молча ничего не делает.
        var date = datePicker.dateValue
        if date <= Date() {
            date = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date
        }
        manager.startUntil(date)
    }

    @objc private func stopSession(_ sender: Any?) {
        manager.stop()
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    // MARK: - Форматирование

    /// Значение «До времени» по умолчанию: сегодня в 18:00, а если 18:00 уже прошло —
    /// в 18:00 следующего дня.
    static func defaultUntilDate(now: Date = Date(), calendar: Calendar = .current) -> Date {
        let startOfDay = calendar.startOfDay(for: now)
        let todayEvening = calendar.date(byAdding: .hour, value: 18, to: startOfDay) ?? now
        guard todayEvening <= now else { return todayEvening }
        return calendar.date(byAdding: .day, value: 1, to: todayEvening) ?? todayEvening
    }

    private static func activeTitle(for session: CaffeinateSession?) -> String {
        guard let session else { return "" }
        switch session.origin {
        case .toggle:
            return "Не давать Mac спать"
        case .timer:
            return "Таймер"
        case .untilTime:
            guard let endsAt = session.endsAt else { return "До времени" }
            return "До " + clockFormatter.string(from: endsAt)
        }
    }

    private static func remainingText(for session: CaffeinateSession?) -> String {
        guard let session else { return "" }
        guard let seconds = session.remainingSeconds() else { return "Без ограничения по времени" }
        return "Осталось " + countdown(seconds)
    }

    /// "01:23:45" или "23:45", если часов нет.
    static func countdown(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("HH:mm")
        return formatter
    }()

    private static func durationLabel(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) мин" }
        if minutes % 60 == 0 { let h = minutes / 60; return h == 1 ? "1 час" : "\(h) часа" }
        return "\(minutes / 60) ч \(minutes % 60) мин"
    }

    // MARK: - Хелперы раскладки

    private func hStack() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    /// Распорка, занимающая всё свободное место по горизонтали.
    private func flexSpacer() -> NSView {
        let view = NSView()
        view.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        view.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        return view
    }

    private func caption(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        return label
    }

    /// Подпись, которая сжимается (обрезается), если не хватает ширины.
    private func shrinkable(_ view: NSView) -> NSView {
        view.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(250), for: .horizontal)
        view.setContentHuggingPriority(NSLayoutConstraint.Priority(250), for: .horizontal)
        return view
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    /// Строка [подпись слева][распорка][контролы справа].
    private func inputRow(leading: String, controls: [NSView]) -> NSStackView {
        let row = hStack()
        row.addArrangedSubview(caption(leading))
        row.addArrangedSubview(flexSpacer())
        let group = hStack()
        group.spacing = 8
        for control in controls {
            group.addArrangedSubview(control)
        }
        row.addArrangedSubview(group)
        return row
    }
}
