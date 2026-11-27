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
    /// 편집이 지정한 열린 토글의 새 줄 번호. 적용 뒤 비어 있는 것만 창 상태에 남긴다.
    var openTogglesAfter: Set<Int>?
    /// 줄 수와 줄 순서를 그대로 두는 편집(줄 머리만 바꾼다). 접힌 토글의 줄 번호가 그대로 남는다.
    var preservesLines = false
    /// 접혀서 보이지 않는 줄까지 일부러 고치는 편집(접힌 덩어리를 통째로 옮기거나 들여 쓴다).
    /// 이 표시가 없는 편집이 감춘 줄에 닿으면 편집기가 막고 그 토글을 편다.
    var includesHiddenLines = false
    /// 부모를 잃는 하위 줄을 이미 따진 편집(`EditorCommands.adoptingOrphans`). 다시 따지지 않는다.
    var checkedForOrphans = false

    init(
        range: NSRange,
        replacement: String,
        selection: NSRange,
        foldedAfter: Set<Int>? = nil,
        preservesLines: Bool = false,
        includesHiddenLines: Bool = false
    ) {
        self.range = range
        self.replacement = replacement
        self.selection = selection
        self.foldedAfter = foldedAfter
        self.preservesLines = preservesLines
        self.includesHiddenLines = includesHiddenLines
    }

    /// 선택을 `text`로 바꾸고 커서를 그 뒤에 둔다.
    static func insert(_ text: String, replacing selection: NSRange) -> TextEdit {
        TextEdit(
            range: selection,
            replacement: text,
            selection: NSRange(location: selection.location + text.utf16.count, length: 0)
        )
    }

    func offsettingRanges(by offset: Int) -> Self {
        var copy = self
        copy.range.location += offset
        copy.selection.location += offset
        return copy
    }

    func applied(to text: String) -> String {
        (text as NSString).replacingCharacters(in: range, with: replacement)
    }
}
