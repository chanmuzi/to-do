import Foundation

/// 본문 맨 아래에 투두 한 줄을 붙인다. 투두 표기는 `[ ] 글자`(D-017).
nonisolated enum TodoAppender {
    static let marker = "[ ] "

    /// - 본문이 줄바꿈으로 끝나면 그 뒤에 바로 붙이고, 아니면 줄바꿈을 하나 넣고 붙인다.
    /// - 맨 끝의 빈 줄(공백뿐인 줄 포함)은 하나로 치지 않고 건너뛴다: 마지막 글 줄 바로 아래에 놓인다.
    /// - 붙인 줄은 줄바꿈으로 끝난다(편집기의 글은 언제나 줄바꿈으로 끝난다).
    /// - 본문이 `\r\n`을 쓰고 있으면 그것을 따른다.
    static func append(_ text: String, to body: String) -> String {
        let newline = body.contains("\r\n") ? "\r\n" : "\n"
        let line = marker + text + newline
        let kept = trimmingTrailingBlankLines(body)
        guard !kept.isEmpty else { return line }
        return kept + newline + line
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
