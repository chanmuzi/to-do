import AppKit

nonisolated extension NSAttributedString.Key {
    /// 문단 첫 글자에 붙는 `FragmentDecoration`. 글자 뒤와 왼쪽 칸에 그릴 것을 담는다.
    static let markdownDecoration = NSAttributedString.Key("FloatingNotes.Editor.decoration")
    /// 형광펜과 인라인 코드의 둥근 바탕(`InlineBackground`).
    static let markdownInlineBackground = NSAttributedString.Key("FloatingNotes.Editor.inlineBackground")
    /// 링크 글자에 붙는 주소 문자열.
    static let markdownLink = NSAttributedString.Key("FloatingNotes.Editor.link")
}

/// 한 문단에서 글자 말고 그리는 것들. `ParagraphStyler`가 만들고 `MarkdownLayoutFragment`가 그린다.
nonisolated final class FragmentDecoration: NSObject {
    enum Gutter: Equatable {
        case checkbox(done: Bool)
        /// 0 채운 원, 1 빈 원, 2 채운 사각.
        case bullet(Int)
        case chevron(open: Bool)
    }

    let style: EditorStyle
    var gutter: Gutter?
    /// 왼쪽 칸이 시작하는 곳(텍스트 컨테이너 기준 x).
    var gutterX: CGFloat = 0
    /// 안내선 수(하위 계층 단계).
    var guideCount = 0
    /// 토글 제목 뒤에 적는 줄 수.
    var count: String?
    /// 문단 안에서 제목 글자가 끝나는 위치.
    var countIndex = 0
    /// 코드 블록 상자. 첫 줄이면 위 모서리를, 마지막 줄이면 아래 모서리를 둥글게 닫는다.
    var codeBox: (top: Bool, bottom: Bool)?
    var codeBoxX: CGFloat = 0
    /// 줄의 기본 글꼴. 줄 높이 안에서 글자를 세로 가운데에 놓을 때 기준으로 삼는다.
    var lineFont: NSFont?
    /// 가운데에서 더 옮길 양(아래가 +). 코드 블록의 ``` 줄이 쓴다.
    var centerOffset: CGFloat = 0
    /// 접힌 토글 안의 줄. 아무것도 그리지 않는다.
    var isCollapsed = false

    init(style: EditorStyle) {
        self.style = style
    }
}

/// 글자 뒤에 그리는 둥근 바탕 하나.
nonisolated final class InlineBackground: NSObject {
    enum Kind: Equatable {
        case highlight(Int)
        case code
    }

    let kind: Kind
    /// 글자 구간 좌우로 넓히는 폭.
    let padX: CGFloat
    /// 상자 높이. 줄 높이 안에서 세로 가운데에 놓는다.
    let height: CGFloat

    init(kind: Kind, padX: CGFloat, height: CGFloat) {
        self.kind = kind
        self.padX = padX
        self.height = height
    }
}
