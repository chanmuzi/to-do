// 잠금 상태를 읽고, 자동 확인용 임시 키체인만 환경 변수의 암호로 연다.
// 사용자 키체인의 암호 입력은 호출 셸의 security unlock-keychain이 담당한다.
import Foundation
import Security

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func check(_ result: OSStatus, _ operation: String) {
    guard result == errSecSuccess else {
        let detail = SecCopyErrorMessageString(result, nil) as String? ?? "\(result)"
        fail("\(operation): \(detail)")
    }
}

guard CommandLine.arguments.count == 2 else { fail("사용: signing-keychain.swift <키체인 경로>") }
let path = URL(fileURLWithPath: CommandLine.arguments[1]).resolvingSymlinksInPath().path
let environment = ProcessInfo.processInfo.environment
let testPassword = environment["FLOATING_NOTES_KEYCHAIN_PASSWORD"]
if testPassword != nil {
    // 로그인·시스템 키체인과 이를 가리키는 심볼릭 링크에는 자동 암호를 쓰지 않는다.
    let temporaryRoots = ["/private/tmp", "/private/var/folders"].map {
        URL(fileURLWithPath: $0).resolvingSymlinksInPath().path + "/"
    }
    let isTemporary = temporaryRoots.contains { path.hasPrefix($0) }
    guard environment["FLOATING_NOTES_KEYCHAIN"] != nil, isTemporary else {
        fail("FLOATING_NOTES_KEYCHAIN_PASSWORD는 명시한 임시 키체인에서만 사용할 수 있습니다.")
    }
}

var keychain: SecKeychain?
check(SecKeychainOpen(path, &keychain), "키체인 열기")
var flags: SecKeychainStatus = 0
check(SecKeychainGetStatus(keychain, &flags), "키체인 잠금 상태 확인")
if flags & kSecUnlockStateStatus == 0, let testPassword {
    // 임시 암호도 프로세스 명령 인자나 파일로 전달하지 않는다.
    let bytes = Array(testPassword.utf8)
    let result = bytes.withUnsafeBytes {
        SecKeychainUnlock(keychain, UInt32($0.count), $0.baseAddress, true)
    }
    check(result, "임시 키체인 잠금 해제")
    check(SecKeychainGetStatus(keychain, &flags), "잠금 해제 결과 확인")
}
print(flags & kSecUnlockStateStatus == 0 ? "locked" : "unlocked")
