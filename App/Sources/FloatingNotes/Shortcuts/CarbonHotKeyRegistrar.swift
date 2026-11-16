import Carbon.HIToolbox

/// Carbon `RegisterEventHotKey`로 전역 단축키를 등록한다(D-011). 손쉬운 사용 권한이 필요 없다.
/// 누른 키는 앱의 이벤트 대상으로 오고, 메인 런 루프에서 `handler`를 부른다.
///
/// 독점(`kEventHotKeyExclusive`)으로 등록한다. 보통 등록은 다른 앱이 같은 키를 이미 등록했어도 받아들여져
/// 겹친 것을 알 수 없다. 독점 등록은 같은 키가 이미 등록돼 있으면 `eventHotKeyExistsErr`로 실패하므로,
/// 그것으로 "다른 앱이 쓰는 키"를 안다(spec 13, 19).
final class CarbonHotKeyRegistrar: HotKeyRegistering {
    /// 이 앱의 단축키를 가리는 표시("FNhk").
    private static let signature: OSType = 0x464E_686B

    private var handlers: [UInt32: () -> Void] = [:]
    private var references: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?

    isolated deinit {
        references.values.forEach { UnregisterEventHotKey($0) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    func register(_ chord: KeyChord, handler: @escaping () -> Void) throws(HotKeyRegistrationError) -> HotKeyToken {
        try installEventHandlerIfNeeded()
        let id = nextID
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(chord.key.keyCode), Self.carbonModifiers(chord.modifiers),
            EventHotKeyID(signature: Self.signature, id: id), GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive), &reference
        )
        guard status == noErr, let reference else { throw HotKeyRegistrationError(status: status) }
        nextID += 1
        references[id] = reference
        handlers[id] = handler
        return HotKeyToken(id: id)
    }

    func unregister(_ token: HotKeyToken) {
        handlers[token.id] = nil
        if let reference = references.removeValue(forKey: token.id) { UnregisterEventHotKey(reference) }
    }

    fileprivate func fire(_ id: UInt32) {
        handlers[id]?()
    }

    private func installEventHandlerIfNeeded() throws(HotKeyRegistrationError) {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(), hotKeyPressed, 1, &spec,
            Unmanaged.passUnretained(self).toOpaque(), &eventHandler
        )
        guard status == noErr else { throw HotKeyRegistrationError(status: status) }
    }

    private static func carbonModifiers(_ modifiers: ShortcutModifiers) -> UInt32 {
        var result = 0
        if modifiers.contains(.command) { result |= cmdKey }
        if modifiers.contains(.shift) { result |= shiftKey }
        if modifiers.contains(.option) { result |= optionKey }
        if modifiers.contains(.control) { result |= controlKey }
        return UInt32(result)
    }
}

/// Carbon이 부르는 C 함수. 앱의 이벤트 대상에 건 처리기는 메인 스레드에서 불린다.
private nonisolated func hotKeyPressed(
    _ call: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKey = EventHotKeyID()
    let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
        MemoryLayout<EventHotKeyID>.size, nil, &hotKey
    )
    guard status == noErr else { return status }
    let id = hotKey.id
    // 포인터는 등록기 자신이다(`installEventHandlerIfNeeded`). 주소 값으로 넘겨 메인에서 되찾는다.
    let address = UInt(bitPattern: userData)
    MainActor.assumeIsolated {
        guard let pointer = UnsafeRawPointer(bitPattern: address) else { return }
        Unmanaged<CarbonHotKeyRegistrar>.fromOpaque(pointer).takeUnretainedValue().fire(id)
    }
    return noErr
}
