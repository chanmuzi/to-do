import Foundation

/// 원문을 줄 단위로 푼 것. 원문은 바꾸지 않는다(같은 글자를 그대로 들고 있다).
/// 줄 경계는 TextKit의 문단 경계(`\n`, `\r`, `\r\n`, U+2029)와 같다.
/// 편집기는 원문을 넣기 전에 줄바꿈을 `\n`으로 맞추므로(`LineEndings`) 편집기 안에서는 `\n`만 나온다.
nonisolated package struct MarkdownDocument: Sendable {
    /// 하위 계층은 이 단계까지만 받는다.
    package static let maxLevel = 8

    package let text: String
    package let units: [unichar]
    package private(set) var lines: [MarkdownLine]

    package var length: Int { units.count }

    package init(_ text: String) {
        self.text = text
        self.units = Array(text.utf16)
        self.lines = []
        splitLines()
        classifyLines()
        linkStructure()
    }

    package func string(in range: NSRange) -> String {
        let lower = max(0, min(range.location, units.count))
        let upper = max(lower, min(NSMaxRange(range), units.count))
        return String(utf16CodeUnits: Array(units[lower..<upper]), count: upper - lower)
    }

    package func todoCompletion(on line: MarkdownLine) -> Bool? {
        guard case .todo(let done) = line.kind, blockLines(at: lineIndex(at: line.start)).contains(where: {
            !string(in: lines[$0].contentRange).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else { return nil }
        return done
    }

    /// 그 위치가 속한 줄 번호. 문서 끝은 마지막 줄이다.
    package func lineIndex(at location: Int) -> Int {
        var low = 0
        var high = lines.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lines[mid].start <= location { low = mid } else { high = mid - 1 }
        }
        return low
    }

    /// 선택이 걸친 줄. 선택이 다음 줄 맨 앞에서 끝나면 그 줄은 넣지 않는다.
    package func lineRange(for selection: NSRange) -> ClosedRange<Int> {
        let first = lineIndex(at: selection.location)
        var last = lineIndex(at: NSMaxRange(selection))
        if selection.length > 0, last > first, NSMaxRange(selection) == lines[last].start { last -= 1 }
        return first...last
    }

    package func ownerLines(for selection: NSRange) -> ClosedRange<Int> {
        let rows = lineRange(for: selection)
        return (lines[rows.lowerBound].continuationOf ?? rows.lowerBound)...(lines[rows.upperBound].continuationOf ?? rows.upperBound)
    }

    package func blockLines(at index: Int) -> ClosedRange<Int> {
        let first = lines[index].continuationOf ?? index
        return first...lines[index].blockLast
    }

    package func sourceRange(for rows: ClosedRange<Int>) -> NSRange {
        let start = lines[rows.lowerBound].start
        return NSRange(location: start, length: lines[rows.upperBound].end - start)
    }

    package func blockColor(at index: Int) -> InkColor? {
        lines[blockLines(at: index).upperBound].blockInk
    }

    package func blockSource(at index: Int) -> String {
        string(in: sourceRange(for: blockLines(at: index)))
    }

    /// 줄바꿈 글자(없으면 빈 문자열).
    package func terminator(of line: MarkdownLine) -> String {
        string(in: NSRange(location: line.end, length: NSMaxRange(line.fullRange) - line.end))
    }

    // MARK: 풀기

    private mutating func splitLines() {
        let n = units.count
        var i = 0
        var endedWithTerminator = true
        while i < n {
            var j = i
            while j < n, units[j] != 0x0A, units[j] != 0x0D, units[j] != 0x2029 { j += 1 }
            var terminator = 0
            if j < n { terminator = units[j] == 0x0D && j + 1 < n && units[j + 1] == 0x0A ? 2 : 1 }
            lines.append(MarkdownLine(
                range: NSRange(location: i, length: j - i),
                fullRange: NSRange(location: i, length: j - i + terminator)
            ))
            endedWithTerminator = terminator > 0
            i = j + terminator
        }
        if endedWithTerminator {
            lines.append(MarkdownLine(range: NSRange(location: n, length: 0), fullRange: NSRange(location: n, length: 0)))
        }
    }

    private mutating func classifyLines() {
        var fence: (index: Int, indentLength: Int, level: Int)?
        for index in lines.indices {
            var line = lines[index]
            // 구문 분류 전에 주석을 떼어 빈 블록의 앞 공백도 들여쓰기로 소비되지 않게 한다.
            if fence == nil, units[line.start..<line.end].suffix(4).elementsEqual(" -->".utf16),
               let start = units[line.start..<line.end].lastIndex(of: 0x3C), start > line.start,
               units[start - 1] == 0x20, units[start..<line.end].starts(with: "<!-- ".utf16),
               start + 5 <= line.end - 4 {
                let name = String(decoding: units[(start + 5)..<(line.end - 4)], as: UTF16.self)
                if let color = InkColor.byLabel[name] {
                    line.blockInk = color
                    line.inkComment = NSRange(location: start - 1, length: line.end - start + 1)
                }
            }
            let bodyEnd = line.contentEnd
            let indent = LineClassifier.indent(units, from: line.start, to: bodyEnd)
            let bodyStart = line.start + indent.length
            if let open = fence {
                if LineClassifier.isClosingFence(units, from: bodyStart, to: line.end) {
                    line.kind = .fenceClose
                    line.indentLength = indent.length
                    fence = nil
                    for i in open.index..<index { lines[i].codeBlock = open.index...index }
                    line.codeBlock = open.index...index
                } else {
                    line.kind = .code
                    // 블록이 들여쓰여 있으면 그만큼만 줄 머리로 본다. 그 뒤의 공백은 코드의 일부다.
                    line.indentLength = min(indent.length, open.indentLength)
                }
                line.level = open.level
            } else if index > 0, lines[index - 1].hasHardBreak {
                let owner = lines[index - 1].continuationOf ?? (index - 1)
                line.continuationOf = owner
                line.indentLength = min(lines[owner].indentLength, bodyEnd - line.start)
                line.level = lines[owner].level
            } else if LineClassifier.isFence(units, from: bodyStart, to: line.end) {
                line.blockInk = nil
                line.inkComment = nil
                line.kind = .fenceOpen
                line.indentLength = indent.length
                line.level = min(indent.level, Self.maxLevel)
                fence = (index, indent.length, line.level)
            } else {
                let marker = LineClassifier.classify(units, from: bodyStart, to: bodyEnd)
                line.kind = marker.kind == .divider && line.inkComment != nil ? .paragraph : marker.kind
                line.markerLength = line.kind == .paragraph ? 0 : marker.markerLength
                line.indentLength = indent.length
                line.level = min(indent.level, Self.maxLevel)
            }
            if !line.kind.isCode {
                if index + 1 < lines.count, bodyEnd > line.contentStart, units[bodyEnd - 1] == 0x5C {
                    var start = bodyEnd - 1
                    while start > line.contentStart, units[start - 1] == 0x5C { start -= 1 }
                    let next = lines[index + 1]
                    // 이어지는 줄에서 주인 줄의 들여쓰기만 소모한다. 나머지 공백은 본문이다.
                    let nextIndent = LineClassifier.indent(units, from: next.start, to: next.end)
                    line.hasHardBreak = (bodyEnd - start) % 2 == 1
                        && !LineClassifier.isFence(units, from: next.start + nextIndent.length, to: next.end)
                        && units[next.start..<next.end].starts(with: units[line.start..<(line.start + line.indentLength)])
                }
                if line.inkComment != nil { line.hasHardBreak = false }
                line.spans = InlineParser.parse(units, in: line.contentRange)
            }
            lines[index] = line
        }
        // 닫히지 않은 블록은 문서 끝까지다.
        if let open = fence {
            for i in open.index..<lines.count { lines[i].codeBlock = open.index...(lines.count - 1) }
        }
    }

    private mutating func linkStructure() {
        for index in lines.indices.reversed() {
            lines[index].blockLast = lines[index].hasHardBreak ? lines[index + 1].blockLast : index
        }
        for index in lines.indices {
            let level = lines[index].level
            var end = blockLines(at: index).upperBound + 1
            var cursor = end
            while lines[index].kind != .divider, cursor < lines.count {
                let child = lines[cursor]
                cursor += 1
                // 토글 안쪽의 빈 구분 줄은 다음 자식과 함께 접고, 마지막 자식 뒤의 빈 줄은 밖에 둔다.
                if lines[index].kind.isToggle, child.isBlankParagraph, child.level <= level { continue }
                guard child.level > level else { break }
                end = cursor
            }
            lines[index].subtreeEnd = end
        }
    }
}
