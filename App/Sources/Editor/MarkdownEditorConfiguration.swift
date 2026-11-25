/// 체크박스 모양(spec 6, 설정에서 고른다).
nonisolated public enum CheckboxStyle: String, Sendable, CaseIterable {
    /// 상자(기본).
    case box
    /// D2Coding 대괄호 `[ ]`, `[x]`. 왼쪽 칸이 28로 넓어진다.
    case bracket
}

/// 인라인 코드의 글자색(spec 6, 설정에서 고른다). 바탕과 치수는 같다. 코드 블록의 글자는 언제나 `code-fg`다.
nonisolated public enum InlineCodeStyle: String, Sendable, CaseIterable {
    /// 코드 강조색 `code-accent`(기본).
    case accent
    /// 본문과 같은 무채색 `code-fg`.
    case plain
}

/// 편집기 설정. 색, 글꼴, 치수는 `Theme`에서 온다.
nonisolated public struct MarkdownEditorConfiguration: Sendable, Equatable {
    package var showsScheduleGutter = false
    public var paletteID: String?
    public var recognizesDates = true
    public var checkboxStyle: CheckboxStyle
    public var inlineCodeStyle: InlineCodeStyle

    public init(checkboxStyle: CheckboxStyle = .box, inlineCodeStyle: InlineCodeStyle = .accent) {
        self.checkboxStyle = checkboxStyle
        self.inlineCodeStyle = inlineCodeStyle
    }
}

/// 편집 동작(spec 13의 "편집" 표). 단축키 없이도 부를 수 있게 공개한다(더 보기 메뉴 등).
nonisolated public enum EditorAction: Sendable, Hashable {
    case indent
    case outdent
    case toggleBullet
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
