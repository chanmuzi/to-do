import AppKit
import Models
import Theme

/// 노트 창이 본문 자리에 끼우는 편집기. 구현은 App이 넘긴다(`NoteBodyEditorFactory`).
/// 노트 창은 이 프로토콜만 알고, 편집기 모듈을 import하지 않는다.
///
/// 지켜야 하는 것:
/// - `view`는 노트 창이 가진 스크롤 뷰의 문서 뷰가 된다. 노트 창은 너비만 맞춘다.
///   높이는 `view`가 스스로 내용에 맞추고, 위에서부터 쌓이도록 뒤집힌 좌표(`isFlipped`)여야 한다.
/// - 안쪽 여백(`Theme.docPadding`)은 편집기가 넣는다. 스크롤해도 여백이 글과 함께 움직이게 하기 위해서다.
/// - `onContentHeightChange`에는 여백을 포함한 내용 전체 높이를 넘긴다. 글이나 너비가 바뀌어
///   높이가 달라질 때마다, 그리고 처음 배치된 뒤 한 번 부른다. 노트 창이 이 값으로 창 높이를 맞춘다.
/// - `text`를 밖에서 넣을 때는 `onTextChange`를 부르지 않는다. 사용자가 고쳤을 때만 부른다.
@MainActor
public protocol NoteBodyEditing: AnyObject {
    var view: NSView { get }
    /// 본문 Markdown 원문.
    var text: String { get set }
    var onTextChange: ((String) -> Void)? { get set }
    var onContentHeightChange: ((CGFloat) -> Void)? { get set }
    /// 본문에 입력 커서를 둔다.
    func focus()
}

/// 편집기를 만들 때 넘기는 것.
public struct NoteBodyEditorContext {
    public let theme: Theme
    public let noteID: NoteID

    public init(theme: Theme, noteID: NoteID) {
        self.theme = theme
        self.noteID = noteID
    }
}

/// 노트 창 하나에 편집기 하나를 만든다. App이 넘긴다.
public typealias NoteBodyEditorFactory = @MainActor (NoteBodyEditorContext) -> any NoteBodyEditing
