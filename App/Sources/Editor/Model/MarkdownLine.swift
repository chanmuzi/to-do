import Foundation

nonisolated enum LineKind: Hashable, Sendable {
    case paragraph
    case heading(Int)
    case todo(done: Bool)
    case bullet
    case toggle
    /// 코드 블록을 여는 ``` 줄, 닫는 ``` 줄, 그 사이의 줄.
    case fenceOpen
    case fenceClose
    case code

    var isListItem: Bool {
        switch self {
        case .todo, .bullet, .toggle: true
        default: false
        }
    }

    var isCode: Bool {
        switch self {
        case .fenceOpen, .fenceClose, .code: true
        default: false
        }
    }
}

/// 원문의 한 줄(TextKit의 문단 하나). 범위는 문서 전체 기준 UTF-16 위치다.
nonisolated struct MarkdownLine: Hashable, Sendable {
    /// 줄바꿈 글자를 뺀 범위.
    var range: NSRange
    /// 줄바꿈 글자까지 포함한 범위.
    var fullRange: NSRange
    /// 줄 앞 들여쓰기(탭, 공백)의 길이.
    var indentLength = 0
    /// 하위 계층 단계. 탭 하나 또는 공백 둘이 한 단계다.
    var level = 0
    var kind: LineKind = .paragraph
    /// 들여쓰기 뒤 기호(`- `, `[ ] `, `> `, `# `)의 길이.
    var markerLength = 0
    var spans: [InlineSpan] = []
    /// 이 줄의 하위 줄이 끝나는 줄 번호(그 줄은 포함하지 않음).
    var subtreeEnd = 0
    /// 바로 아래 단계의 줄 수(토글 제목 뒤에 보이는 수).
    var childCount = 0
    /// 코드 블록에 속하면 그 블록의 줄 번호 범위(``` 줄 포함).
    var codeBlock: ClosedRange<Int>?

    var start: Int { range.location }
    var end: Int { NSMaxRange(range) }
    var prefixLength: Int { indentLength + markerLength }
    var contentStart: Int { start + prefixLength }
    var contentRange: NSRange { NSRange(location: contentStart, length: end - contentStart) }
    var indentRange: NSRange { NSRange(location: start, length: indentLength) }
    var markerRange: NSRange { NSRange(location: start + indentLength, length: markerLength) }
    var prefixRange: NSRange { NSRange(location: start, length: prefixLength) }

    /// 항상 감춰 두는 줄 머리의 끝. 커서는 이보다 앞에 놓이지 않는다.
    /// 목록 기호는 왼쪽 칸의 그림으로 대신하므로 감추고, 제목의 `#`은 편집 중에 보이므로 들여쓰기만 감춘다.
    var caretStart: Int {
        switch kind {
        case .heading, .fenceOpen, .fenceClose, .code: start + indentLength
        case .paragraph, .todo, .bullet, .toggle: contentStart
        }
    }
}
