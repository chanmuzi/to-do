import Foundation

// 글자를 칠 때 그 자리에서 일어나는 일들: 닫는 기호를 쳐서 서식이 되는 순간, 링크 글자 안의 `]`,
// 구간 끝에서 친 공백, 글자 바꾸기(⌃T), 붙여 넣을 글 다듬기.

nonisolated extension EditorCommands {
    /// 닫는 기호의 마지막 글자를 쳐서 그 자리에서 서식이 되는 입력. 두 번의 편집으로 넣는다:
    /// 먼저 친 기호를 백슬래시로 막은 글자로(`literal`), 이어서 서식으로(`formatted`). 그래서 바로 되돌리면
    /// 친 글자가 글자 그대로 남고(다시 서식이 되지 않는다), 한 번 더 되돌리면 마지막에 친 글자가 지워진다.
    struct Conversion: Equatable, Sendable {
        var literal: TextEdit
        var formatted: TextEdit
    }

    private static let closers: Set<Character> = ["*", "~", "=", "`", ")"]

    static func conversion(_ doc: MarkdownDocument, typing text: String, at position: Int) -> Conversion? {
        guard text.count == 1, let character = text.first, closers.contains(character) else { return nil }
        let line = doc.line(at: position)
        guard !line.kind.isCode, position >= line.contentStart else { return nil }
        let local = position - line.start
        let newText = (doc.string(in: line.range) as NSString).replacingCharacters(in: NSRange(location: local, length: 0), with: text)
        let parsed = MarkdownDocument(newText)
        guard parsed.lines.count == 1, let newLine = parsed.lines.first, newLine.kind == line.kind else { return nil }
        // 방금 친 글자로 닫힌 구간(여럿이면 가장 바깥).
        guard let span = newLine.markedSpans.filter({ NSMaxRange($0.range) == local + 1 && $0.closeMarker.length > 0 })
            .max(by: { $0.range.length < $1.range.length }) else { return nil }
        // 이미 그 서식이던 구간(형광펜의 색 번호를 고쳐 치는 경우 등)은 새로 바뀐 것이 아니다.
        let existed = line.markedSpans.contains { old in
            old.range.location - line.start == span.range.location && sameFormat(old.kind, span.kind)
        }
        guard !existed else { return nil }

        let source = newText as NSString
        let open = source.substring(with: span.openMarker)
        let close = source.substring(with: span.closeMarker)
        let content = source.substring(with: span.contentRange)
        let literalClose: String
        if case .link = span.kind {
            // 주소는 그대로 두고 `]`만 막는다.
            literalClose = "\\]" + close.dropFirst()
        } else {
            literalClose = escaped(close)
        }
        let literalText = escaped(open) + content + literalClose
        let start = line.start + span.range.location
        let literal = TextEdit(
            range: NSRange(location: start, length: span.range.length - 1),
            replacement: literalText,
            selection: NSRange(location: start + literalText.utf16.count, length: 0)
        )
        let formatted = TextEdit(
            range: NSRange(location: start, length: literalText.utf16.count),
            replacement: source.substring(with: span.range),
            selection: NSRange(location: start + span.range.length, length: 0)
        )
        return Conversion(literal: literal, formatted: formatted)
    }

    private static func sameFormat(_ a: InlineSpan.Kind, _ b: InlineSpan.Kind) -> Bool {
        switch (a, b) {
        case (.bold, .bold), (.strike, .strike), (.code, .code), (.highlight, .highlight), (.link, .link): true
        default: false
        }
    }

    /// 그 위치가 링크 글자(`[글자](주소)`의 글자) 안인지. 거기서 친 `]`는 백슬래시로 막아 넣는다
    /// (그대로 넣으면 링크가 그 자리에서 끝나 나머지가 글자로 드러난다).
    static func isInsideLinkText(_ doc: MarkdownDocument, at position: Int) -> Bool {
        let line = doc.line(at: position)
        guard !line.kind.isCode else { return false }
        return line.markedSpans.contains { span in
            guard case .link = span.kind else { return false }
            return span.contentRange.location <= position && position <= NSMaxRange(span.contentRange)
                && !line.markedSpans.contains { $0.kind == .code && $0.contentRange.location <= position && position <= NSMaxRange($0.contentRange) }
        }
    }

    /// 서식 구간의 끝에서 친 공백은 기호 밖에 놓인다(`**가** |`). 이어서 글자를 치면 그 공백과 글자를 구간
    /// 안으로 들인다(`**가 나|**`): 구간의 끝에서 이어 치는 글은 서식이 이어진다.
    /// - Parameters:
    ///   - closeStart: 닫는 기호들이 시작하는 자리.
    ///   - caret: 공백 뒤의 커서.
    static func absorbingIntoRun(_ doc: MarkdownDocument, closeStart: Int, caret: Int, text: String) -> TextEdit? {
        guard closeStart < caret, caret <= doc.length, !text.contains("\n") else { return nil }
        let line = doc.line(at: caret)
        guard closeStart >= line.contentStart else { return nil }
        var spaceStart = caret
        while spaceStart > closeStart, InlineParser.isWhitespace(doc.units[spaceStart - 1]) { spaceStart -= 1 }
        guard spaceStart > closeStart, spaceStart < caret, line.isHiddenOnly(from: closeStart, to: spaceStart) else { return nil }
        let closes = doc.string(in: NSRange(location: closeStart, length: spaceStart - closeStart))
        let space = doc.string(in: NSRange(location: spaceStart, length: caret - spaceStart))
        let edit = TextEdit(
            range: NSRange(location: closeStart, length: caret - closeStart),
            replacement: space + text + closes,
            selection: NSRange(location: closeStart + space.utf16.count + text.utf16.count, length: 0)
        )
        return edit
    }

    /// ⌃T(앞뒤 글자 바꾸기). 보이는 글자 둘을 바꾼다. 둘 사이나 둘 안에 감춘 기호가 있으면 하지 않는다
    /// (기호의 글자와 자리를 바꾸면 기호가 깨진다).
    static func transpose(_ doc: MarkdownDocument, selection: NSRange) -> KeyOutcome {
        guard selection.length == 0 else { return .ignore }
        let line = doc.line(at: selection.location)
        if line.kind == .code { return .passThrough }
        guard !line.kind.isCode, selection.location >= line.contentStart else { return .ignore }
        // 줄 끝(닫는 기호 앞 포함)에서는 앞의 두 글자를 바꾼다.
        var middle = selection.location
        if line.isVisualEnd(middle) {
            middle = line.visualStart(from: middle)
            guard middle > line.contentStart else { return .ignore }
            middle = doc.characterRange(before: middle).location
        }
        guard middle > line.contentStart, middle < line.end else { return .ignore }
        let first = doc.characterRange(before: middle)
        let second = doc.characterRange(at: middle)
        let both = NSUnionRange(first, second)
        guard first.location >= line.contentStart, NSMaxRange(second) <= line.end else { return .ignore }
        let blocked = line.hiddenSpans.contains { span in
            if span.kind == .escape { return NSIntersectionRange(span.range, both).length > 0 }
            return [span.openMarker, span.closeMarker].contains { marker in
                marker.length > 0 && marker.location < NSMaxRange(both) && NSMaxRange(marker) > both.location
            }
        }
        guard !blocked else { return .ignore }
        return .edit(TextEdit(
            range: both,
            replacement: doc.string(in: second) + doc.string(in: first),
            selection: NSRange(location: NSMaxRange(both), length: 0)
        ))
    }

    // MARK: 붙여넣기

    /// 붙여 넣을 글을 그 자리에 맞게 다듬는다.
    ///
    /// - 같은 서식의 구간 안에 붙이면 그 서식의 기호를 벗긴다(`**a|b**`에 `**글**`을 붙이면 `**a글b**`).
    ///   그대로 넣으면 기호가 엇갈려 서식이 뒤집힌다. 링크 글자 안에서는 붙이는 글의 링크 문법도 벗긴다.
    /// - 코드 블록(``` 줄)이 든 글은 블록이 제 줄에 놓이도록 앞뒤에 줄바꿈을 넣고, 닫는 줄이 없으면 넣는다.
    /// - 코드 블록 안에 붙이면 ``` 줄은 빼고 그 안의 글만 넣는다.
    /// - Parameter runEnd: 구간 끝에서 친 공백 뒤에 붙이는 것이면(이어 넣는 글이 그 구간에 붙는다) 그 구간의
    ///   닫는 기호가 시작하는 자리.
    static func preparedForPaste(_ doc: MarkdownDocument, _ text: String, replacing selection: NSRange, runEnd: Int? = nil) -> String {
        let line = doc.line(at: selection.location)
        let fragment = MarkdownDocument(text)
        let hasFence = fragment.lines.contains { $0.kind == .fenceOpen }
        if line.kind.isCode {
            guard hasFence else { return text }
            return fragment.lines.filter { $0.kind != .fenceOpen && $0.kind != .fenceClose }
                .map { fragment.string(in: $0.range) }.joined(separator: "\n")
        }
        var result = text
        let containing = selection.location >= line.contentStart ? line.spansContaining(runEnd ?? selection.location) : []
        if !containing.isEmpty, !hasFence {
            let insideCode = containing.contains { $0.kind == .code }
            func strips(_ kind: InlineSpan.Kind) -> Bool {
                if insideCode { return kind == .code }
                return containing.contains { sameFormat($0.kind, kind) }
            }
            result = fragment.lines.map { fragmentLine -> String in
                var units = Array(fragment.units[fragmentLine.start..<fragmentLine.end])
                let markers = fragmentLine.markedSpans.filter { strips($0.kind) }
                    .flatMap { [$0.openMarker, $0.closeMarker] }
                    .filter { $0.length > 0 }
                    .sorted { $0.location > $1.location }
                for marker in markers {
                    units.removeSubrange((marker.location - fragmentLine.start)..<(NSMaxRange(marker) - fragmentLine.start))
                }
                return String(utf16CodeUnits: units, count: units.count)
            }.joined(separator: "\n")
        }
        guard hasFence else { return result }
        if hasUnterminatedFence(fragment) {
            result += result.hasSuffix("\n") ? "```" : "\n```"
        }
        if fragment.lines.first?.kind == .fenceOpen, selection.location != line.start {
            result = "\n" + result
        }
        let endLine = doc.line(at: NSMaxRange(selection))
        let reparsed = MarkdownDocument(result)
        if reparsed.lines.last?.kind == .fenceClose, NSMaxRange(selection) != endLine.end {
            result += "\n"
        }
        return result
    }
}
