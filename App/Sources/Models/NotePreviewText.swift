import Foundation
import MarkdownSyntax

/// 화면에 표시할 본문 줄을 한 줄의 미리보기로 잇는다.
package enum NotePreviewText {
    /// 대화 이름과 완료 알림에는 처음으로 글이 보이는 줄만 쓴다.
    package static func firstLine(in markdown: String) -> String? {
        let document = MarkdownDocument(markdown)
        for line in document.lines where line.kind != .fenceOpen && line.kind != .fenceClose {
            // Float의 체크박스는 목록 머리 없이도 올 수 있다.
            let source: String
            if case .todo = line.kind {
                source = document.string(in: line.contentRange)
            } else {
                source = document.string(in: line.range)
            }
            let trimmed = source.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if line.kind == .code { return trimmed }

            guard let rendered = try? AttributedString(markdown: trimmed) else { return trimmed }
            if rendered.runs.first?.presentationIntent?.components.contains(where: { $0.kind == .thematicBreak }) == true { continue }
            let text = String(rendered.characters).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return text }
        }
        return nil
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
