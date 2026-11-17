#!/bin/bash
# SwiftPM으로 빌드하고 실행할 수 있는 .app 묶음을 build/ 에 만든다(D-011).
# 사용: scripts/build-app.sh [debug|release]   (기본 release)
set -euo pipefail

CONFIGURATION="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGE="$ROOT/App"
RESOURCES="$PACKAGE/Resources"
# FLOATING_NOTES_APP_DIR로 묶음을 둘 폴더를 바꾼다(기본 build/). 실행 중인 묶음과 분리할 때 사용.
APP="${FLOATING_NOTES_APP_DIR:-$ROOT/build}/FloatingNotes.app"

swift build --package-path "$PACKAGE" --configuration "$CONFIGURATION" --product FloatingNotes
BINARY="$(swift build --package-path "$PACKAGE" --configuration "$CONFIGURATION" --show-bin-path)/FloatingNotes"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/FloatingNotes"
cp "$RESOURCES/Info.plist" "$APP/Contents/Info.plist"
cp "$RESOURCES/tokens.json" "$APP/Contents/Resources/tokens.json"
cp -R "$RESOURCES/Fonts" "$APP/Contents/Resources/Fonts"
cp -R "$RESOURCES/SpaceImages" "$APP/Contents/Resources/SpaceImages"
cp "$RESOURCES/menubar-icon.pdf" "$APP/Contents/Resources/menubar-icon.pdf"

# 앱 아이콘: appiconset의 PNG를 iconutil이 받는 이름으로 옮겨 .icns로 만든다.
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
SOURCE="$RESOURCES/AppIcon.appiconset"
cp "$SOURCE/icon_16.png"   "$ICONSET/icon_16x16.png"
cp "$SOURCE/icon_32.png"   "$ICONSET/icon_16x16@2x.png"
cp "$SOURCE/icon_32.png"   "$ICONSET/icon_32x32.png"
cp "$SOURCE/icon_64.png"   "$ICONSET/icon_32x32@2x.png"
cp "$SOURCE/icon_128.png"  "$ICONSET/icon_128x128.png"
cp "$SOURCE/icon_256.png"  "$ICONSET/icon_128x128@2x.png"
cp "$SOURCE/icon_256.png"  "$ICONSET/icon_256x256.png"
cp "$SOURCE/icon_512.png"  "$ICONSET/icon_256x256@2x.png"
cp "$SOURCE/icon_512.png"  "$ICONSET/icon_512x512.png"
cp "$SOURCE/icon_1024.png" "$ICONSET/icon_512x512@2x.png"
iconutil --convert icns --output "$APP/Contents/Resources/AppIcon.icns" "$ICONSET"
rm -rf "$(dirname "$ICONSET")"

# 이 Mac에서만 쓰는 임시 서명.
codesign --force --sign - "$APP"

echo "$APP"
