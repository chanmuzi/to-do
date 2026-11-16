/// 등록한 전역 단축키 하나를 가리키는 값.
nonisolated struct HotKeyToken: Hashable, Sendable {
    let id: UInt32
}

/// 전역 단축키를 등록하지 못했다.
nonisolated struct HotKeyRegistrationError: Error, Hashable, Sendable, CustomStringConvertible {
    /// Carbon의 `eventHotKeyExistsErr`. 다른 프로그램이 이미 그 키를 등록했다.
    static let alreadyRegisteredStatus: Int32 = -9878

    /// 시스템이 돌려준 값(`OSStatus`).
    let status: Int32

    /// 다른 앱이 이미 쓰는 키인지(spec 13, 19).
    var isTakenByAnotherApp: Bool { status == Self.alreadyRegisteredStatus }

    var description: String {
        isTakenByAnotherApp ? "다른 앱이 이미 쓰는 키입니다" : "시스템이 등록을 받지 않았습니다(\(status))"
    }
}

/// 다른 앱을 쓰는 중에도 받는 키를 시스템에 등록하는 곳. 실제 구현은 `CarbonHotKeyRegistrar`(D-011)이고,
/// 테스트는 가짜를 넣어 등록 실패를 본다.
protocol HotKeyRegistering: AnyObject {
    func register(_ chord: KeyChord, handler: @escaping () -> Void) throws(HotKeyRegistrationError) -> HotKeyToken
    func unregister(_ token: HotKeyToken)
}
