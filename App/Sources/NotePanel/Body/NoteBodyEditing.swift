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
/// - 편집기에 글을 넣는 때는 셋뿐이다. (1) 편집기를 만든 직후 한 번. (2) 다른 프로그램이 파일을 고쳤거나
///   "파일의 내용으로 되돌리기"를 골랐을 때. (3) 이 앱의 다른 곳이 이 노트의 본문을 저장소에 썼을 때
///   (빠른 캡처가 떠 있는 노트에 한 줄을 덧붙임). (2)와 (3)에서는 저장소의 본문이 "편집기와 마지막으로
///   주고받은 본문"(마지막으로 넣은 값 또는 `onTextChange`로 받은 값)과 다를 때만 넣는다. 넣지 않으면
///   편집기가 옛 글을 들고 있다가 다음 입력 때 본문 전체를 옛 글로 덮어써, 덧붙인 줄이 사라진다.
/// - 넣는 방법은 셋이다. 편집기를 만든 직후에는 `text`에 넣는다. 그 뒤에 밖에서 바뀐 본문은 `text`에 넣지
///   않는다: 새 본문이 주고받은 본문의 끝에 글이 붙은 것이면 `appendFromOutside(_:)`로 붙은 글만 넘기고,
///   아니면(끝의 빈 줄을 걷어 내고 붙인 줄, 다른 프로그램이 고친 파일) `applyOutsideChange(to:)`로 새 본문을
///   넘긴다. 둘 다 할 수 있는 편집기는 바뀐 곳만 바꿔 커서, 접힘, 실행 취소 기록을 지킨다.
/// - 편집기가 `onTextChange`로 알려 준 글을 되돌려 넣지 않는다. 이 창이 한 저장(자동 저장, 제목과 색 변경,
///   닫을 때 쓰기, "내가 고친 내용으로 저장", "다시 저장")은 저장소의 본문이 주고받은 본문과 같으므로
///   편집기를 건드리지 않는다.
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
    func editedRange(from previous: String) -> NSRange?
    var onTextChange: ((String) -> Void)? { get set }
    var onContentHeightChange: ((CGFloat) -> Void)? { get set }
    func setNotePalette(_ id: String?)
    func setTitleFocusAction(_ action: @escaping () -> Void)
    func scheduleRemoved(fromBodyLine line: Int)
    /// 본문에 입력 커서를 둔다.
    func focus()
    /// 아직 `onTextChange`로 알리지 않은 변경이 있으면 지금 알린다.
    func flushPendingChange()
    /// 이 편집기가 아닌 쪽이 본문 끝에 `suffix`를 덧붙였다. 지금 글의 끝에 그대로 붙인다.
    /// `text`를 밖에서 넣을 때처럼 `onTextChange`를 부르지 않는다. 다만 아직 알리지 않은 사용자의 변경이
    /// 있었다면 버리지 않고, 다음에 알릴 때 붙인 글까지 든 원문을 넘긴다.
    /// 할 수 있는 편집기는 커서와 선택, 접힘, 실행 취소 기록, 조합 중인 글자를 그대로 둔다.
    /// 구현하지 않으면 `text`에 통째로 넣는 것으로 넘어간다(실행 취소 기록이 비워지고 조합이 끊긴다).
    func appendFromOutside(_ suffix: String)
    /// 이 편집기가 아닌 쪽이 본문을 `newText`로 바꿨다(끝에 붙인 것만이 아닌 바꿈: 끝의 빈 줄을 걷어 내고
    /// 붙인 줄, 다른 프로그램이 고친 파일, "파일의 내용으로 되돌리기"). 지금 글을 그 글로 맞춘다.
    /// `text`를 밖에서 넣을 때처럼 `onTextChange`를 부르지 않고, 넣기 전에 미뤄 둔 알림은 버린다.
    /// 할 수 있는 편집기는 달라진 곳만 바꿔 커서와 선택, 접힘, 실행 취소 기록을 그대로 둔다.
    /// 구현하지 않으면 `text`에 통째로 넣는 것으로 넘어간다(실행 취소 기록이 비워지고 조합이 끊긴다).
    func applyOutsideChange(to newText: String)
}

extension NoteBodyEditing {
    public func editedRange(from previous: String) -> NSRange? { nil }
    public func setNotePalette(_ id: String?) {}
    public func setTitleFocusAction(_ action: @escaping () -> Void) {}
    public func scheduleRemoved(fromBodyLine line: Int) {}

    public func appendFromOutside(_ suffix: String) {
        text += suffix
    }

    public func applyOutsideChange(to newText: String) {
        text = newText
    }
}

@MainActor
package protocol ScheduleLineDisplaying: AnyObject {
    func setScheduleMarkers(_ markers: [Int: ScheduleLineMarker])
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

public enum NoteFormat: CaseIterable { case bold, strike, highlight, code, link, checklist, bullet }

@MainActor
public protocol NoteBodyFormatting: AnyObject {
    var isEditingBody: Bool { get }
    var activeFormats: Set<NoteFormat> { get }
    var onFormattingChange: (() -> Void)? { get set }
    func applyFormat(_ format: NoteFormat)
}

@MainActor
package protocol NoteInkFormatting: AnyObject {
    var lastInkToken: ColorToken { get }
    func inkMenu() -> NSMenu
}

/// 노트 창 하나에 편집기 하나를 만든다. App이 넘긴다.
public typealias NoteBodyEditorFactory = @MainActor (NoteBodyEditorContext) -> any NoteBodyEditing
