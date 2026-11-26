#!/bin/zsh
# 시안 본문(<title>, 절, 페이지 스크립트)을 키트와 합쳐 한 파일로 만든다.
# 쓰기: docs/mockup-kit/build.sh <본문.html> <나갈 page.html>
# 본문 파일 맨 위에 <title>을 둔다. 본문의 <script>는 FloatKit을 쓸 수 있다.
set -e
kit=${0:A:h}
body=$1; out=$2
[[ -f $body && -n $out ]] || { echo "쓰기: build.sh <본문.html> <page.html>" >&2; exit 1; }
{
  awk '{print} /<\/title>/{exit}' "$body"
  echo '<meta name="claude:viewport-fit-sides" content="cover">'
  echo '<style>'; cat "$kit/kit.css"; echo '</style>'
  echo '<script>'; cat "$kit/kit.js"; echo '</script>'
  awk 'found{print} /<\/title>/{found=1}' "$body"
} > "$out"
# 금지 기호 검사(유니코드 번호로): 가운뎃점과 유사 기호, 대시
if perl -CSD -ne 'if (/[\x{00B7}\x{2027}\x{2219}\x{22C5}\x{2014}\x{2013}]/) { print "$.: $_"; $f=1 } END { exit($f ? 0 : 1) }' "$out"; then echo "금지 기호가 있습니다" >&2; exit 2; fi
echo "$out"
