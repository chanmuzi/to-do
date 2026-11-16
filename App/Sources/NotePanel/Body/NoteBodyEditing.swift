import AppKit
import Models
import Theme

/// 노트 창이 본문 자리에 끼우는 편집기. 구현은 App이 넘긴다(`NoteBodyEditorFactory`).
/// 노트 창은 이 프로토콜만 알고, 편집기 모듈을 import하지 않는다.
///
/// ## 화면
/// - `view`는 노트 창이 가진 스크롤 뷰의 문서 뷰가 된다. 노트 창은 너비만 맞춘다.
///   높이는 `view`가 스스로 내용에 맞추고, 위에서부터 쌓이도록 뒤집힌 좌표(`isFlipped`)여야 한다.
/// - 안쪽 여백(`Theme.docPadding`)은 편집기가 넣는다. 스크롤해도 여백이 글과 함께 움직이게 하기 위해서다.
/// - `onContentHeightChange`에는 여백을 포함한 내용 전체 높이를 넘긴다. 글이나 너비가 바뀌어
///   높이가 달라질 때마다, 그리고 처음 배치된 뒤 한 번 부른다. 노트 창이 이 값으로 창 높이를 맞춘다.
///
/// ## 글을 주고받는 약속
/// 편집 중인 글의 주인은 편집기다. 실행 취소 기록과 조합 중인 글자(한글 입력)는 편집기만 안다.
/// 편집기는 받은 글을 제 표기로 고쳐 보일 수 있고(CRLF를 LF로 등), 밖에서 다른 글을 넣으면
/// 실행 취소 기록을 비우고 조합을 끊어도 된다. 그래서 노트 창은 꼭 필요할 때만 `text`에 넣는다.
///
/// 노트 창이 지키는 것:
/// - `text`에 넣는 때는 둘뿐이다. (1) 편집기를 만든 직후 한 번. (2) 이 편집기가 아닌 쪽이 본문을 바꿨을 때
///   (다른 프로그램이 파일을 고침, "파일의 내용으로 되돌리기"). 그때도 저장소의 본문이 "편집기와 마지막으로
///   주고받은 본문"(마지막으로 `text`에 넣은 값 또는 `onTextChange`로 받은 값)과 다를 때만 넣는다.
/// - 편집기가 `onTextChange`로 알려 준 글을 되돌려 넣지 않는다. 이 앱이 한 저장(자동 저장, 제목과 색 변경,
///   닫을 때 쓰기, "내가 고친 내용으로 저장", "다시 저장")의 알림으로는 `text`를 건드리지 않는다.
/// - 저장하는 본문은 `onTextChange`로 받은 값 그대로다. 저장하려고 `text`를 읽지 않는다.
///
/// 편집기가 지켜야 하는 것:
/// - 사용자가 고쳐 본문 원문이 달라질 때마다 `onTextChange`에 그때의 원문 전체를 넘긴다. 조합 중에는
///   메인 큐에서 한 차례 늦게 불러도 된다. 노트 창은 받은 값을 `scheduleUpdate(id) { $0.body = text }`로 넘긴다.
/// - `text`를 밖에서 넣을 때는 `onTextChange`를 부르지 않는다. 넣기 전에 미뤄 둔 알림(옛 글의 것)이 있으면
///   버린다. 버리지 않으면 방금 받은 글을 옛 글이 덮어쓴다.
/// - 지금 글과 같은 글을 넣으면 아무것도 하지 않는다(실행 취소 기록과 조합을 그대로 둔다).
/// - 다른 글을 넣으면 그 글로 바꾸고 실행 취소 기록을 비운다(옛 기록은 새 글에 없는 범위를 가리킨다).
/// - 받은 글을 제 표기로 고쳐 보이는 것만으로는 `onTextChange`를 부르지 않는다(사용자가 고친 것이 아니다).
/// - `flushPendingChange()`가 불리면 아직 알리지 않은 변경(늦게 알리려고 미뤄 둔 것)을 그 자리에서
///   `onTextChange`로 알린다. 알릴 것이 없으면 아무것도 하지 않는다. 노트 창은 창을 내리기 전,
///   휴지통으로 보내기 전, 앱을 끝내기 전에 부른다. 부르지 않으면 같은 차례에 닫힌 창의 마지막 글이 사라진다.
@MainActor
public protocol NoteBodyEditing: AnyObject {
    var view: NSView { get }
    /// 본문 Markdown 원문.
    var text: String { get set }
    var onTextChange: ((String) -> Void)? { get set }
    var onContentHeightChange: ((CGFloat) -> Void)? { get set }
    /// 본문에 입력 커서를 둔다.
    func focus()
    /// 아직 `onTextChange`로 알리지 않은 변경이 있으면 지금 알린다.
    func flushPendingChange()
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
