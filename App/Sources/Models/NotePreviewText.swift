import Foundation
import MarkdownSyntax

/// 화면에 표시할 본문 줄을 한 줄의 미리보기로 잇는다.
package enum NotePreviewText {
    /// 대화 이름과 완료 알림에는 처음으로 글이 보이는 줄만 쓴다.
    package static func firstLine(in markdown: String) -> String? {
        firstLines(in: markdown, limit: 1).first
    }

    package static func firstLines(in markdown: String, limit: Int) -> [String] {
        var lines: [String] = []
        let document = MarkdownDocument(markdown)
        for line in document.lines where line.kind != .fenceOpen && line.kind != .fenceClose {
            // Float의 체크박스는 목록 머리 없이도 올 수 있다.
            let source: String
            switch line.kind {
            case .todo, .toggleHeading: source = document.string(in: line.contentRange)
            default: source = document.string(in: NSRange(location: line.start, length: line.contentEnd - line.start))
            }
            let trimmed = source.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            let rendered = line.kind == .code ? nil : try? AttributedString(markdown: trimmed)
            if rendered?.runs.first?.presentationIntent?.components.contains(where: { $0.kind == .thematicBreak }) == true { continue }
            let text = (rendered.map { String($0.characters) } ?? trimmed).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { lines.append(text) }
            if lines.count == limit { break }
        }
        return lines
    }

    /// 줄 단위의 기존 검색 정규화에 넘기기 전에 구조적인 줄바꿈 기호만 제거한다.
    package static func removingHardBreakMarkers(in markdown: String) -> String {
        guard markdown.contains("\\") else { return markdown }
        let doc = MarkdownDocument(markdown)
        return doc.lines.map { doc.string(in: NSRange(location: $0.start, length: $0.contentEnd - $0.start)) + doc.terminator(of: $0) }.joined()
    }

    package static func join(_ lines: some Sequence<String>) -> String {
        var result = ""
        for line in lines where !line.isEmpty {
            if let previous = result.last {
                result += previous.isPunctuation ? " " : ", "
            }
            result += line
        }
        return result
    }
}
