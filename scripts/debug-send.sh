#!/bin/bash
# 실행 중인 디버그 빌드에 확인용 명령을 보낸다(App/Sources/FloatingNotes/DebugControl.swift).
# 앱을 --debug-control <출력 폴더> 로 켠 뒤에 쓴다. 표는 그 폴더의 control-token 에서 읽는다.
# 사용: scripts/debug-send.sh <출력 폴더> <명령...>
# 예:   scripts/debug-send.sh /tmp/fn-out dump state.json
set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "사용: $0 <출력 폴더> <명령...>" >&2
  exit 64
fi
DIRECTORY="$1"
shift
TOKEN="$(cat "$DIRECTORY/control-token")"

osascript -l JavaScript -e '
ObjC.import("Foundation");
function run(argv) {
  $.NSDistributedNotificationCenter.defaultCenter
    .postNotificationNameObjectUserInfoDeliverImmediately("local.floating-notes.debug", argv[0], $(), true);
}' "$TOKEN $*"
