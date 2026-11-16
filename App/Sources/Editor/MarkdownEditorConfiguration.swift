/// 체크박스 모양(spec 6, 설정에서 고른다).
nonisolated public enum CheckboxStyle: String, Sendable, CaseIterable {
    /// 상자(기본).
    case box
    /// D2Coding 대괄호 `[ ]`, `[x]`. 왼쪽 칸이 28로 넓어진다.
    case bracket
}

/// 편집기 설정. 색, 글꼴, 치수는 `Theme`에서 온다.
nonisolated public struct MarkdownEditorConfiguration: Sendable, Equatable {
    public var checkboxStyle: CheckboxStyle

    public init(checkboxStyle: CheckboxStyle = .box) {
        self.checkboxStyle = checkboxStyle
    }
}

/// 편집 동작(spec 13의 "편집" 표). 단축키 없이도 부를 수 있게 공개한다(더 보기 메뉴 등).
nonisolated public enum EditorAction: Sendable, Hashable {
    case indent
    case outdent
    case toggleTodo
    case toggleDone
    case moveLineUp
    case moveLineDown
    case fold
    case unfold
    case heading(Int)
    case bold
    case strikethrough
    /// 형광펜. 다시 부르면 다음 색으로 넘어간다.
    case highlight
    case inlineCode
    case codeBlock
    case link
}
