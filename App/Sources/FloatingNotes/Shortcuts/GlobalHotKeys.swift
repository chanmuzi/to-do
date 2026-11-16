/// "어디서나" 쓰는 단축키(spec 13)를 표에서 읽어 등록하고, 등록하지 못한 것을 적어 둔다.
/// 등록 실패(다른 앱이 쓰는 키)는 숨기지 않는다. App이 켤 때 경고로 남기고, 설정 화면이 생기면
/// `failures`로 그 자리에서 알려 다른 키를 고르게 한다.
final class GlobalHotKeys {
    struct Failure: Hashable {
        let command: AppCommand
        let action: String
        let chord: KeyChord
        let error: HotKeyRegistrationError

        /// 기록에 남기는 한 줄.
        var warning: String {
            "전역 단축키 \(chord.labels.joined()) (\(action))를 등록하지 못했습니다: \(error)"
        }
    }

    private let registrar: any HotKeyRegistering
    private let perform: (AppCommand) -> Void
    private var tokens: [AppCommand: HotKeyToken] = [:]
    /// 등록된 동작과 그 키.
    private(set) var registered: [AppCommand: KeyChord] = [:]
    private(set) var failures: [Failure] = []

    init(registrar: any HotKeyRegistering, perform: @escaping (AppCommand) -> Void) {
        self.registrar = registrar
        self.perform = perform
    }

    isolated deinit {
        tokens.values.forEach(registrar.unregister)
    }

    /// 표의 "어디서나" 줄을 등록한다. 이미 등록한 것은 먼저 푼다(키를 바꾼 뒤 다시 부를 수 있다).
    /// - Returns: 등록하지 못한 것. 하나가 실패해도 나머지는 등록한다.
    @discardableResult
    func register(_ table: ShortcutTable) -> [Failure] {
        tokens.values.forEach(registrar.unregister)
        tokens = [:]
        registered = [:]
        failures = []
        for entry in table.entries(in: .global) {
            guard let command = entry.command, let chord = entry.chords.first else { continue }
            do {
                let perform = perform
                tokens[command] = try registrar.register(chord) { perform(command) }
                registered[command] = chord
            } catch {
                failures.append(Failure(command: command, action: entry.action, chord: chord, error: error))
            }
        }
        return failures
    }
}
