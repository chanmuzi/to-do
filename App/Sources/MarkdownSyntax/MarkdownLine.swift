import Foundation

nonisolated package enum LineKind: Hashable, Sendable {
    case divider
    case paragraph
    case heading(Int)
    case todo(done: Bool)
    case bullet
    /// 접고 펴는 토글. 원문은 `+ `(D-044).
    case toggle
    case toggleHeading(Int)
    /// 인용문. 원문은 표준 Markdown의 `> `(D-044).
    case quote
    /// 코드 블록을 여는 ``` 줄, 닫는 ``` 줄, 그 사이의 줄.
    case fenceOpen
    case fenceClose
    case code

    package var isToggle: Bool {
        switch self {
        case .toggle, .toggleHeading: true
        default: false
        }
    }

    package var headingLevel: Int? {
        switch self {
        case .heading(let level), .toggleHeading(let level): level
        default: nil
        }
    }

    package var isListItem: Bool {
        switch self {
        case .todo, .bullet, .toggle, .toggleHeading: true
        default: false
        }
    }

    /// 하위 계층의 부모가 될 수 있는 줄(목록, 투두, 토글, 인용문). 들여 쓴 줄은 이런 줄 아래에만 놓인다(D-043).
    package var isParentItem: Bool {
        switch self {
        case .todo, .bullet, .toggle, .toggleHeading, .quote: true
        default: false
        }
    }

    package var isCode: Bool {
        switch self {
        case .fenceOpen, .fenceClose, .code: true
        default: false
        }
    }
}

/// 원문의 한 줄(TextKit의 문단 하나). 범위는 문서 전체 기준 UTF-16 위치다.
nonisolated package struct MarkdownLine: Hashable, Sendable {
    /// 줄바꿈 글자를 뺀 범위.
    package var range: NSRange
    /// 줄바꿈 글자까지 포함한 범위.
    package var fullRange: NSRange
    /// 줄 앞 들여쓰기(탭, 공백)의 길이.
    package var indentLength = 0
    /// 하위 계층 단계. 탭 하나 또는 공백 둘이 한 단계다.
    package var level = 0
    package var kind: LineKind = .paragraph
    /// 들여쓰기 뒤 기호(`- `, `[ ] `, `+ `, `> `, `# `)의 길이.
    package var markerLength = 0
    /// 강제 줄바꿈으로 이어진 줄의 첫 물리 줄 번호.
    package var continuationOf: Int?
    var blockLast = 0
    package var hasHardBreak = false
    package var blockInk: InkColor?
    package var inkComment: NSRange?
    package var contentEnd: Int { (inkComment?.location ?? end) - (hasHardBreak ? 1 : 0) }
    package var spans: [InlineSpan] = []
    /// 이 줄의 하위 줄이 끝나는 줄 번호(그 줄은 포함하지 않음).
    package var subtreeEnd = 0
    /// 코드 블록에 속하면 그 블록의 줄 번호 범위(``` 줄 포함).
    package var codeBlock: ClosedRange<Int>?

    /// 편집 앞뒤 줄 수가 같으면 문서 좌표만 옮기고 기존의 구문 분석을 재사용한다.
    mutating func shiftSourceRanges(by offset: Int) {
        guard offset != 0 else { return }
        range.location += offset
        fullRange.location += offset
        inkComment?.location += offset
        for index in spans.indices {
            spans[index].range.location += offset
            spans[index].contentRange.location += offset
        }
    }

    package var start: Int { range.location }
    package var end: Int { NSMaxRange(range) }
    package var isBlankParagraph: Bool { continuationOf == nil && !hasHardBreak && kind == .paragraph && contentRange.length == 0 }
    package var prefixLength: Int { indentLength + markerLength }
    package var contentStart: Int { start + prefixLength }
    package var contentRange: NSRange { NSRange(location: contentStart, length: contentEnd - contentStart) }
    package var indentRange: NSRange { NSRange(location: start, length: indentLength) }
    package var markerRange: NSRange { NSRange(location: start + indentLength, length: markerLength) }
    package var prefixRange: NSRange { NSRange(location: start, length: prefixLength) }

    /// 항상 감춰 두는 줄 머리의 끝. 커서는 이보다 앞에 놓이지 않는다.
    /// 들여쓰기, 목록 기호, 제목의 `#`은 보이지 않는다(목록은 왼쪽 칸의 그림이 대신한다).
    /// 코드 줄은 들여쓰기만 줄 머리다.
    package var caretStart: Int {
        switch kind {
        case .fenceOpen, .fenceClose, .code: start + indentLength
        case .divider, .paragraph, .heading, .todo, .bullet, .toggle, .toggleHeading, .quote: contentStart
        }
    }
}
