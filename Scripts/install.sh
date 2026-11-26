#!/usr/bin/env bash
# install.sh — установка MagicCaffeinate на любой Mac из терминала, без Homebrew.
#
# Скачивает DMG последнего релиза с GitHub, копирует приложение в /Applications,
# снимает quarantine-атрибут (сборка подписана ad-hoc, без Developer ID) и запускает.
#
# Использование:
#   curl -fL -o install.sh https://raw.githubusercontent.com/SoundIKS/MagicCaffeinate/master/Scripts/install.sh
#   bash install.sh
#
# Переменные окружения:
#   REPO=SoundIKS/MagicCaffeinate   репозиторий с релизами (по умолчанию подставляется при сборке шаблона)
#   DEST=/Applications           куда ставить
#   NO_LAUNCH=1                  не запускать после установки

set -euo pipefail

REPO="${REPO:-SoundIKS/MagicCaffeinate}"
DEST="${DEST:-/Applications}"
APP_NAME="MagicCaffeinate"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Это macOS-приложение, на $(uname -s) оно не запустится." >&2
  exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

echo "→ скачиваю DMG последнего релиза ${REPO}"
curl -fL --retry 3 --progress-bar \
  "https://github.com/${REPO}/releases/latest/download/MagicCaffeinate.dmg" \
  -o "$work/MagicCaffeinate.dmg"

echo "→ монтирую образ"
mount_point="$work/mnt"
mkdir -p "$mount_point"
hdiutil attach -nobrowse -readonly -mountpoint "$mount_point" "$work/MagicCaffeinate.dmg" >/dev/null
cleanup_mount() {
  hdiutil detach "$mount_point" -quiet >/dev/null 2>&1 || true
}
trap 'cleanup_mount; rm -rf "$work"' EXIT

if [ -e "$DEST/$APP_NAME.app" ]; then
  echo "→ удаляю прежнюю версию"
  # Приложение может быть запущено — просим штатно завершиться.
  osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
  pkill -f "$DEST/$APP_NAME.app/Contents/MacOS/$APP_NAME" >/dev/null 2>&1 || true
  rm -rf "$DEST/$APP_NAME.app"
fi

echo "→ копирую в $DEST"
cp -R "$mount_point/$APP_NAME.app" "$DEST/"
xattr -dr com.apple.quarantine "$DEST/$APP_NAME.app" 2>/dev/null || true

echo "✓ установлено: $DEST/$APP_NAME.app"
if [ "${NO_LAUNCH:-0}" != "1" ]; then
  open "$DEST/$APP_NAME.app"
fi
