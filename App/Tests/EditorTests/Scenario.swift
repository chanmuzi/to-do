import Foundation
@testable import Editor

/// 명령을 원문에 적용한 결과를 `|`(커서) 표기로 견준다. `|`가 둘이면 그 사이가 선택이다.
struct Scenario {
    var text: String
    var selection: NSRange

    init(_ marked: String) {
        let parts = marked.components(separatedBy: "|")
        text = parts.joined()
        let start = parts[0].utf16.count
        selection = NSRange(location: start, length: parts.count > 2 ? parts[1].utf16.count : 0)
    }

    var doc: MarkdownDocument { MarkdownDocument(text) }

    func applying(_ edit: TextEdit?) -> String? {
        guard let edit else { return nil }
        return Self.marked(edit.applied(to: text), selection: edit.selection)
    }

    /// 원문에 선택을 `|`로 적어 넣는다.
    static func marked(_ text: String, selection: NSRange) -> String {
        let end = (text as NSString).replacingCharacters(in: NSRange(location: NSMaxRange(selection), length: 0), with: "|") as NSString
        guard selection.length > 0 else { return end as String }
        return end.replacingCharacters(in: NSRange(location: selection.location, length: 0), with: "|")
    }
}
