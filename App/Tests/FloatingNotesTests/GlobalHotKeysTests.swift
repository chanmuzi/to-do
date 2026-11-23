import Routing
import Testing
@testable import FloatingNotes

/// 전역 단축키 등록과 실패 보고. 시스템에 등록하지 않고 가짜 등록기로 본다.
@Suite struct GlobalHotKeysTests {
    /// 등록을 받아 적어 두는 가짜. `taken`에 든 키는 다른 앱이 쓰는 것처럼 거절한다.
    private final class FakeRegistrar: HotKeyRegistering {
        var taken: Set<KeyChord> = []
        var failingStatus: [KeyChord: Int32] = [:]
        private(set) var handlers: [HotKeyToken: () -> Void] = [:]
        private(set) var chords: [HotKeyToken: KeyChord] = [:]
        private(set) var unregistered: [HotKeyToken] = []
        private var nextID: UInt32 = 1

        func register(
            _ chord: KeyChord, handler: @escaping () -> Void
        ) throws(HotKeyRegistrationError) -> HotKeyToken {
            if taken.contains(chord) {
                throw HotKeyRegistrationError(status: HotKeyRegistrationError.alreadyRegisteredStatus)
            }
            if let status = failingStatus[chord] { throw HotKeyRegistrationError(status: status) }
            let token = HotKeyToken(id: nextID)
            nextID += 1
            handlers[token] = handler
            chords[token] = chord
            return token
        }

        func unregister(_ token: HotKeyToken) {
            handlers[token] = nil
            chords[token] = nil
            unregistered.append(token)
        }

        func press(_ chord: KeyChord) {
            chords.first { $0.value == chord }.flatMap { handlers[$0.key] }?()
        }
    }

    /// 여는 화면이 아직 이어지지 않은 동작의 키는 등록하지 않는다. 등록하면 그 키가 시스템 전체에서
    /// 다른 앱에 가지 않는데 이 앱은 기록만 한다.
    @Test func onlyCommandsWithAConnectedScreenAreRegistered() {
        let registrar = FakeRegistrar()
        var performed: [AppCommand] = []
        let hotKeys = GlobalHotKeys(registrar: registrar) { performed.append($0) }

        let failures = hotKeys.register(.standard)

        #expect(failures.isEmpty)
        // 빠른 캡처, 노트 모두 숨기기, 라이브러리만 전역 키를 등록한다.
        #expect(hotKeys.registered == [
            .quickCapture: KeyChord(.n, [.control, .option]),
            .toggleNotesHidden: KeyChord(.h, [.control, .option]),
            .library: KeyChord(.l, [.control, .option]),
        ])
        #expect(hotKeys.skipped == [.requestAgent])
        #expect(Set(registrar.chords.values) == [KeyChord(.n, [.control, .option]), KeyChord(.h, [.control, .option]), KeyChord(.l, [.control, .option])])
        registrar.press(KeyChord(.n, [.control, .option]))
        registrar.press(KeyChord(.l, [.control, .option]))
        registrar.press(KeyChord(.h, [.control, .option]))
        #expect(performed == [.quickCapture, .library, .toggleNotesHidden])
    }

    /// 등록할지는 요청이 이어져 있는지 하나로 정해진다(`Route.isConnected`). 그 값을 바꾸면 따라온다.
    @Test func availabilityFollowsTheConnectedRoutes() {
        #expect(Route.toggleAllNotesHidden.isConnected && AppCommand.toggleNotesHidden.isConnected)
        #expect(AppCommand.quickCapture.isConnected == Route.openCapture.isConnected)
        #expect(AppCommand.library.isConnected == Route.openLibrary.isConnected)
        #expect(AppCommand.requestAgent.isConnected == Route.requestAgent.isConnected)
        #expect(AppCommand.findNote.isConnected == Route.openBrowse(anchor: nil).isConnected)
        // 라이브러리를 열 수 있으며 전역 요청 막대는 아직 연결 전이다.
        #expect(AppCommand.quickCapture.isConnected && AppCommand.findNote.isConnected)
        #expect(AppCommand.library.isConnected && !AppCommand.requestAgent.isConnected)

        // 화면이 이어진 뒤처럼 넘기면 그 키도 등록된다.
        let registrar = FakeRegistrar()
        let hotKeys = GlobalHotKeys(registrar: registrar, isAvailable: { $0 != .requestAgent }) { _ in }
        hotKeys.register(.standard)
        #expect(Set(hotKeys.registered.keys) == [.quickCapture, .toggleNotesHidden, .library])
        #expect(hotKeys.skipped == [.requestAgent])
    }

    @Test func registersTheFourGlobalRowsAndDispatchesTheirCommands() {
        let registrar = FakeRegistrar()
        var performed: [AppCommand] = []
        let hotKeys = GlobalHotKeys(registrar: registrar, isAvailable: { _ in true }) { performed.append($0) }

        let failures = hotKeys.register(.standard)

        #expect(failures.isEmpty)
        #expect(hotKeys.registered == [
            .quickCapture: KeyChord(.n, [.control, .option]),
            .toggleNotesHidden: KeyChord(.h, [.control, .option]),
            .library: KeyChord(.l, [.control, .option]),
            .requestAgent: KeyChord(.a, [.control, .option]),
        ])
        registrar.press(KeyChord(.h, [.control, .option]))
        registrar.press(KeyChord(.n, [.control, .option]))
        #expect(performed == [.toggleNotesHidden, .quickCapture])
    }

    /// 다른 앱이 쓰는 키는 등록되지 않는다. 조용히 넘어가지 않고 어느 키가 왜 안 됐는지 남기며, 나머지는 등록한다.
    @Test func aKeyTakenByAnotherAppIsReportedAndTheRestStillRegister() {
        let registrar = FakeRegistrar()
        registrar.taken = [KeyChord(.n, [.control, .option])]
        registrar.failingStatus = [KeyChord(.a, [.control, .option]): -50]
        let hotKeys = GlobalHotKeys(registrar: registrar, isAvailable: { _ in true }) { _ in }

        let failures = hotKeys.register(.standard)

        #expect(failures.map(\.command) == [.quickCapture, .requestAgent])
        #expect(failures[0].error.isTakenByAnotherApp)
        #expect(failures[0].warning == "전역 단축키 ⌃⌥N (빠른 캡처)를 등록하지 못했습니다: 다른 앱이 이미 쓰는 키입니다")
        #expect(!failures[1].error.isTakenByAnotherApp)
        #expect(failures[1].warning.contains("-50"))
        #expect(hotKeys.failures == failures)
        #expect(Set(hotKeys.registered.keys) == [.toggleNotesHidden, .library])
    }

    /// 키를 바꾼 표로 다시 등록하면 옛 등록을 풀고 새 키로 건다(설정에서 다른 키를 고를 때).
    @Test func registeringAgainReplacesTheOldRegistrations() {
        let registrar = FakeRegistrar()
        registrar.taken = [KeyChord(.n, [.control, .option])]
        var performed: [AppCommand] = []
        let hotKeys = GlobalHotKeys(registrar: registrar, isAvailable: { _ in true }) { performed.append($0) }
        hotKeys.register(.standard)
        let replacement = KeyChord(.k, [.control, .option])

        let failures = hotKeys.register(ShortcutTable.standard.replacing(.quickCapture, with: replacement))

        #expect(failures.isEmpty)
        #expect(registrar.unregistered.count == 3)
        #expect(registrar.chords.count == 4)
        registrar.press(replacement)
        #expect(performed == [.quickCapture])
    }
}
