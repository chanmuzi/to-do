import Foundation

// 사용자의 편집이 원문에 들어가기 전에 거치는 확인과 다듬기. 감춘 글자(줄 머리, 백슬래시, ``` 줄)는
// 화면에 보이지 않으므로, 편집의 경계가 그 한가운데에 놓이거나 한쪽만 지워지지 않게 한다.

nonisolated extension EditorCommands {
    /// 편집할 범위의 양 끝을 감춘 글자의 경계로 옮긴다.
    ///
    /// - 백슬래시와 그것이 막은 글자 사이에는 놓이지 않는다(백슬래시 앞으로 옮긴다).
    /// - 줄 머리(들여쓰기, 목록과 제목의 기호) 안에서 시작하는 범위는 글자가 보이기 시작하는 자리부터로 줄인다
    ///   (`- ab|c`에서 ⇧Home 뒤에 친 글자가 목록 기호를 지우지 않는다).
    /// - 뒷줄의 맨 앞에서 끝나는 범위는 그 줄의 감춘 줄 머리까지 늘린다(줄을 합칠 때 기호가 글자로 드러나지
    ///   않는다). 넣는 글이 줄바꿈으로 끝나면 줄이 합쳐지지 않으므로 늘리지 않는다.
    /// - 줄 맨 앞에서 시작해 뒷줄의 맨 앞에서 끝나는 범위(줄을 통째로 고른 것)와 문서 전체는 그대로 둔다.
    static func normalized(_ doc: MarkdownDocument, _ range: NSRange, replacement: String) -> NSRange {
        var lower = range.location
        var upper = NSMaxRange(range)
        let firstIndex = doc.lineIndex(at: lower)
        let first = doc.lines[firstIndex]
        if let escape = first.escape(splitAt: lower) {
            if upper == lower { upper = escape.range.location }
            lower = escape.range.location
        }
        guard upper > lower else { return NSRange(location: lower, length: 0) }
        if let escape = doc.line(at: upper).escape(splitAt: upper), escape.range.location >= lower {
            upper = escape.range.location
        }
        let isWholeDocument = lower == 0 && upper == doc.length
        let lastIndex = doc.lineIndex(at: upper)
        let last = doc.lines[lastIndex]
        let endsAtLineStart = lastIndex > firstIndex && upper == last.start
        let isWholeLines = lower == first.start && endsAtLineStart
        guard !isWholeDocument, !isWholeLines else { return NSRange(location: lower, length: upper - lower) }
        if first.kind != .fenceOpen, first.kind != .fenceClose, lower < first.caretStart {
            lower = first.caretStart
            upper = max(upper, lower)
        }
        if lastIndex > firstIndex, !last.kind.isCode, upper < last.caretStart, !replacement.hasSuffix("\n") {
            upper = last.caretStart
        }
        return NSRange(location: lower, length: upper - lower)
    }

    /// 두 편집을 하나로 합친다. `second`는 `first`를 적용한 원문(`middle`)에 대한 편집이다.
    static func compose(_ first: TextEdit, then second: TextEdit, middle: MarkdownDocument) -> TextEdit {
        let firstEnd = first.range.location + first.replacement.utf16.count
        let start = min(first.range.location, second.range.location)
        let end = max(firstEnd, NSMaxRange(second.range))
        let prefix = middle.string(in: NSRange(location: start, length: second.range.location - start))
        let suffix = middle.string(in: NSRange(location: NSMaxRange(second.range), length: end - NSMaxRange(second.range)))
        let oldEnd = end - first.replacement.utf16.count + first.range.length
        var result = second
        result.range = NSRange(location: start, length: oldEnd - start)
        result.replacement = prefix + second.replacement + suffix
        return result
    }

    // MARK: 코드 블록의 짝

    /// 닫는 줄이 없는 코드 블록이 있는지.
    static func hasUnterminatedFence(_ doc: MarkdownDocument) -> Bool {
        guard let last = doc.lines.last, let block = last.codeBlock else { return false }
        return last.kind != .fenceClose || block.lowerBound == block.upperBound
    }

    /// 그 편집을 넣어도 ``` 줄의 짝이 맞는지. 닫히지 않은 블록이 새로 생기는 편집은 넣지 않는다
    /// (``` 줄은 보이지 않아서, 짝을 잃으면 그 아래의 글이 모두 코드로 뒤집히고 사용자는 까닭을 볼 수 없다).
    /// 이미 닫히지 않은 블록이 있는 문서(다른 프로그램이 쓴 파일)에서는 막지 않는다.
    static func keepsFencesBalanced(_ doc: MarkdownDocument, _ edit: TextEdit) -> Bool {
        let lines = doc.lineIndex(at: edit.range.location)...doc.lineIndex(at: NSMaxRange(edit.range))
        let backtick: unichar = 0x60
        let touchesBacktick = edit.replacement.utf16.contains(backtick) || lines.contains { index in
            let line = doc.lines[index]
            return line.kind.isCode || (line.start..<line.end).contains { doc.units[$0] == backtick }
        }
        guard touchesBacktick, !hasUnterminatedFence(doc) else { return true }
        return !hasUnterminatedFence(MarkdownDocument(edit.applied(to: doc.text)))
    }

    // MARK: 편집 뒤 다듬기

    /// 편집의 결과를 다듬는다.
    ///
    /// - 지운 뒤에 줄 맨 앞에 남은 공백은 함께 지운다. 그대로 두면 그 공백이 감춘 들여쓰기가 된다.
    /// - 편집으로 맞붙은 같은 서식의 구간(`**ab****cd**`)은 하나로 합친다.
    static func finalized(_ doc: MarkdownDocument, _ edit: TextEdit) -> TextEdit {
        mergingAdjacentRuns(doc, unformattingBrokenRuns(doc, movingEdgeWhitespaceOut(doc, trimmingExposedIndent(doc, edit))))
    }

    /// 편집 때문에 있던 구간의 기호가 더는 기호로 읽히지 않게 되면(구간 바로 옆에 영문자를 쳐서 낱말 속이 된
    /// 경우 등) 그 구간의 기호를 지운다. 그대로 두면 감춰 있던 기호가 글자로 드러난다. 서식은 풀리고 글은 남는다.
    /// 사용자가 일부러 글자로 만든 경우(백슬래시로 막거나 인라인 코드로 감쌈)는 건드리지 않는다.
    private static func unformattingBrokenRuns(_ doc: MarkdownDocument, _ edit: TextEdit) -> TextEdit {
        let line = doc.line(at: edit.range.location)
        let endLine = doc.line(at: NSMaxRange(edit.range))
        guard !line.kind.isCode, !endLine.kind.isCode, !edit.replacement.contains("\n") else { return edit }
        let editEnd = NSMaxRange(edit.range)
        let delta = edit.replacement.utf16.count - edit.range.length
        // 편집 뒤에 한 줄이 되는 범위(줄을 합치는 편집이면 두 줄).
        let lineRange = NSRange(location: line.start, length: endLine.end - line.start)
        // 편집에 닿지 않은 기호를 가진 구간들. 기호의 자리를 편집 뒤의 줄 안 위치로 옮겨 본다.
        func mapped(_ marker: NSRange) -> NSRange? {
            if NSMaxRange(marker) <= edit.range.location { return NSRange(location: marker.location - line.start, length: marker.length) }
            if marker.location >= editEnd { return NSRange(location: marker.location - line.start + delta, length: marker.length) }
            return nil
        }
        let spans = line.start == endLine.start ? line.markedSpans : line.markedSpans + endLine.markedSpans
        let kept: [(open: NSRange, close: NSRange)] = spans.compactMap { span in
            guard let open = mapped(span.openMarker), let close = mapped(span.closeMarker) else { return nil }
            return (open, close)
        }
        let local = NSRange(location: edit.range.location - line.start, length: edit.range.length)
        // 넣는 글(붙여 넣은 글)이 제 안에 가진 구간들도 넣은 자리에서 기호로 읽혀야 한다.
        let inserted: [(open: NSRange, close: NSRange)] = edit.replacement.utf16.count < 2 ? [] :
            (MarkdownDocument("\u{200B}" + edit.replacement).lines.first?.markedSpans ?? []).map { span in
                let shift = local.location - 1
                return (
                    NSRange(location: span.openMarker.location + shift, length: span.openMarker.length),
                    NSRange(location: span.closeMarker.location + shift, length: span.closeMarker.length)
                )
            }
        let expected = kept + inserted
        guard !expected.isEmpty else { return edit }
        let newText = (doc.string(in: lineRange) as NSString).replacingCharacters(in: local, with: edit.replacement)
        let parsed = MarkdownDocument(newText)
        guard parsed.lines.count == 1, let newLine = parsed.lines.first, newLine.kind == line.kind else { return edit }
        let live = newLine.markedSpans
        // 기호가 아니라 글자로 보이는 자리인지: 감춘 기호도, 인라인 코드의 글도, 막은 글자도 아니다.
        func isLiteral(_ marker: NSRange) -> Bool {
            !newLine.hiddenSpans.contains { span in
                let covered = span.kind == .code || span.kind == .escape ? span.range : nil
                return [span.openMarker, span.closeMarker, covered ?? NSRange(location: 0, length: 0)].contains {
                    $0.length > 0 && NSIntersectionRange($0, marker).length > 0
                }
            }
        }
        var removed: [NSRange] = []
        for span in expected {
            if live.contains(where: { $0.openMarker == span.open && $0.closeMarker == span.close }) { continue }
            guard span.open.length > 0, span.close.length > 0, isLiteral(span.open), isLiteral(span.close) else { continue }
            removed += [span.open, span.close]
        }
        guard !removed.isEmpty else { return edit }
        var text = newText as NSString
        var selection = edit.selection
        for marker in removed.sorted(by: { $0.location > $1.location }) {
            text = text.replacingCharacters(in: marker, with: "") as NSString
            let at = line.start + marker.location
            func move(_ position: Int) -> Int {
                position >= at + marker.length ? position - marker.length : min(position, at)
            }
            let start = move(selection.location)
            selection = NSRange(location: start, length: max(0, move(NSMaxRange(selection)) - start))
        }
        var result = edit
        result.range = lineRange
        result.replacement = text as String
        result.selection = selection
        return result
    }

    /// 편집으로 서식 구간의 글이 공백으로 시작하거나 끝나게 되면(`**가 **`), 그 공백을 기호 밖으로 옮긴다
    /// (`**가** `). 여는 기호 뒤와 닫는 기호 앞은 공백일 수 없어서, 그대로 두면 기호가 글자로 드러난다.
    /// 글이 공백만 남으면 기호를 지운다.
    private static func movingEdgeWhitespaceOut(_ doc: MarkdownDocument, _ edit: TextEdit) -> TextEdit {
        let line = doc.line(at: edit.range.location)
        guard !line.kind.isCode, !edit.replacement.contains("\n"), NSMaxRange(edit.range) <= line.end else { return edit }
        let enclosing = line.markedSpans.filter { span in
            // 링크의 글자는 공백으로 시작하거나 끝나도 된다.
            if case .link = span.kind { return false }
            return span.contentRange.location <= edit.range.location && NSMaxRange(edit.range) <= NSMaxRange(span.contentRange)
        }.sorted { $0.range.length < $1.range.length }
        guard !enclosing.isEmpty else { return edit }

        let delta = edit.replacement.utf16.count - edit.range.length
        var units = Array(doc.units[line.start..<line.end])
        units.replaceSubrange((edit.range.location - line.start)..<(NSMaxRange(edit.range) - line.start), with: Array(edit.replacement.utf16))
        // 줄 안의 위치로 다룬다.
        var start = edit.selection.location - line.start
        var end = NSMaxRange(edit.selection) - line.start
        var changed = false
        // 안쪽 구간의 기호를 지운 만큼 바깥 구간의 닫는 기호가 당겨진다.
        var removed = 0
        for span in enclosing {
            var open = NSRange(location: span.openMarker.location - line.start, length: span.openMarker.length)
            var close = NSRange(location: span.closeMarker.location - line.start + delta - removed, length: span.closeMarker.length)
            let contentStart = NSMaxRange(open)
            var leading = 0
            while contentStart + leading < close.location, InlineParser.isWhitespace(units[contentStart + leading]) { leading += 1 }
            func move(_ transform: (Int) -> Int) {
                start = transform(start)
                end = max(start, transform(end))
            }
            if contentStart + leading == close.location {
                // 공백만 남았다(또는 비었다). 기호를 지운다.
                units.removeSubrange(close.location..<NSMaxRange(close))
                units.removeSubrange(open.location..<NSMaxRange(open))
                let (o, c) = (open, close)
                move { position in
                    var result = position
                    if position >= NSMaxRange(c) { result -= c.length } else if position > c.location { result = c.location }
                    if position >= NSMaxRange(o) { result -= o.length } else if position > o.location { result = o.location }
                    return result
                }
                removed += o.length + c.length
                changed = true
                continue
            }
            if leading > 0 {
                // [여는 기호][공백] 을 [공백][여는 기호] 로.
                let marker = Array(units[open.location..<contentStart])
                let space = Array(units[contentStart..<(contentStart + leading)])
                units.replaceSubrange(open.location..<(contentStart + leading), with: space + marker)
                let o = open
                move { position in
                    if position <= o.location || position >= NSMaxRange(o) + leading { return position }
                    return position >= NSMaxRange(o) ? position - o.length : o.location
                }
                open.location += leading
                changed = true
            }
            var trailing = 0
            while close.location - trailing > NSMaxRange(open), InlineParser.isWhitespace(units[close.location - trailing - 1]) { trailing += 1 }
            if trailing > 0 {
                // [공백][닫는 기호] 를 [닫는 기호][공백] 으로.
                let space = Array(units[(close.location - trailing)..<close.location])
                let marker = Array(units[close.location..<NSMaxRange(close)])
                units.replaceSubrange((close.location - trailing)..<NSMaxRange(close), with: marker + space)
                let c = close
                move { position in
                    if position <= c.location - trailing || position >= NSMaxRange(c) { return position }
                    return position <= c.location ? position + c.length : NSMaxRange(c)
                }
                close.location -= trailing
                changed = true
            }
        }
        guard changed else { return edit }
        var result = edit
        result.range = line.range
        result.replacement = String(utf16CodeUnits: units, count: units.count)
        result.selection = NSRange(location: line.start + start, length: end - start)
        return result
    }

    private static func trimmingExposedIndent(_ doc: MarkdownDocument, _ edit: TextEdit) -> TextEdit {
        guard edit.replacement.isEmpty, edit.range.length > 0 else { return edit }
        let line = doc.line(at: edit.range.location)
        let endLine = doc.line(at: NSMaxRange(edit.range))
        guard edit.range.location == line.start, line.kind == .paragraph, line.indentLength == 0,
              !endLine.kind.isCode else { return edit }
        var upper = NSMaxRange(edit.range)
        guard upper > endLine.start + endLine.indentLength || endLine.start == line.start else { return edit }
        while upper < endLine.end, doc.units[upper] == 0x20 || doc.units[upper] == 0x09 { upper += 1 }
        guard upper > NSMaxRange(edit.range) else { return edit }
        var result = edit
        result.range.length = upper - edit.range.location
        return result
    }

    private static func mergingAdjacentRuns(_ doc: MarkdownDocument, _ edit: TextEdit) -> TextEdit {
        let line = doc.line(at: edit.range.location)
        let endLine = doc.line(at: NSMaxRange(edit.range))
        guard !line.kind.isCode, !endLine.kind.isCode, !edit.replacement.contains("\n") else { return edit }
        // 편집 뒤의 그 줄만 다시 풀어 본다.
        let lineRange = NSRange(location: line.start, length: endLine.end - line.start)
        let local = NSRange(location: edit.range.location - line.start, length: edit.range.length)
        let newText = (doc.string(in: lineRange) as NSString).replacingCharacters(in: local, with: edit.replacement)
        let parsed = MarkdownDocument(newText)
        guard parsed.lines.count == 1, let newLine = parsed.lines.first else { return edit }
        let regionStart = local.location
        let regionEnd = local.location + edit.replacement.utf16.count
        let spans = newLine.markedSpans
        var removed: [NSRange] = []
        for left in spans {
            guard let right = spans.first(where: { $0.range.location == NSMaxRange(left.range) && $0.kind == left.kind }),
                  left.closeMarker.length > 0, right.openMarker.length > 0,
                  left.closeMarker.location <= regionEnd, NSMaxRange(right.openMarker) >= regionStart else { continue }
            if case .link = left.kind { continue }
            removed.append(left.closeMarker)
            removed.append(right.openMarker)
        }
        guard !removed.isEmpty else { return edit }
        var merged = newText as NSString
        var selection = edit.selection
        for marker in removed.sorted(by: { $0.location > $1.location }) {
            merged = merged.replacingCharacters(in: marker, with: "") as NSString
            let at = line.start + marker.location
            func move(_ position: Int) -> Int {
                position >= at + marker.length ? position - marker.length : min(position, at)
            }
            let start = move(selection.location)
            selection = NSRange(location: start, length: max(0, move(NSMaxRange(selection)) - start))
        }
        var result = edit
        result.range = lineRange
        result.replacement = merged as String
        result.selection = selection
        return result
    }

    // MARK: 기호가 기호로 읽히는지

    /// 편집을 넣은 뒤에도, 그 편집이 쓴 기호들이 기호로 읽히는지. `markers`는 바꿔 쓴 글 안의 위치다.
    /// 낱말 한가운데(앞뒤가 모두 영문자나 숫자)에 쓴 `**` 같은 기호는 글자로 읽히므로, 그런 편집은 넣지 않는다.
    static func marksAreRecognized(_ doc: MarkdownDocument, _ edit: TextEdit, markers: [NSRange]) -> Bool {
        let line = doc.line(at: edit.range.location)
        let endLine = doc.line(at: NSMaxRange(edit.range))
        let lineRange = NSRange(location: line.start, length: endLine.end - line.start)
        let local = NSRange(location: edit.range.location - line.start, length: edit.range.length)
        let newText = (doc.string(in: lineRange) as NSString).replacingCharacters(in: local, with: edit.replacement)
        let parsed = MarkdownDocument(newText)
        let all = Set(parsed.lines.flatMap { $0.markedSpans.flatMap { [$0.openMarker, $0.closeMarker] } })
        return markers.allSatisfy { marker in
            marker.length == 0 || all.contains(NSRange(location: local.location + marker.location, length: marker.length))
        }
    }

    /// 기호로 읽힐 수 있는 글자 앞에 백슬래시를 붙인다(이미 막은 글자는 그대로 둔다).
    static func escaped(_ text: String, only characters: Set<Character> = InlineParser.escapableCharacters) -> String {
        var result = ""
        var previousWasBackslash = false
        for character in text {
            if previousWasBackslash {
                result.append(character)
                previousWasBackslash = false
                continue
            }
            if character == "\\" {
                previousWasBackslash = true
                result.append(character)
                continue
            }
            if characters.contains(character) { result.append("\\") }
            result.append(character)
        }
        return result
    }
}
