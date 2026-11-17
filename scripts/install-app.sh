#!/bin/bash
# 릴리스 빌드를 만들어 응용 프로그램 폴더에 "플로팅 노트.app"으로 넣는다. sudo를 쓰지 않는다.
# 사용: scripts/install-app.sh
#   넣을 폴더: /Applications. 쓸 수 없으면 ~/Applications.
#   FLOATING_NOTES_INSTALL_DIR=<폴더> 로 넣을 폴더를 바꾼다(확인용으로 임시 폴더에 넣을 때).
# 이미 실행 중인 앱이 있으면 먼저 정상 종료를 요청하고(저장하지 못한 노트가 있으면 앱이 묻는다) 끝날 때까지 기다린다.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="플로팅 노트.app"
# 끝낼 앱의 번들 ID. 확인용으로 다른 값을 주면 실행 중인 앱을 건드리지 않는다.
BUNDLE_ID="${FLOATING_NOTES_BUNDLE_ID:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$ROOT/App/Resources/Info.plist")}"
QUIT_TIMEOUT="${FLOATING_NOTES_QUIT_TIMEOUT:-30}"

if [ -n "${FLOATING_NOTES_INSTALL_DIR:-}" ]; then
  DEST_DIR="$FLOATING_NOTES_INSTALL_DIR"
elif [ -w /Applications ]; then
  DEST_DIR="/Applications"
else
  DEST_DIR="$HOME/Applications"
fi
mkdir -p "$DEST_DIR"
if [ ! -w "$DEST_DIR" ]; then
  echo "넣을 폴더에 쓸 수 없습니다: $DEST_DIR" >&2
  exit 73
fi
DEST="$DEST_DIR/$APP_NAME"

BUILT="$("$ROOT/scripts/build-app.sh" release | tail -n 1)"
if [ ! -d "$BUILT" ]; then
  echo "빌드한 앱을 찾지 못했습니다: $BUILT" >&2
  exit 1
fi

# 이 번들 ID로 실행 중인 앱이 있는지.
running() {
  [ "$(osascript -e "application id \"$BUNDLE_ID\" is running" 2>/dev/null || echo false)" = "true" ]
}

if running; then
  echo "실행 중인 플로팅 노트를 종료합니다"
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null
  waited=0
  while running; do
    if [ "$waited" -ge "$QUIT_TIMEOUT" ]; then
      echo "플로팅 노트가 ${QUIT_TIMEOUT}초 안에 끝나지 않았습니다(저장 확인 창이 떠 있을 수 있습니다). 설치하지 않았습니다." >&2
      exit 75
    fi
    sleep 1
    waited=$((waited + 1))
  done
fi

# 새 묶음을 옆에 먼저 복사한 뒤 바꿔 넣는다. 복사가 실패해도 설치되어 있던 앱은 그대로 남는다.
STAGING="$DEST_DIR/.$APP_NAME.installing"
rm -rf "$STAGING"
ditto "$BUILT" "$STAGING"
rm -rf "$DEST"
mv "$STAGING" "$DEST"

echo "$DEST"
