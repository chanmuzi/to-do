import Foundation

// 줄 맨 앞(글자가 보이기 시작하는 자리)에 기호를 치면 그 줄의 종류가 바뀐다(D-036).
// 빈 줄, 글이 있는 줄, 이미 다른 종류인 줄 모두에서 된다. 바뀐 뒤에는 기호가 보이지 않는다.

nonisolated extension EditorCommands {
    private static let spaceTriggers: [(text: String, kind: LineKind)] = [
        ("###", .heading(3)), ("##", .heading(2)), ("#", .heading(1)),
        // `[ ]`, `- [ ]`도 받는다(이미 글머리표인 줄에서 `- [ ]`를 쳐도 투두가 된다). 긴 것부터 견준다.
        ("- [ ]", .todo(done: false)), ("- []", .todo(done: false)), ("* [ ]", .todo(done: false)),
        ("[ ]", .todo(done: false)), ("[]", .todo(done: false)),
        ("-", .bullet), ("*", .bullet), (">", .toggle),
        // 인용문은 `"`나 `|`로 친다(`>`는 토글이다). 원문은 표준의 `> `다(D-044).
        ("\"", .quote), ("|", .quote),
    ]

    /// Space를 치기 직전. 커서 앞이 줄 맨 앞에 친 `#`, `##`, `###`, `-`, `[]`, `[ ]`, `- [ ]`, `>`, `"`, `|`이면 그 기호를 지우고
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
            let from = line.start + line.indentLength
            // 친 기호가 서식 구간의 글 전부였으면(⌘B 뒤에 `#`을 침) 그 구간의 기호도 함께 지운다.
            // 남겨 두면 빈 기호 쌍(`****`)이 글자로 드러난다.
            var typed = NSRange(location: start, length: length)
            while let span = line.markedSpans.first(where: { $0.contentRange == typed }) { typed = span.range }
            // 기호 앞에 감춘 여는 기호가 있었으면(줄 맨 앞이 서식 구간) 그대로 둔다.
            let kept = doc.string(in: NSRange(location: line.contentStart, length: typed.location - line.contentStart))
            return TextEdit(
                range: NSRange(location: from, length: NSMaxRange(typed) - from),
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
        case .toggle: return "+ "
        case .quote: return "> "
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
    ///
    /// 코드 블록 안에서는 백틱 둘만 있는 줄의 끝에서 친 세 번째 백틱이 블록에서 나가게 한다
    /// (`exitingCodeLine`). 그 밖의 자리에서는 `nil`이고 백틱은 글자로 들어간다.
    static func codeBlockTrigger(_ doc: MarkdownDocument, selection: NSRange) -> TextEdit? {
        guard selection.length == 0 else { return nil }
        let position = selection.location
        let index = doc.lineIndex(at: position)
        let line = doc.lines[index]
        if line.kind == .code {
            let typed = NSRange(location: line.start + line.indentLength, length: 2)
            // 백틱 둘의 앞, 사이, 뒤 어디에 쳐도 그 줄은 ``` 가 된다.
            guard NSLocationInRange(position, NSRange(location: typed.location, length: 3)),
                  NSMaxRange(typed) == line.end, doc.string(in: typed) == "``" else { return nil }
            // 친 백틱 둘을 지운 빈 줄에서 나간다.
            let erase = TextEdit(range: typed, replacement: "", selection: NSRange(location: typed.location, length: 0))
            let middle = MarkdownDocument(erase.applied(to: doc.text))
            guard let exit = exitingCodeLine(middle, lineIndex: index) else { return nil }
            return compose(erase, then: exit, middle: middle)
        }
        // 백틱 둘의 앞, 사이, 뒤 어디에 쳐도 줄 머리가 ``` 가 된다(세 번째 백틱).
        guard !line.kind.isCode, line.contentStart + 2 <= line.end,
              NSLocationInRange(position, NSRange(location: line.contentStart, length: 3)),
              doc.string(in: NSRange(location: line.contentStart, length: 2)) == "``" else { return nil }
        let indent = doc.string(in: line.indentRange)
        let rest = doc.string(in: NSRange(location: line.contentStart + 2, length: line.end - line.contentStart - 2))
        let head = indent + "```\n" + indent
        return TextEdit(
            range: line.range,
            replacement: head + rest + "\n" + indent + "```",
            selection: NSRange(location: line.start + head.utf16.count, length: 0)
        )
    }

    /// 코드 블록의 빈 줄에서 블록 밖으로 나가는 편집(그 줄에 백틱 셋을 쳤을 때).
    ///
    /// - 마지막 줄: Return과 같다. 그 줄을 지우고 블록 아래에 문단을 연다(닫히지 않은 블록은 닫는다).
    /// - 첫 줄: 그 줄을 지우고 블록 위에 문단을 연다.
    /// - 가운데 줄: 블록을 둘로 나누고 그 사이에 문단을 연다.
    /// - 줄이 하나뿐인 블록: 블록을 없애고 문단으로 둔다.
    static func exitingCodeLine(_ doc: MarkdownDocument, lineIndex index: Int) -> TextEdit? {
        let line = doc.lines[index]
        guard line.kind == .code, let block = line.codeBlock, line.end == line.start + line.indentLength else { return nil }
        let code = block.filter { doc.lines[$0].kind == .code }
        let open = doc.lines[block.lowerBound]
        let last = doc.lines[block.upperBound]
        let indent = doc.string(in: open.indentRange)
        if code.count == 1 {
            let end = last.kind == .fenceClose ? last.end : line.end
            return TextEdit(
                range: NSRange(location: open.start, length: end - open.start),
                replacement: indent,
                selection: NSRange(location: open.start + indent.utf16.count, length: 0)
            )
        }
        if index == code.last { return leavingCodeBlock(doc, lineIndex: index) }
        if index == code.first {
            return TextEdit(
                range: NSRange(location: open.start, length: NSMaxRange(line.fullRange) - open.start),
                replacement: indent + "\n" + doc.string(in: open.range) + "\n",
                selection: NSRange(location: open.start + indent.utf16.count, length: 0)
            )
        }
        let head = indent + "```\n" + indent
        return TextEdit(
            range: line.range,
            replacement: head + "\n" + indent + "```",
            selection: NSRange(location: line.start + head.utf16.count, length: 0)
        )
    }

    /// 언어 이름에 쓸 수 있는 글자인지(`swift`, `c++`, `objective-c`, `c#`).
    static func isLanguageTag(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || "_+-#.".unicodeScalars.contains(scalar))
        }
    }

    /// 세 번째 백틱으로 블록을 만든 바로 뒤에 낱말 하나를 치고 Return을 눌렀다. 그 낱말을 여는 줄의 언어
    /// 이름으로 옮긴다(` ```swift ` 를 치는 손의 움직임 그대로). 블록의 첫 줄이 친 낱말 그대로이고 커서가
    /// 그 끝에 있을 때만이다. 아는 언어 이름(`CodeLanguages`)만 옮긴다. 다른 낱말은 코드 줄로 남는다(`ls`,
    /// `main` 같은 한 낱말짜리 코드가 보이지 않는 이름이 되지 않게). 해당하지 않으면 `nil`.
    static func languageTag(_ doc: MarkdownDocument, selection: NSRange, openLine: Int, typed: String) -> TextEdit? {
        guard selection.length == 0, isLanguageTag(typed), CodeLanguages.isKnown(typed), openLine + 1 < doc.lines.count else { return nil }
        let open = doc.lines[openLine]
        let first = doc.lines[openLine + 1]
        guard open.kind == .fenceOpen, first.kind == .code, selection.location == first.end,
              open.end == open.start + open.indentLength + 3,
              doc.string(in: NSRange(location: first.start + first.indentLength, length: first.end - first.start - first.indentLength)) == typed
        else { return nil }
        let indent = doc.string(in: first.indentRange)
        return TextEdit(
            range: NSRange(location: open.end, length: first.end - open.end),
            replacement: typed + "\n" + indent,
            selection: NSRange(location: open.end + typed.utf16.count + 1 + indent.utf16.count, length: 0)
        )
    }
}
