/// 단축키 표의 구획(spec 13). 이름은 `tokens.json`의 `shortcuts[].group`과 같다.
nonisolated enum ShortcutGroup: String, Hashable, Sendable, CaseIterable {
    case global = "어디서나 (다른 앱을 쓰는 중에도. 모두 바꿀 수 있음)"
    case capture = "빠른 캡처 바"
    case agent = "에이전트"
    case noteWindow = "노트 창"
    case browse = "노트 찾기"
    case library = "라이브러리"
    case editing = "편집"
    case markdownInput = "마크다운으로 입력"
}

/// 단축키 표의 한 줄.
nonisolated struct ShortcutEntry: Hashable, Sendable {
    enum Keys: Hashable, Sendable {
        /// 누르는 키. 여럿이면 같은 보조 키에 키만 다른 것들이다(예: ⌃⌘↑, ⌃⌘↓).
        case chords([KeyChord])
        /// 키 조합이 아니라 입력하는 글자(마크다운으로 입력).
        case typed([String])
    }

    let group: ShortcutGroup
    /// 표에 적는 동작 이름. `tokens.json`의 `action`과 같다.
    let action: String
    var keys: Keys
    /// App이 받아서 하는 동작. `nil`이면 그 화면(편집기, 캡처 바, 노트 찾기)이 스스로 받는다.
    let command: AppCommand?

    var chords: [KeyChord] {
        if case .chords(let chords) = keys { chords } else { [] }
    }

    /// 표에 적는 키 모습(`tokens.json`의 `keys`와 같다). 보조 키를 한 번 적고 키를 차례로 잇는다.
    var keyLabels: [String] {
        switch keys {
        case .typed(let labels): return labels
        case .chords(let chords):
            if Set(chords.map(\.modifiers)).count > 1 {
                return [chords.map { $0.labels.joined() }.joined(separator: " / ")]
            }
            return (chords.first?.modifiers.labels ?? []) + chords.map(\.key.label)
        }
    }
}

/// 단축키 표(spec 13)의 정본. 메뉴의 키, 전역 단축키 등록, (뒤 단계의) 단축키 화면이 모두 이것을 읽는다.
/// `tokens.json`의 `shortcuts`와 줄마다 같아야 하고, 테스트가 견준다.
/// 사용자가 키를 바꾸는 설정이 생기면 `replacing(_:with:)`로 바꾼 표를 만들어 메뉴와 전역 단축키를 다시 만든다.
nonisolated struct ShortcutTable: Hashable, Sendable {
    var entries: [ShortcutEntry]

    func entries(in group: ShortcutGroup) -> [ShortcutEntry] {
        entries.filter { $0.group == group }
    }

    func entry(for command: AppCommand) -> ShortcutEntry? {
        entries.first { $0.command == command }
    }

    func chord(for command: AppCommand) -> KeyChord? {
        entry(for: command)?.chords.first
    }

    /// 그 동작의 키를 바꾼 표.
    func replacing(_ command: AppCommand, with chord: KeyChord) -> ShortcutTable {
        ShortcutTable(entries: entries.map { entry in
            guard entry.command == command else { return entry }
            var changed = entry
            changed.keys = .chords([chord])
            return changed
        })
    }

    static let standard = ShortcutTable(
        entries: global + capture + agent + noteWindow + browse + library + editing + markdownInput
    )

    private static func row(
        _ group: ShortcutGroup, _ action: String, _ keys: [ShortcutKey], _ modifiers: ShortcutModifiers = [],
        command: AppCommand? = nil
    ) -> ShortcutEntry {
        ShortcutEntry(
            group: group, action: action, keys: .chords(keys.map { KeyChord($0, modifiers) }), command: command
        )
    }

    private static let global: [ShortcutEntry] = [
        row(.global, "빠른 캡처", [.n], [.control, .option], command: .quickCapture),
        row(.global, "떠 있는 노트 모두 숨기기, 다시 보이기", [.h], [.control, .option], command: .toggleNotesHidden),
        row(.global, "라이브러리", [.l], [.control, .option], command: .library),
        row(.global, "에이전트에게 요청", [.a], [.control, .option], command: .requestAgent),
    ]

    private static let capture: [ShortcutEntry] = [
        row(.capture, "추가", [.returnKey]),
        row(.capture, "새 노트로 띄우기", [.returnKey], [.command]),
        row(.capture, "스페이스 바꾸기", [.tab]),
        row(.capture, "리마인더 직접 고르기", [.r], [.command]),
        row(.capture, "닫기", [.escape]),
    ]

    private static let agent: [ShortcutEntry] = [
        row(.agent, "요청을 보내고 대화 열기", [.returnKey]),
        row(.agent, "노트에서 에이전트 창 열기", [.j], .command, command: .openAgentWindow),
    ]

    private static let noteWindow: [ShortcutEntry] = [
        row(.noteWindow, "새 노트", [.n], [.command], command: .newNote),
        row(.noteWindow, "노트 찾기", [.p], [.command], command: .findNote),
        row(.noteWindow, "더 보기 메뉴", [.k], [.command], command: .moreMenu),
        row(.noteWindow, "다음 노트로", [.backtick], [.command], command: .nextNote),
        row(.noteWindow, "제목 고치기", [.t], [.shift, .command], command: .editTitle),
        row(.noteWindow, "항상 위에 고정 켜기, 끄기", [.p], [.shift, .command], command: .togglePin),
        row(.noteWindow, "리마인더 설정", [.r], [.command], command: .setReminder),
        row(.noteWindow, "스페이스 옮기기", [.m], [.shift, .command], command: .moveToSpace),
        row(.noteWindow, "노트 안에서 찾기", [.f], [.command], command: .findInNote),
        ShortcutEntry(group: .noteWindow, action: "본문 확대", keys: .chords([
            KeyChord(.equals, [.shift, .command]), KeyChord(.equals, .command)
        ]), command: .enlargeBody),
        row(.noteWindow, "본문 축소", [.minus], [.command], command: .reduceBody),
        row(.noteWindow, "본문 기본 크기", [.zero], [.command], command: .resetBodySize),
        row(.noteWindow, "전체 검색", [.f], [.shift, .command], command: .searchAll),
        row(.noteWindow, "창 닫기 (노트는 남음)", [.w], [.command], command: .closeWindow),
        row(.noteWindow, "설정", [.comma], [.command], command: .settings),
        row(.noteWindow, "이 단축키 표", [.slash], [.command], command: .shortcuts),
    ]

    private static let browse: [ShortcutEntry] = [
        row(.browse, "항목 이동", [.up, .down]),
        row(.browse, "열기", [.returnKey]),
        row(.browse, "닫기", [.escape]),
    ]

    private static let library: [ShortcutEntry] = [
        row(.library, "선택한 줄 열기", [.returnKey]),
        row(.library, "목록 선택 이동", [.up, .down]),
        ShortcutEntry(group: .library, action: "컨트롤 사이 이동", keys: .typed(["⇥", "/", "⇧⇥"]), command: nil),
    ]

    /// 편집기(`Editor` 모듈)가 스스로 받는 키. 여기서는 표에 보일 내용만 든다.
    private static let editing: [ShortcutEntry] = [
        row(.editing, "현재 줄 날짜 제안 받기", [.tab]),
        row(.editing, "날짜 제안만 닫기", [.escape]),
        row(.editing, "들여쓰기 (날짜 제안이 없을 때)", [.tab]),
        row(.editing, "내어쓰기 / 본문 처음에서 제목으로", [.tab], [.shift]),
        row(.editing, "투두로 바꾸기", [.nine], [.shift, .command]),
        row(.editing, "완료 표시", [.returnKey], [.command]),
        row(.editing, "줄 위로, 아래로 옮기기", [.up, .down], [.control, .command]),
        row(.editing, "접기, 펼치기", [.leftBracket, .rightBracket], [.option, .command]),
        row(.editing, "제목 1, 2, 3", [.one, .two, .three], [.option, .command]),
        row(.editing, "굵게", [.b], [.command]),
        row(.editing, "취소선", [.x], [.shift, .command]),
        row(.editing, "형광펜 (다시 누르면 다음 색)", [.h], [.shift, .command]),
        row(.editing, "인라인 코드", [.e], [.command]),
        row(.editing, "코드 블록", [.c], [.option, .command]),
        row(.editing, "링크", [.l], [.command]),
    ]

    private static func typed(_ action: String, _ labels: [String]) -> ShortcutEntry {
        ShortcutEntry(group: .markdownInput, action: action, keys: .typed(labels), command: nil)
    }

    private static let markdownInput: [ShortcutEntry] = [
        typed("제목 1, 2, 3", ["#", "##", "###"]),
        typed("글머리표", ["-"]),
        typed("투두", ["[]", "[ ]"]),
        typed("토글", [">"]),
        typed("인용문", ["\"", "|"]),
        typed("굵게", ["**글자**"]),
        typed("취소선", ["~~글자~~"]),
        typed("형광펜", ["==글자=="]),
        typed("인라인 코드", ["`글자`"]),
        typed("코드 블록", ["```"]),
    ]
}
