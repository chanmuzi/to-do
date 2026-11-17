#!/bin/bash
# 이 Mac에서 계속 쓸 코드 서명 인증서를 한 번 만든다(D-063).
# 확인용 키체인은 FLOATING_NOTES_KEYCHAIN으로 지정한다. 검색 목록은 바꾸지 않는다.
set -euo pipefail
umask 077

IDENTITY="Float Local Code Signing"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KEYCHAIN="${FLOATING_NOTES_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
if [ ! -f "$KEYCHAIN" ]; then
  echo "키체인을 찾을 수 없습니다: $KEYCHAIN" >&2
  exit 1
fi

# -c는 부분 이름으로도 찾는다. 비슷한 이름이 있어도 교체하지 않는 쪽으로 처리한다.
if security find-certificate -c "$IDENTITY" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "이미 '$IDENTITY' 이름에 해당하는 인증서가 있습니다. 만들거나 바꾸지 않습니다."
  security find-identity -p codesigning "$KEYCHAIN"
  exit 0
fi

echo "'$IDENTITY' 인증서(10년, codeSigning)를 만듭니다: $KEYCHAIN"
echo "신뢰 등록이나 관리자 권한은 필요하지 않습니다. 신뢰 설정은 바꾸지 않습니다."
echo "보통 암호를 묻지 않으며, 키체인이 잠겨 있으면 macOS의 security가 직접 묻습니다."
# show-keychain-info는 잠금 설정을 읽으며, 잠긴 키체인에서는 암호 확인을
# 기다릴 수 있다. 현재 상태는 SecKeychainGetStatus로 먼저 확인한다.
KEYCHAIN_STATE="$(/usr/bin/swift "$SCRIPT_DIR/signing-keychain.swift" "$KEYCHAIN")"
unset FLOATING_NOTES_KEYCHAIN_PASSWORD
if [ "$KEYCHAIN_STATE" = locked ]; then
  security unlock-keychain "$KEYCHAIN"
fi
security show-keychain-info "$KEYCHAIN"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/float-signing.XXXXXX")"
cleanup() {
  rm -rf "$WORK"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

cat > "$WORK/openssl.cnf" <<'EOF'
[req]
prompt = no
distinguished_name = subject
x509_extensions = signing
[subject]
CN = Float Local Code Signing
[signing]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF

/usr/bin/openssl req -new -x509 -newkey rsa:2048 -sha256 -nodes -days 3650 \
  -config "$WORK/openssl.cnf" -keyout "$WORK/private.pem" -out "$WORK/certificate.pem"
/usr/bin/openssl rand -hex 32 > "$WORK/import-password"
/usr/bin/openssl pkcs12 -export -name "$IDENTITY" \
  -inkey "$WORK/private.pem" -in "$WORK/certificate.pem" \
  -out "$WORK/identity.p12" -passout "file:$WORK/import-password"
security import "$WORK/identity.p12" -k "$KEYCHAIN" -f pkcs12 \
  -P "$(cat "$WORK/import-password")" -T /usr/bin/codesign
# import의 -T로 이 개인 키를 쓸 앱을 codesign으로 한정한다.
# 키체인 전체의 partition list를 변경할 필요가 없으며 다른 키의 ACL은 건드리지 않는다.

# anchor trusted를 요구하지 않는 로컬 코드 서명은 신뢰 등록 없이 검증된다.
# https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html
echo "인증서를 만들었습니다. 신뢰되지 않은 자체 서명이므로 -v 없이 전체 identity를 확인합니다."
security find-identity -p codesigning "$KEYCHAIN"
