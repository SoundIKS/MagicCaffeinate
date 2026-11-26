# MagicCaffeinate

[![Build & Release](https://github.com/SoundIKS/MagicCaffeinate/actions/workflows/release.yml/badge.svg)](https://github.com/SoundIKS/MagicCaffeinate/actions/workflows/release.yml)

Menu bar (трей) утилита для macOS — минимальная UI-обёртка над встроенным `/usr/bin/caffeinate`.
Одна задача: не давать Mac засыпать, пока это нужно.

- Иконка чашки в строке меню, панель с переключателем, таймером и «бодрствовать до времени».
- Чистый AppKit (`NSStatusItem` + `NSPopover`) — **Xcode не требуется**, собирается на Command Line Tools.
- Универсальный бинарник: Apple Silicon и Intel, macOS 14+.
- Никаких приватных API и App Store — персональная утилита, оборачивает системный `caffeinate`.
- При выходе приложение снимает все assertion'ы: дочерний `caffeinate` не переживает родителя.

## Установка

### Homebrew (рекомендуется)

```bash
brew install --cask SoundIKS/tap/magiccaffeinate
```

Ставит `MagicCaffeinate.app` в `/Applications`. Cask сам снимает quarantine-атрибут.
Обновление — `brew upgrade --cask magiccaffeinate`, удаление — `brew uninstall --cask magiccaffeinate`.

### Из терминала одной командой (без Homebrew)

```bash
curl -fL -o /tmp/magiccaffeinate-install.sh https://raw.githubusercontent.com/SoundIKS/MagicCaffeinate/master/Scripts/install.sh
bash /tmp/magiccaffeinate-install.sh
```

Скрипт скачивает DMG последнего релиза с GitHub, копирует приложение в `/Applications`,
снимает карантин и запускает. Подходит для любого Mac (Intel или Apple Silicon).

### Вручную (DMG)

1. Скачайте `MagicCaffeinate.dmg` со [страницы релизов](https://github.com/SoundIKS/MagicCaffeinate/releases/latest).
2. Откройте образ и перетащите **MagicCaffeinate** в *Applications*.
3. Один раз снимите карантин:

```bash
xattr -dr com.apple.quarantine /Applications/MagicCaffeinate.app
open /Applications/MagicCaffeinate.app
```

### Почему нужен шаг с карантином

Сборки подписаны **ad-hoc**: Developer ID у проекта нет, нотаризации Apple тоже,
поэтому Gatekeeper не может автоматически подтвердить издателя. Приложение при этом
не имеет сетевых и файловых entitlements, а весь код — в этом репозитории.
Homebrew-тэп и `Scripts/install.sh` снимают атрибут за вас.

Если карантин не снять, macOS покажет «Apple не может проверить приложение»;
тогда запуск разрешается через **Системные настройки → Конфиденциальность и безопасность → «Всё равно открыть»**.

Требования: macOS 14 (Sonoma) или новее.

## Что умеет

Всё сводится к одному режиму — `/usr/bin/caffeinate -i -d`: система не уходит в idle-sleep,
дисплей не гаснет. Одновременно живёт не больше одного процесса.

| Действие | Команда caffeinate |
|---|---|
| Переключатель «Не давать Mac спать» | `caffeinate -i -d` (бессрочно) |
| Таймер на N минут | `caffeinate -i -d -t N*60` |
| «Бодрствовать до времени» | `caffeinate -i -d -t <секунд до момента>` |

- «До времени» по умолчанию подставляет **сегодня 18:00**; если 18:00 уже прошло —
  18:00 следующего дня. Значение пересчитывается при каждом открытии панели.
- Активный режим, остаток времени и кнопка «Остановить» — в разделе «Активный режим».
  Отсчёт в панели обновляется раз в секунду, пока панель открыта.
- Иконка заливается, когда что-то активно.
- Панель реализована на `NSPopover` (а не `NSMenu`): в обычном `NSMenu` NSPopUpButton
  и NSDatePicker не получают клики.

## URL-команды

Приложение принимает `magiccaffeinate://` — так его сможет дёргать виджет:

```bash
open "magiccaffeinate://start?minutes=60"   # таймер на час (значение по умолчанию — 60)
open "magiccaffeinate://stop"               # остановить активный режим
```

## Автозапуск при логине

Через сборку из исходников:

```bash
./build.sh install-agent     # LaunchAgent (~/Library/LaunchAgents/local.magiccaffeinate.plist)
./build.sh uninstall-agent   # убрать
```

Проверка: `launchctl print gui/$(id -u)/local.magiccaffeinate` → `state = running`.
Агент запускает приложение только в GUI-сессии (`LimitLoadToSessionType=Aqua`).

Для версии из `/Applications` проще добавить приложение в
**Системные настройки → Основные → Элементы входа и расширения**.

## Сборка из исходников

Нужны только Command Line Tools (`xcode-select --install`), полный Xcode не требуется.

```bash
./build.sh run          # собрать и запустить (иконка чашки в статус-баре)
./build.sh build        # только собрать MagicCaffeinate.app
./build.sh dmg          # собрать dist/MagicCaffeinate-<version>.dmg (+ sha256)
./build.sh icon         # перегенерировать Resources/AppIcon.icns
./build.sh clean        # удалить .build, .app и dist
```

Переменные окружения:

```bash
UNIVERSAL=1 VERSION=1.0.0 ./build.sh dmg
```

- `UNIVERSAL=1` — универсальный бинарник `arm64 + x86_64` (без флага собирается нативная архитектура);
- `VERSION` — `CFBundleShortVersionString` и имя DMG (по умолчанию `1.0.0`);
- `BUILD_NUMBER` — `CFBundleVersion` (по умолчанию число коммитов).

`build.sh` компилирует напрямую через `swiftc` — сознательно без SwiftPM: его build-система
зависит от SDK и кэшей окружения и падает там, где прямой `swiftc` работает (типовое:
Command Line Tools без полного Xcode, закрытые кэши `~/Library`, CI-раннеры с
несовпадающими версиями). `Package.swift` остаётся, чтобы проект можно было открыть в IDE.

Подпись — ad-hoc (`codesign --sign -`), достаточная для локального запуска и установки.

## Релизы и CI

`.github/workflows/release.yml` собирает проект на macOS-раннере:

- **push в `master` / pull request** — сборка универсального DMG и артефакт сборки;
- **тег `v*`** — GitHub Release с `MagicCaffeinate-<version>.dmg` (плюс `MagicCaffeinate.dmg`
  как ссылка «последний релиз»), контрольной суммой SHA-256 и черновиком release notes;
- **опционально** — автообновление cask в Homebrew-тэпе, если заданы секреты
  `TAP_TOKEN` (PAT с правом записи в репозиторий тэпа) и, при необходимости, `TAP_REPO`.

Выпуск новой версии:

```bash
git tag v1.0.1 && git push origin v1.0.1
```

### Homebrew-тэп

Cask лежит в отдельном репозитории `SoundIKS/homebrew-tap`, шаблон — `packaging/magiccaffeinate.rb.tmpl`.
CI подставляет версию и sha256 сам (см. секрет `TAP_TOKEN`); вручную это делается так:

```bash
VERSION=1.0.1
SHA256=$(shasum -a 256 "dist/MagicCaffeinate-${VERSION}.dmg" | cut -d' ' -f1)
sed -e "s|__VERSION__|${VERSION}|g" -e "s|__SHA256__|${SHA256}|g" -e "s|__OWNER__|SoundIKS|g" \
  packaging/magiccaffeinate.rb.tmpl > /путь/к/homebrew-tap/Casks/magiccaffeinate.rb
```

## Проверка

- Сборка: `./build.sh` → есть `MagicCaffeinate.app`, `plutil -lint` ок, `codesign -v` ок.
- Режим: включи переключатель → `pmset -g assertions` (строки
  `PreventUserIdleSystemSleep` / `PreventUserIdleDisplaySleep` с pid дочернего `caffeinate`).
- Таймер: запусти на 5 минут → в панели идёт отсчёт, по истечении assertion'ы исчезают сами.
- «До времени»: открой панель → в поле стоит 18:00 (или 18:00 завтра, если уже позже).
- Чистый выход: включи режим → «Выйти» → строки от нашего `caffeinate` в `pmset -g assertions` исчезли.
- URL: `open "magiccaffeinate://start?minutes=5"` → включился таймер на 5 минут.

## Структура

```
Sources/MagicCaffeinate/
  MagicCaffeinateApp.swift   # @main, NSApplicationDelegate, URL-схема, terminateAll при выходе
  StatusMenuController.swift # статус-бар + NSPopover-панель, тикер отсчёта
  CaffeinateManager.swift    # единственный процесс /usr/bin/caffeinate
  Models.swift               # CaffeinateSession, AppCommand
  SharedState.swift          # публикация состояния для виджета (App Group + fallback)
Resources/AppIcon.icns       # иконка (генерируется Scripts/make-icon.swift)
Scripts/make-icon.swift      # рисует иконку кодом
Scripts/install.sh           # установка из терминала с GitHub-релиза
packaging/                    # шаблон Homebrew-cask
build.sh                      # сборка, DMG, LaunchAgent
.github/workflows/release.yml # CI: сборка DMG и GitHub Release
```

## Общее состояние для виджета

`CaffeinateManager` публикует состояние в `SharedState` (JSON `status.json`):

- `isActive`, `origin` (`toggle` / `timer` / `untilTime`), `startedAt`, `endsAt`;
- пишется в контейнер App Group `group.local.magiccaffeinate`, если он доступен
  (нужна подпись с entitlements `com.apple.security.application-groups`),
  и всегда — в `~/Library/Application Support/MagicCaffeinate/status.json`
  как запасной путь для локальной ad-hoc сборки;
- на старте приложения состояние перепубликуется, чтобы в файле не остался
  «активный» статус от аварийно завершившегося запуска.

### Дальше: виджет

План — WidgetKit extension в том же бандле: статус и остаток времени, кнопка,
запускающая таймер на час через `magiccaffeinate://start?minutes=60`.

Для этого нужен полный Xcode и подпись с team ID (хотя бы бесплатный personal team):
только с ней существует контейнер App Group, через который sandbox'ed виджет читает
`status.json`. Заготовки под это уже есть: `AppCommand` в `Models.swift` и `SharedState.swift`.

## Примечания

- В «Система → Аккумулятор» как причина «не спит» отображается `caffeinate` (системный процесс),
  а не имя приложения: под капотом сознательно обёрнуто именно над `/usr/bin/caffeinate`.
- При `kill -9` приложения дочерний `caffeinate` переживает родителя и держит assertion до своего
  выхода — корректно снимать только обычным выходом из приложения.
