import Foundation

/// 원문에 가하는 한 번의 바꿔 쓰기. 명령은 모두 이것 하나를 돌려준다(되돌리기 한 단계가 된다).
nonisolated struct TextEdit: Equatable, Sendable {
    /// 바꿀 범위(바꾸기 전 원문 기준).
    var range: NSRange
    var replacement: String
    /// 바꾼 뒤의 선택.
    var selection: NSRange
    /// 줄 순서가 바뀌는 편집이면 접힌 토글의 새 줄 번호.
    var foldedAfter: Set<Int>?

    init(range: NSRange, replacement: String, selection: NSRange, foldedAfter: Set<Int>? = nil) {
        self.range = range
        self.replacement = replacement
        self.selection = selection
        self.foldedAfter = foldedAfter
    }

    /// 선택을 `text`로 바꾸고 커서를 그 뒤에 둔다.
    static func insert(_ text: String, replacing selection: NSRange) -> TextEdit {
        TextEdit(
            range: selection,
            replacement: text,
            selection: NSRange(location: selection.location + text.utf16.count, length: 0)
        )
    }

    func applied(to text: String) -> String {
        (text as NSString).replacingCharacters(in: range, with: replacement)
    }
}
