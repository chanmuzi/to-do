import Foundation

/// 한 줄의 글자 구간에서 굵게, 취소선, 형광펜, 인라인 코드, 링크, 백슬래시로 막은 글자를 찾는다.
/// 바깥 구간이 안쪽 구간보다 먼저 나온다. 인라인 코드 안은 더 풀지 않는다.
///
/// 기호로 읽는 조건(D-036의 13번). 맞지 않는 기호는 글자 그대로 보인다.
/// - 여는 기호 바로 뒤와 닫는 기호 바로 앞은 공백이 아니어야 한다(`a == b`, `2 ** 3`, `` ` `` 뒤의 공백).
/// - `**`, `~~`, `==`: 여는 기호 앞과 닫는 기호 뒤가 둘 다 영문자나 숫자면 낱말 속의 글자로 본다
///   (`x==1&y==2`, `2**3**4`). 한글은 여기의 영문자나 숫자가 아니다(`**중요**하다`는 굵게다).
/// - `\` 뒤의 `*`, `=`, `~`, `` ` ``, `[`, `]`, `\`는 그 글자 그대로다. 백슬래시는 보이지 않고 원문에 남는다.
///   인라인 코드 안에서는 백슬래시도 글자다.
nonisolated enum InlineParser {
    private static let backtick: unichar = 0x60
    private static let star: unichar = 0x2A
    private static let tilde: unichar = 0x7E
    private static let equals: unichar = 0x3D
    private static let backslash: unichar = 0x5C
    private static let leftBracket: unichar = 0x5B
    private static let rightBracket: unichar = 0x5D
    private static let leftParen: unichar = 0x28
    private static let rightParen: unichar = 0x29
    private static let leftBrace: unichar = 0x7B
    private static let rightBrace: unichar = 0x7D
    private static let httpPrefixes: [[unichar]] = [Array("https://".utf16), Array("http://".utf16)]
    private static let trailingPunctuation = Set(".,;:!?)\"'".utf16)
    /// 백슬래시로 막을 수 있는 글자.
    static let escapable: Set<unichar> = [star, equals, tilde, backtick, leftBracket, rightBracket, backslash]
    static let escapableCharacters: Set<Character> = ["*", "=", "~", "`", "[", "]", "\\"]

    static func parse(_ units: [unichar], in range: NSRange) -> [InlineSpan] {
        var spans: [InlineSpan] = []
        scan(units, from: range.location, to: NSMaxRange(range), lineStart: range.location, into: &spans)
        return spans
    }

    static func isWhitespace(_ c: unichar) -> Bool {
        c == 0x20 || c == 0x09 || c == 0xA0 || c == 0x3000
    }

    private static func isEscape(_ u: [unichar], at i: Int, to end: Int) -> Bool {
        u[i] == backslash && i + 1 < end && escapable.contains(u[i + 1])
    }

    /// `i`에서 시작하는 인라인 코드의 닫는 백틱. 여는 백틱 뒤와 닫는 백틱 앞은 공백이 아니어야 한다.
    private static func codeClose(_ u: [unichar], from i: Int, to end: Int) -> Int? {
        guard i + 2 < end, !isWhitespace(u[i + 1]), u[i + 1] != backtick else { return nil }
        var j = i + 2
        while j < end {
            if u[j] == backtick, !isWhitespace(u[j - 1]) { return j }
            j += 1
        }
        return nil
    }

    /// `i`에서 시작하는 `cc`의 닫는 `cc`. 사이의 백슬래시로 막은 글자와 인라인 코드는 건너뛴다.
    private static func pairClose(_ c: unichar, in u: [unichar], from i: Int, to end: Int) -> Int? {
        guard i + 2 < end, !isWhitespace(u[i + 2]) else { return nil }
        var j = i + 2
        while j + 1 < end {
            if isEscape(u, at: j, to: end) {
                j += 2
            } else if u[j] == backtick, let close = codeClose(u, from: j, to: end) {
                j = close + 1
            } else if u[j] == c, u[j + 1] == c, j > i + 2, !isWhitespace(u[j - 1]) {
                return j
            } else {
                j += 1
            }
        }
        return nil
    }

    private static func scan(_ u: [unichar], from start: Int, to end: Int, lineStart: Int, into spans: inout [InlineSpan]) {
        var i = start
        while i < end {
            let c = u[i]
            if isEscape(u, at: i, to: end) {
                spans.append(InlineSpan(
                    kind: .escape,
                    range: NSRange(location: i, length: 2),
                    contentRange: NSRange(location: i + 1, length: 1)
                ))
                i += 2
                continue
            }
            if c == backtick, let close = codeClose(u, from: i, to: end) {
                spans.append(InlineSpan(
                    kind: .code,
                    range: NSRange(location: i, length: close + 1 - i),
                    contentRange: NSRange(location: i + 1, length: close - i - 1)
                ))
                i = close + 1
                continue
            }
            if c == star || c == tilde || c == equals, i + 1 < end, u[i + 1] == c,
               let close = pairClose(c, in: u, from: i, to: end) {
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
                // 앞뒤가 모두 영문자나 숫자에 붙어 있으면 낱말 속의 글자다. 두 기호 모두 글자로 둔다.
                let glued = i > lineStart && isWordCharacter(u[i - 1]) && spanEnd < end && isWordCharacter(u[spanEnd])
                if !glued {
                    spans.append(InlineSpan(
                        kind: kind,
                        range: NSRange(location: i, length: spanEnd - i),
                        contentRange: NSRange(location: i + 2, length: close - i - 2)
                    ))
                }
                scan(u, from: i + 2, to: close, lineStart: lineStart, into: &spans)
                i = glued ? close + 2 : spanEnd
                continue
            }
            if c == leftBracket,
               let textEnd = linkTextEnd(u, from: i + 1, to: end),
               // 글자가 없는 링크는 화면에 아무것도 남지 않으므로 링크로 읽지 않는다.
               textEnd > i + 1, textEnd + 1 < end, u[textEnd + 1] == leftParen,
               let urlEnd = index(of: rightParen, in: u, from: textEnd + 2, to: end) {
                let url = String(utf16CodeUnits: Array(u[(textEnd + 2)..<urlEnd]), count: urlEnd - textEnd - 2)
                spans.append(InlineSpan(
                    kind: .link(url),
                    range: NSRange(location: i, length: urlEnd + 1 - i),
                    contentRange: NSRange(location: i + 1, length: textEnd - i - 1)
                ))
                scan(u, from: i + 1, to: textEnd, lineStart: lineStart, into: &spans)
                i = urlEnd + 1
                continue
            }
            if c == 0x68, i == lineStart || !isWordCharacter(u[i - 1]), let urlEnd = bareURLEnd(u, at: i, to: end) {
                let range = NSRange(location: i, length: urlEnd - i)
                let url = String(utf16CodeUnits: Array(u[i..<urlEnd]), count: urlEnd - i)
                spans.append(InlineSpan(kind: .link(url), range: range, contentRange: range))
                i = urlEnd
                continue
            }
            i += 1
        }
    }

    /// 링크 글자를 닫는 `]`. 백슬래시로 막은 글자는 건너뛴다.
    private static func linkTextEnd(_ u: [unichar], from: Int, to end: Int) -> Int? {
        var i = from
        while i < end {
            if isEscape(u, at: i, to: end) {
                i += 2
            } else if u[i] == rightBracket {
                return i
            } else {
                i += 1
            }
        }
        return nil
    }

    private static func index(of c: unichar, in u: [unichar], from: Int, to end: Int) -> Int? {
        var i = from
        while i < end {
            if u[i] == c { return i }
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

    static func isWordCharacter(_ c: unichar) -> Bool {
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
