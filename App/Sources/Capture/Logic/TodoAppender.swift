import Foundation

/// 본문 맨 아래에 투두 한 줄을 붙인다. 투두 표기는 `[ ] 글자`(D-017).
nonisolated enum TodoAppender {
    static let marker = "[ ] "
    private static let fence = "```"

    /// - 본문이 줄바꿈으로 끝나면 그 뒤에 바로 붙이고, 아니면 줄바꿈을 하나 넣고 붙인다.
    /// - 맨 끝의 빈 줄(공백뿐인 줄 포함)은 하나로 치지 않고 건너뛴다: 마지막 글 줄 바로 아래에 놓인다.
    /// - 붙인 줄은 줄바꿈으로 끝난다(편집기의 글은 언제나 줄바꿈으로 끝난다).
    /// - 본문이 `\r\n`을 쓰고 있으면 그것을 따른다.
    /// - 본문이 닫히지 않은 코드 블록으로 끝나면 먼저 블록을 닫는다(붙인 줄이 코드가 되지 않게).
    /// - 적은 글이 이미 투두 표기로 시작하면(`[ ] 우유`, `- [ ] 우유`) 표기를 겹쳐 붙이지 않는다.
    static func append(_ text: String, to body: String) -> String {
        let newline = body.contains("\r\n") ? "\r\n" : "\n"
        let line = todoLine(text) + newline
        var kept = trimmingTrailingBlankLines(body)
        guard !kept.isEmpty else { return line }
        if let indent = openFenceIndent(in: kept) { kept += newline + indent + fence }
        return kept + newline + line
    }

    /// 투두 한 줄. 적은 글에 붙어 있던 투두 표기(목록 기호 포함)는 하나로 고른다. 끝난 일 표시(`[x]`)는 남긴다.
    static func todoLine(_ text: String) -> String {
        guard let match = text.firstMatch(of: /^\s*(?:[-*+]\s+)?\[([ xX])\]\s+(.*)$/) else { return marker + text }
        return (match.1 == " " ? marker : "[x] ") + match.2
    }

    /// 닫히지 않은 코드 블록이 있으면 그 여는 줄의 들여쓰기. 판정은 편집기와 같다(`LineClassifier`):
    /// 들여쓰기 뒤에 ``` 로 시작하는 줄이 열고, ``` 뒤에 공백만 있는 줄이 닫는다.
    private static func openFenceIndent(in body: String) -> String? {
        var open: String?
        for rawLine in body.components(separatedBy: "\n") {
            let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
            let indent = String(line.prefix { $0 == " " || $0 == "\t" })
            let rest = line.dropFirst(indent.count)
            guard rest.hasPrefix(fence) else { continue }
            if open == nil {
                open = indent
            } else if rest.dropFirst(fence.count).allSatisfy({ $0 == " " || $0 == "\t" }) {
                open = nil
            }
        }
        return open
    }

    /// 맨 끝의 줄바꿈과 빈 줄을 뗀다. 마지막 글 줄의 끝 공백은 건드리지 않는다.
    private static func trimmingTrailingBlankLines(_ body: String) -> String {
        var lines = body.components(separatedBy: "\n")
        while let last = lines.last, last.allSatisfy(\.isWhitespace) {
            lines.removeLast()
        }
        var kept = lines.joined(separator: "\n")
        if kept.hasSuffix("\r") { kept.removeLast() }
        return kept
    }
}
