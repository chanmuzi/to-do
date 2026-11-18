import Foundation

/// 줄 안의 서식 구간 하나. 범위는 문서 전체 기준 UTF-16 위치다.
nonisolated package struct InlineSpan: Hashable, Sendable {
    package enum Kind: Hashable, Sendable {
        case bold
        case strike
        /// 형광펜. 번호는 1...4 (D-008의 `{n}`, 1은 생략).
        case highlight(Int)
        case code
        /// 링크. 주소만 적은 링크는 기호 구간이 비어 있다.
        case link(String)
        /// 백슬래시로 막은 글자 하나(`\*`). 여는 기호가 백슬래시이고 닫는 기호는 없다. 서식이 아니다.
        case escape
    }

    package var kind: Kind
    /// 기호까지 포함한 전체.
    package var range: NSRange
    /// 기호를 뺀 글자.
    package var contentRange: NSRange

    package var openMarker: NSRange {
        NSRange(location: range.location, length: contentRange.location - range.location)
    }

    package var closeMarker: NSRange {
        NSRange(location: NSMaxRange(contentRange), length: NSMaxRange(range) - NSMaxRange(contentRange))
    }

    package func contains(_ selection: NSRange) -> Bool {
        selection.location >= range.location && NSMaxRange(selection) <= NSMaxRange(range)
    }
}
