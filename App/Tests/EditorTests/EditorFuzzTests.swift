import AppKit
import Testing
@testable import Editor

/// 씨앗을 정해 둔 무작위 입력. 무엇을 눌러도 지켜져야 하는 것을 확인한다:
/// ``` 줄의 짝, 커서가 감춘 기호 안에 놓이지 않음, 편집이 짝 잃은 기호를 만들지 않음, 모두 되돌리면 처음 글.
@MainActor
@Suite struct EditorFuzzTests {
    /// 같은 씨앗이면 같은 차례가 나오는 난수(SplitMix64).
    struct Generator {
        var state: UInt64

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }

        mutating func below(_ bound: Int) -> Int { Int(next() % UInt64(bound)) }
        mutating func pick<T>(_ items: [T]) -> T { items[below(items.count)] }
    }

    typealias Key = EditorShortcuts.Key

    static let documents = [
        "",
        "첫 줄\n**굵게** 그리고 ~~취소~~ 끝\n- 항목 하나\n- [ ] 할 일\n",
        "# 제목\n본문 ==형광== 과 `코드` 와 [링크](https://a.example) 끝\n+ 토글\n\t안쪽 줄\n꼬리",
        "앞\n```swift\nlet a = 1\nlet b = 2\n```\n뒤 **굵게**\n",
        "==**겹친** 서식=={2} 뒤\n\t- 들여 쓴 항목\n```\n코드\n```",
    ]

    static let moves: [Selector] = [
        #selector(NSResponder.moveLeft(_:)), #selector(NSResponder.moveRight(_:)),
        #selector(NSResponder.moveUp(_:)), #selector(NSResponder.moveDown(_:)),
        #selector(NSResponder.moveToBeginningOfLine(_:)), #selector(NSResponder.moveToEndOfLine(_:)),
        #selector(NSResponder.moveWordLeft(_:)), #selector(NSResponder.moveWordRight(_:)),
        #selector(NSResponder.moveLeftAndModifySelection(_:)), #selector(NSResponder.moveRightAndModifySelection(_:)),
        #selector(NSResponder.moveUpAndModifySelection(_:)), #selector(NSResponder.moveDownAndModifySelection(_:)),
        #selector(NSResponder.moveToBeginningOfLineAndModifySelection(_:)),
        #selector(NSResponder.moveToEndOfLineAndModifySelection(_:)),
        #selector(NSResponder.moveWordRightAndModifySelection(_:)),
    ]

    static let deletes: [Selector] = [
        #selector(NSResponder.deleteBackward(_:)), #selector(NSResponder.deleteBackward(_:)),
        #selector(NSResponder.deleteForward(_:)), #selector(NSResponder.deleteWordBackward(_:)),
        #selector(NSResponder.deleteToBeginningOfLine(_:)), #selector(NSResponder.deleteToEndOfLine(_:)),
        #selector(NSResponder.transpose(_:)),
    ]

    static let actions: [EditorAction] = [
        .bold, .strikethrough, .highlight, .inlineCode, .codeBlock, .indent, .outdent, .toggleTodo, .toggleDone,
        .moveLineUp, .moveLineDown, .heading(1), .heading(2),
    ]

    static let plainText = ["가", "나", "다", "a", "b", " ", " ", "1"]
    static let wildText = plainText + ["*", "*", "`", "`", "=", "~", "[", "]", "(", ")", "\\", "#", "-", ">", "{", "2", "}"]
    static let plainPastes = ["붙인 글", "**굵은 글**", "==형광==", "`코드`", "두 줄\n글", "- 항목\n- 둘", "[링크](https://b.example)"]
    static let wildPastes = plainPastes + ["```\n코드\n```", "```", "```js\nx", "** 떨어진 **", "a == b", "끝 ```"]

    /// 한 걸음. 한 일을 글자로 돌려준다(실패했을 때 되짚을 수 있게).
    static func step(_ h: EditorHarness, _ random: inout Generator, wild: Bool) -> String {
        switch random.below(100) {
        case 0..<34:
            let text = random.pick(wild ? Self.wildText : Self.plainText)
            h.type(text)
            return "type(\(text.debugDescription))"
        case 34..<50:
            let selector = random.pick(Self.moves)
            h.press(selector)
            return "\(selector)"
        case 50..<62:
            let selector = random.pick(Self.deletes)
            h.press(selector)
            return "\(selector)"
        case 62..<70:
            h.press(NSResponder.newline)
            return "newline"
        case 70..<82:
            let action = random.pick(Self.actions)
            // 선택 없이 누른 서식 단축키는 원문을 고치지 않는다. 되돌리기 묶음을 열지 않는다.
            if h.editor.selectedRange.length == 0 { h.editor.perform(action) } else { h.perform(action) }
            return "perform(\(action))"
        case 82..<88:
            let text = random.pick(wild ? Self.wildPastes : Self.plainPastes)
            h.paste(text)
            return "paste(\(text.debugDescription))"
        case 88..<91:
            h.press(random.below(2) == 0 ? NSResponder.tab : NSResponder.backtab)
            return "tab"
        case 91..<93:
            h.step { h.view.selectAll(nil) }
            return "selectAll"
        case 93..<97:
            h.undo()
            return "undo"
        default:
            h.redo()
            return "redo"
        }
    }

    /// 화면에 보이는 글자(감춘 기호와 백슬래시를 뺀 것). 인라인 코드 안의 글은 뺀다(그 안에서는 기호도 글자다).
    private func visibleText(of line: MarkdownLine, in doc: MarkdownDocument) -> String {
        var units: [unichar] = []
        let hidden = line.markers.map(\.range) + line.spans.filter { $0.kind == .code }.map(\.range)
        for position in line.contentStart..<line.end where !hidden.contains(where: { NSLocationInRange(position, $0) }) {
            units.append(doc.units[position])
        }
        return String(utf16CodeUnits: units, count: units.count)
    }

    private func caretProblem(_ h: EditorHarness) -> String? {
        let doc = h.document
        let selection = h.editor.selectedRange
        for position in Set([selection.location, NSMaxRange(selection)]) {
            let index = doc.lineIndex(at: position)
            let line = doc.lines[index]
            if line.kind == .fenceOpen || line.kind == .fenceClose {
                if selection.length == 0, EditorCommands.emptyBlock(doc, caretAt: position) == nil { return "``` 줄 위의 커서 \(position)" }
                continue
            }
            if line.kind == .code { continue }
            if selection.length == 0, position < line.caretStart { return "줄 머리 안의 커서 \(position)" }
            guard position >= line.contentStart else { continue }
            if line.marker(enclosing: position) != nil { return "기호 한가운데의 커서 \(position)" }
            if selection.length == 0, line.escape(splitAt: position) != nil { return "백슬래시와 글자 사이의 커서 \(position)" }
        }
        return nil
    }

    private func run(
        seed: UInt64, sequences: Int, steps: Int, wild: Bool, honoursEnvironment: Bool = true,
        documents: [String] = EditorFuzzTests.documents
    ) throws {
        // 더 많이 돌릴 때: EDITOR_FUZZ_SEED(씨앗에 더할 값), EDITOR_FUZZ_SEQUENCES(씨앗마다의 차례 수).
        let environment = honoursEnvironment ? ProcessInfo.processInfo.environment : [:]
        let seed = seed &+ (environment["EDITOR_FUZZ_SEED"].flatMap(UInt64.init) ?? 0)
        let sequences = environment["EDITOR_FUZZ_SEQUENCES"].flatMap(Int.init) ?? sequences
        var random = Generator(state: seed)
        for sequence in 0..<sequences {
            let original = random.pick(documents)
            let h = try EditorHarness(original)
            h.caret(at: random.below(h.document.length + 1))
            var log: [String] = []
            // 코드 블록 안에서는 기호도 글자다. 거기에 넣은 글은 블록을 풀면 다시 Markdown으로 읽히므로
            // (감싸고 풀면 원래대로 돌아와야 한다), 그런 차례에서는 "짝 잃은 기호" 확인을 그만둔다.
            var typedInCode = false
            // 실패한 차례를 되짚을 때: FUZZ_TRACE=씨앗:차례 로 걸음마다의 원문을 찍는다.
            let traces = ProcessInfo.processInfo.environment["FUZZ_TRACE"] == "\(seed):\(sequence)"
            if traces { print("TRACE start \(h.marked.debugDescription)") }
            for _ in 0..<steps {
                if h.document.line(at: h.editor.selectedRange.location).kind.isCode
                    || h.document.line(at: NSMaxRange(h.editor.selectedRange)).kind.isCode { typedInCode = true }
                log.append(Self.step(h, &random, wild: wild))
                if traces { print("TRACE \(log.last ?? "") → \(h.marked.debugDescription)") }
                let context = "seed \(seed) #\(sequence) \(log.suffix(12).joined(separator: ", ")) → \(h.marked.debugDescription)"
                let doc = h.document
                guard h.view.string == h.editor.text else {
                    Issue.record("화면과 원문이 다르다: \(context)")
                    return
                }
                guard !EditorCommands.hasUnterminatedFence(doc) else {
                    Issue.record("``` 줄이 짝을 잃었다: \(context)")
                    return
                }
                if let problem = caretProblem(h) {
                    Issue.record("\(problem): \(context)")
                    return
                }
                if !wild, !typedInCode {
                    for line in doc.lines where !line.kind.isCode {
                        let visible = visibleText(of: line, in: doc)
                        guard !["**", "~~", "==", "`", "](", "\\"].contains(where: visible.contains) else {
                            Issue.record("짝 잃은 기호가 보인다 \(visible.debugDescription): \(context)")
                            return
                        }
                    }
                }
            }
            // 모두 되돌리면 처음 글이다.
            var guardCount = 0
            while h.editor.undoManager.canUndo, guardCount < 10_000 {
                h.undo()
                guardCount += 1
            }
            guard h.editor.text == original else {
                Issue.record("모두 되돌려도 처음 글이 아니다: seed \(seed) #\(sequence) \(h.editor.text.debugDescription) ≠ \(original.debugDescription)")
                return
            }
        }
    }

    /// 글자와 명령만 쓰는 입력(기호 글자는 치지 않는다): 짝 잃은 기호가 화면에 드러나지 않는다.
    @Test(arguments: [1, 2, 3, 4] as [UInt64])
    func commandsAndPlainTypingKeepTheSourceWellFormed(seed: UInt64) throws {
        try run(seed: seed, sequences: 12, steps: 50, wild: false)
    }

    /// 기호 글자와 ``` 가 든 글까지 섞은 입력: ``` 줄의 짝과 커서 자리, 되돌리기가 지켜진다.
    @Test(arguments: [11, 12, 13, 14] as [UInt64])
    func arbitraryTypingKeepsFencesBalancedAndUndoExact(seed: UInt64) throws {
        try run(seed: seed, sequences: 12, steps: 50, wild: true)
    }

    /// 인용문과 여러 단계의 목록, 부모 없는 들여쓰기가 든 글: 부모를 잃는 하위 줄을 함께 내어 쓰는 편집(D-043)과
    /// 인용문(D-044)에서도 같은 것이 지켜진다.
    @Test(arguments: [21, 22, 23, 24] as [UInt64])
    func quotesAndNestedListsKeepTheSourceWellFormed(seed: UInt64) throws {
        let documents = [
            "> 인용 **굵게**\n> 둘째 ==형광==\n본문\n- 부모\n\t- 하위\n\t\t[ ] 할 일\n\t- 둘째\n끝",
            "+ 토글\n\t> 안쪽 인용\n\t- 항목\n\t\t- 깊은 항목\n본문\n\t\t\t부모 없는 줄\n> 꼬리",
            "- a\n\t+ T\n\t\t안쪽\n\t\t\t- 더 안쪽\n- b\n```\n코드\n```\n> 끝",
        ]
        try run(seed: seed, sequences: 12, steps: 50, wild: true, documents: documents)
    }

    /// 이슈 #9의 회귀 확인은 씨앗 417(`EDITOR_FUZZ_SEED=404`를 기본 씨앗 13에 더한 것)뿐이다. 108번째 차례에서
    /// 줄 머리 안에 커서를 남겼다(줄 종류를 바꾼 뒤 ⇧←).
    /// `312`를 더한 여덟 씨앗은 회귀 확인이 아니다: 이슈 #9에서 실패했다고 적힌 씨앗이지만 어느 기본 씨앗이었는지
    /// 남아 있지 않고, 지금 코드에서는 옛 실패를 다시 내지 않는다. 다른 씨앗처럼 같은 것이
    /// 지켜지는지 보는 보통 씨앗으로 둔다.
    @Test(arguments: [
        (13 + 404, 110, true),
        (11 + 312, 45, true), (12 + 312, 45, true), (13 + 312, 45, true), (14 + 312, 45, true),
        (1 + 312, 45, false), (2 + 312, 45, false), (3 + 312, 45, false), (4 + 312, 45, false),
    ] as [(UInt64, Int, Bool)])
    func issue9SeedAndExtraSeedsKeepTheCaretOutOfLinePrefixes(seed: UInt64, sequences: Int, wild: Bool) throws {
        try run(seed: seed, sequences: sequences, steps: 50, wild: wild, honoursEnvironment: false)
    }
}
