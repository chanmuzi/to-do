import Foundation

/// 한 줄의 글자 구간에서 굵게, 취소선, 형광펜, 인라인 코드, 링크를 찾는다.
/// 바깥 구간이 안쪽 구간보다 먼저 나온다. 인라인 코드 안은 더 풀지 않는다.
nonisolated enum InlineParser {
    private static let backtick: unichar = 0x60
    private static let star: unichar = 0x2A
    private static let tilde: unichar = 0x7E
    private static let equals: unichar = 0x3D
    private static let leftBracket: unichar = 0x5B
    private static let rightBracket: unichar = 0x5D
    private static let leftParen: unichar = 0x28
    private static let rightParen: unichar = 0x29
    private static let leftBrace: unichar = 0x7B
    private static let rightBrace: unichar = 0x7D
    private static let httpPrefixes: [[unichar]] = [Array("https://".utf16), Array("http://".utf16)]
    private static let trailingPunctuation = Set(".,;:!?)\"'".utf16)

    static func parse(_ units: [unichar], in range: NSRange) -> [InlineSpan] {
        var spans: [InlineSpan] = []
        scan(units, from: range.location, to: NSMaxRange(range), into: &spans)
        return spans
    }

    private static func scan(_ u: [unichar], from start: Int, to end: Int, into spans: inout [InlineSpan]) {
        var i = start
        while i < end {
            let c = u[i]
            if c == backtick, let close = index(of: backtick, in: u, from: i + 1, to: end), close > i + 1 {
                spans.append(InlineSpan(
                    kind: .code,
                    range: NSRange(location: i, length: close + 1 - i),
                    contentRange: NSRange(location: i + 1, length: close - i - 1)
                ))
                i = close + 1
                continue
            }
            if c == star || c == tilde || c == equals, i + 1 < end, u[i + 1] == c,
               let close = indexOfPair(c, in: u, from: i + 2, to: end), close > i + 2 {
                var spanEnd = close + 2
                let kind: InlineSpan.Kind
                switch c {
                case star: kind = .bold
                case tilde: kind = .strike
                default:
                    if let number = highlightSuffix(u, at: spanEnd, to: end) {
                        kind = .highlight(number)
                        spanEnd += 3
                    } else {
                        kind = .highlight(1)
                    }
                }
                spans.append(InlineSpan(
                    kind: kind,
                    range: NSRange(location: i, length: spanEnd - i),
                    contentRange: NSRange(location: i + 2, length: close - i - 2)
                ))
                scan(u, from: i + 2, to: close, into: &spans)
                i = spanEnd
                continue
            }
            if c == leftBracket,
               let textEnd = index(of: rightBracket, in: u, from: i + 1, to: end),
               // 글자가 없는 링크는 화면에 아무것도 남지 않으므로 링크로 읽지 않는다.
               textEnd > i + 1, textEnd + 1 < end, u[textEnd + 1] == leftParen,
               let urlEnd = index(of: rightParen, in: u, from: textEnd + 2, to: end) {
                let url = String(utf16CodeUnits: Array(u[(textEnd + 2)..<urlEnd]), count: urlEnd - textEnd - 2)
                spans.append(InlineSpan(
                    kind: .link(url),
                    range: NSRange(location: i, length: urlEnd + 1 - i),
                    contentRange: NSRange(location: i + 1, length: textEnd - i - 1)
                ))
                scan(u, from: i + 1, to: textEnd, into: &spans)
                i = urlEnd + 1
                continue
            }
            if c == 0x68, i == start || !isWordCharacter(u[i - 1]), let urlEnd = bareURLEnd(u, at: i, to: end) {
                let range = NSRange(location: i, length: urlEnd - i)
                let url = String(utf16CodeUnits: Array(u[i..<urlEnd]), count: urlEnd - i)
                spans.append(InlineSpan(kind: .link(url), range: range, contentRange: range))
                i = urlEnd
                continue
            }
            i += 1
        }
    }

    private static func index(of c: unichar, in u: [unichar], from: Int, to end: Int) -> Int? {
        var i = from
        while i < end {
            if u[i] == c { return i }
            i += 1
        }
        return nil
    }

    private static func indexOfPair(_ c: unichar, in u: [unichar], from: Int, to end: Int) -> Int? {
        var i = from
        while i + 1 < end {
            if u[i] == c, u[i + 1] == c { return i }
            i += 1
        }
        return nil
    }

    /// `{2}`~`{4}`(와 `{1}`)를 읽는다.
    private static func highlightSuffix(_ u: [unichar], at i: Int, to end: Int) -> Int? {
        guard i + 2 < end, u[i] == leftBrace, u[i + 2] == rightBrace else { return nil }
        let digit = Int(u[i + 1]) - 0x30
        return (1...4).contains(digit) ? digit : nil
    }

    private static func isWordCharacter(_ c: unichar) -> Bool {
        (0x30...0x39).contains(c) || (0x41...0x5A).contains(c) || (0x61...0x7A).contains(c)
    }

    private static func bareURLEnd(_ u: [unichar], at i: Int, to end: Int) -> Int? {
        guard let prefix = httpPrefixes.first(where: { p in
            i + p.count <= end && !p.indices.contains { u[i + $0] != p[$0] }
        }) else { return nil }
        var j = i + prefix.count
        while j < end, u[j] != 0x20, u[j] != 0x09 { j += 1 }
        while j > i + prefix.count, trailingPunctuation.contains(u[j - 1]) { j -= 1 }
        return j > i + prefix.count ? j : nil
    }
}
