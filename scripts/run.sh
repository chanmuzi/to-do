#!/bin/bash
# 빌드한 뒤 앱을 앞에서 실행한다. 인자는 앱에 그대로 넘긴다.
# 예: scripts/run.sh --notes-dir /tmp/fn-notes --appearance dark
# 환경 변수 CONFIGURATION=debug 로 디버그 빌드를 쓴다.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/build-app.sh" "${CONFIGURATION:-release}"
exec "${FLOATING_NOTES_APP_DIR:-$ROOT/build}/FloatingNotes.app/Contents/MacOS/FloatingNotes" "$@"
