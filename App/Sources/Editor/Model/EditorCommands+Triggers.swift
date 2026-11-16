import Foundation

// 줄 맨 앞(글자가 보이기 시작하는 자리)에 기호를 치면 그 줄의 종류가 바뀐다(D-036).
// 빈 줄, 글이 있는 줄, 이미 다른 종류인 줄 모두에서 된다. 바뀐 뒤에는 기호가 보이지 않는다.

nonisolated extension EditorCommands {
    private static let spaceTriggers: [(text: String, kind: LineKind)] = [
        ("###", .heading(3)), ("##", .heading(2)), ("#", .heading(1)),
        ("[]", .todo(done: false)), ("-", .bullet), ("*", .bullet), (">", .toggle),
    ]

    /// Space를 치기 직전. 커서 앞이 줄 맨 앞에 친 `#`, `##`, `###`, `-`, `[]`, `>`이면 그 기호를 지우고
    /// 줄 머리를 바꾼다. 들여쓰기와 글은 그대로다. 이미 그 종류인 줄에서는 `nil`(공백을 그대로 넣는다).
    static func spaceTrigger(_ doc: MarkdownDocument, selection: NSRange) -> TextEdit? {
        guard selection.length == 0 else { return nil }
        let position = selection.location
        let line = doc.line(at: position)
        guard !line.kind.isCode, position >= line.contentStart else { return nil }
        for trigger in spaceTriggers {
            let length = trigger.text.utf16.count
            let start = position - length
            guard start >= line.contentStart, line.isVisualStart(start),
                  doc.string(in: NSRange(location: start, length: length)) == trigger.text else { continue }
            guard !isSameBlock(line.kind, trigger.kind) else { return nil }
            let marker = marker(for: trigger.kind, replacing: line, in: doc)
            // 기호 앞에 감춘 여는 기호가 있었으면(줄 맨 앞이 서식 구간) 그대로 둔다.
            let kept = doc.string(in: NSRange(location: line.contentStart, length: start - line.contentStart))
            let from = line.start + line.indentLength
            return TextEdit(
                range: NSRange(location: from, length: position - from),
                replacement: marker + kept,
                selection: NSRange(location: from + marker.utf16.count + kept.utf16.count, length: 0),
                preservesLines: true
            )
        }
        return nil
    }

    private static func isSameBlock(_ current: LineKind, _ target: LineKind) -> Bool {
        switch (current, target) {
        case (.todo, .todo): true
        default: current == target
        }
    }

    private static func marker(for kind: LineKind, replacing line: MarkdownLine, in doc: MarkdownDocument) -> String {
        switch kind {
        case .heading(let level): return String(repeating: "#", count: level) + " "
        case .bullet: return "- "
        case .toggle: return "> "
        case .todo:
            // 표준 문법의 글머리표(`- `)에서 바꾸면 그 꼴(`- [ ] `)을 지킨다(D-017).
            let old = doc.string(in: line.markerRange)
            return line.kind == .bullet ? String(old.prefix(2)) + "[ ] " : "[ ] "
        default: return ""
        }
    }

    /// 백틱을 치기 직전. 줄 맨 앞에 백틱 둘이 있으면(세 번째 백틱) 그 줄을 코드 블록으로 바꾼다:
    /// 여는 줄, 그 줄의 글(없으면 빈 줄), 닫는 줄. 커서는 블록 안에 놓인다.
    ///
    /// 세 번째 백틱에서 곧바로 바꾸는 까닭: ``` 만 있는 줄이 원문에 잠깐이라도 생기면 그 아래의
    /// ``` 줄들이 모두 새로 짝지어져, 코드와 글이 뒤집혀 보인다.
    static func codeBlockTrigger(_ doc: MarkdownDocument, selection: NSRange) -> TextEdit? {
        guard selection.length == 0 else { return nil }
        let position = selection.location
        let line = doc.line(at: position)
        guard !line.kind.isCode, position == line.contentStart + 2,
              doc.string(in: NSRange(location: line.contentStart, length: 2)) == "``" else { return nil }
        let indent = doc.string(in: line.indentRange)
        let rest = doc.string(in: NSRange(location: position, length: line.end - position))
        let head = indent + "```\n" + indent
        return TextEdit(
            range: line.range,
            replacement: head + rest + "\n" + indent + "```",
            selection: NSRange(location: line.start + head.utf16.count, length: 0)
        )
    }
}
