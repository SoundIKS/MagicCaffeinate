#!/usr/bin/env bash
# build.sh — сборка и упаковка MagicCaffeinate без Xcode.
# Команды: build | run | dmg | icon | install-agent | uninstall-agent | clean
#
# Переменные окружения:
#   VERSION=1.0.0      версия в Info.plist и в имени DMG
#   BUILD_NUMBER=1     CFBundleVersion (по умолчанию — число коммитов)
#   UNIVERSAL=1        собрать универсальный бинарник arm64 + x86_64

set -euo pipefail

APP_NAME="MagicCaffeinate"
BUNDLE_ID="local.magiccaffeinate"
MIN_MACOS="14.0"
VERSION="${VERSION:-1.0.0}"
# pwd -P: физический путь (macOS-ФС регистронезависима, и clang считает «Personal» и
# «personal» разными путями — это ломало модульный кэш). Канонизируем раз и навсегда.
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
BUILD_DIR="$PROJECT_DIR/.build"
DIST_DIR="$PROJECT_DIR/dist"
BIN_SOURCE="$BUILD_DIR/release/$APP_NAME"
APP_DIR="$PROJECT_DIR/$APP_NAME.app"
BIN_TARGET="$APP_DIR/Contents/MacOS/$APP_NAME"
ICON_SOURCE="$PROJECT_DIR/Resources/AppIcon.icns"
AGENT_PLIST="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
AGENT_LABEL="$BUNDLE_ID"

if [ -z "${BUILD_NUMBER:-}" ]; then
  if git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    BUILD_NUMBER="$(git -C "$PROJECT_DIR" rev-list --count HEAD)"
  else
    BUILD_NUMBER="1"
  fi
fi

native_arch() {
  case "$(uname -m)" in
    arm64) echo "arm64" ;;
    x86_64) echo "x86_64" ;;
    *) echo "arm64" ;;
  esac
}

# Архитектуры сборки: одна (нативная) либо обе для универсального бандла.
target_archs() {
  if [ "${UNIVERSAL:-0}" = "1" ]; then
    echo "arm64 x86_64"
  else
    native_arch
  fi
}

# Компилирует один срез бинарника напрямую через swiftc.
# SwiftPM (swift build) сознательно не используется: его build-система
# зависит от SDK/кэшей окружения и падает там, где прямой swiftc работает
# (типовое: Command Line Tools без полного Xcode, закрытые кэши ~/Library,
# CI-раннеры с несовпадающими версиями). Package.swift остаётся для IDE.
compile_arch() {
  local arch="$1" output="$2"
  local module_cache="$BUILD_DIR/module-cache-$arch"
  mkdir -p "$module_cache"
  swiftc -parse-as-library -O \
    -target "${arch}-apple-macosx${MIN_MACOS}" \
    -module-name "$APP_NAME" \
    -module-cache-path "$module_cache" \
    -Xcc -fmodules-cache-path="$module_cache" \
    -framework AppKit \
    "$PROJECT_DIR"/Sources/MagicCaffeinate/*.swift \
    -o "$output"
}

build_binary() {
  mkdir -p "$BUILD_DIR/release"
  local slices=()
  for arch in $(target_archs); do
    echo "   компиляция $arch"
    local slice="$BUILD_DIR/release/$APP_NAME-$arch"
    compile_arch "$arch" "$slice"
    slices+=("$slice")
  done

  if [ "${#slices[@]}" -eq 1 ]; then
    cp "${slices[0]}" "$BIN_SOURCE"
  else
    lipo -create -output "$BIN_SOURCE" "${slices[@]}"
  fi
}

build_icon() {
  if [ ! -f "$ICON_SOURCE" ]; then
    echo "→ генерация иконки"
    swift "$PROJECT_DIR/Scripts/make-icon.swift" "$ICON_SOURCE"
  fi
}

build_app() {
  echo "→ сборка бинарника ($(target_archs | tr '\n' ' '))"
  build_binary
  build_icon

  echo "→ собираю $APP_DIR"
  rm -rf "$APP_DIR"
  mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
  cp "$BIN_SOURCE" "$BIN_TARGET"
  cp "$ICON_SOURCE" "$APP_DIR/Contents/Resources/AppIcon.icns"

  PLIST="$APP_DIR/Contents/Info.plist"
  cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
    <key>LSUIElement</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>Personal utility. Wraps /usr/bin/caffeinate.</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key><string>$BUNDLE_ID.command</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>magiccaffeinate</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
EOF

  # Ad-hoc подпись: Developer ID нет, для локального запуска и установки этого достаточно.
  codesign --force --sign - --identifier "$BUNDLE_ID" "$APP_DIR"
  codesign --verify --deep --strict "$APP_DIR"

  plutil -lint "$PLIST" >/dev/null && echo "✓ $APP_DIR готов (v$VERSION, build $BUILD_NUMBER)"
}

# DMG для распространения: приложение + ярлык Applications для перетаскивания.
build_dmg() {
  build_app

  local dmg="$DIST_DIR/${APP_NAME}-${VERSION}.dmg"
  # Глобальная переменная, чтобы EXIT-ловушка не спотыкалась о set -u
  # (local-переменная уже вне области видимости к моменту выхода).
  STAGING_DIR="$(mktemp -d)"
  trap 'rm -rf "$STAGING_DIR"' EXIT

  cp -R "$APP_DIR" "$STAGING_DIR/"
  ln -s /Applications "$STAGING_DIR/Applications"

  mkdir -p "$DIST_DIR"
  rm -f "$dmg"
  echo "→ собираю DMG"
  hdiutil create \
    -volname "$APP_NAME $VERSION" \
    -srcfolder "$STAGING_DIR" \
    -fs HFS+ \
    -format UDZO \
    -ov -quiet \
    "$dmg"

  hdiutil verify -quiet "$dmg"
  echo "✓ $dmg"
  ( cd "$DIST_DIR" && shasum -a 256 "$(basename "$dmg")" | tee "$(basename "$dmg").sha256" )
}

run_app() {
  build_app
  open "$APP_DIR"
}

install_icon_now() {
  build_icon
}

install_agent() {
  build_app
  # Идемпотентно: сначала выгружаем старый агент, потом пишем plist и грузим заново.
  launchctl bootout "gui/$(id -u)/$AGENT_LABEL" 2>/dev/null || true
  cat > "$AGENT_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$AGENT_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BIN_TARGET</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><false/>
    <key>LimitLoadToSessionType</key><string>Aqua</string>
    <key>ProcessType</key><string>Interactive</string>
    <key>StandardOutPath</key><string>$HOME/Library/Logs/MagicCaffeinate.log</string>
    <key>StandardErrorPath</key><string>$HOME/Library/Logs/MagicCaffeinate.error.log</string>
</dict>
</plist>
EOF
  launchctl bootstrap "gui/$(id -u)" "$AGENT_PLIST"
  launchctl print "gui/$(id -u)/$AGENT_LABEL" 2>/dev/null || true
  echo "✓ LaunchAgent установлен: $AGENT_PLIST"
}

uninstall_agent() {
  launchctl bootout "gui/$(id -u)/$AGENT_LABEL" 2>/dev/null || true
  rm -f "$AGENT_PLIST"
  echo "✓ LaunchAgent удалён"
}

cleanup() {
  rm -rf "$BUILD_DIR" "$APP_DIR" "$DIST_DIR"
  echo "✓ Очищено"
}

case "${1:-build}" in
  build) build_app ;;
  run) run_app ;;
  dmg) build_dmg ;;
  icon) install_icon_now ;;
  install-agent) install_agent ;;
  uninstall-agent) uninstall_agent ;;
  clean) cleanup ;;
  *) echo "usage: $0 {build|run|dmg|icon|install-agent|uninstall-agent|clean}"; exit 1 ;;
esac
