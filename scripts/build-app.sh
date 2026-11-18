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

# -v는 신뢰되지 않은 자체 서명 인증서를 숨기므로 전체 identity에서 찾는다.
IDENTITY_QUERY=(security find-identity -p codesigning)
SIGN_COMMAND=(codesign --force)
if [ -n "${FLOATING_NOTES_KEYCHAIN:-}" ]; then
  IDENTITY_QUERY+=("$FLOATING_NOTES_KEYCHAIN")
  SIGN_COMMAND+=(--keychain "$FLOATING_NOTES_KEYCHAIN")
fi
IDENTITY="${FLOATING_NOTES_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  IDENTITIES="$("${IDENTITY_QUERY[@]}")"
  if [[ "$IDENTITIES" == *'"Float Local Code Signing"'* ]]; then
    IDENTITY="Float Local Code Signing"
  else
    IDENTITY="-"
    echo "경고: 고정 서명 인증서가 없어 임시 서명(-)을 씁니다. 업데이트 시 macOS 권한이 유지되지 않을 수 있습니다." >&2
  fi
fi

swift build --package-path "$PACKAGE" --configuration "$CONFIGURATION" --product FloatingNotes
BINARY="$(swift build --package-path "$PACKAGE" --configuration "$CONFIGURATION" --show-bin-path)/FloatingNotes"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/FloatingNotes"
cp "$RESOURCES/Info.plist" "$APP/Contents/Info.plist"
# 원본 DisplayName은 파일명과 맞추고, 시스템 표시 이름은 지역화 리소스에서 읽는다(D-062).
cp -R "$RESOURCES/ko.lproj" "$RESOURCES/en.lproj" "$APP/Contents/Resources/"
cp "$RESOURCES/tokens.json" "$APP/Contents/Resources/tokens.json"
cp -R "$RESOURCES/Fonts" "$APP/Contents/Resources/Fonts"
cp -R "$RESOURCES/SpaceImages" "$APP/Contents/Resources/SpaceImages"
cp "$RESOURCES/menubar-icon.pdf" "$APP/Contents/Resources/menubar-icon.pdf"

# 앱 아이콘: appiconset의 PNG를 iconutil이 받는 이름으로 옮겨 .icns로 만든다.
ICON_WORK="$(mktemp -d "${TMPDIR:-/tmp}/float-icon.XXXXXX")"
trap 'rm -rf "$ICON_WORK"' EXIT
ICONSET="$ICON_WORK/AppIcon.iconset"
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
xcrun actool "$RESOURCES/AppIcon.icon" --compile "$ICON_WORK" --platform macosx \
  --minimum-deployment-target 26.0 --app-icon AppIcon \
  --output-partial-info-plist "$ICON_WORK/icon.plist"
cp "$ICON_WORK/Assets.car" "$APP/Contents/Resources/"
rm -rf "$ICON_WORK"

# Hardened Runtime은 켜지 않는다: 켜면 EventKit 캘린더 접근에 별도
# com.apple.security.personal-information.calendars 엔타이틀먼트가 필요하다(D-063).
# 명시한 identity가 잘못됐거나 서명에 실패하면 임시 서명으로 숨기지 않고 실패한다.
"${SIGN_COMMAND[@]}" --sign "$IDENTITY" "$APP"

echo "$APP"
