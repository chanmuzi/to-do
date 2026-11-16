import AppKit
import Theme

/// 마크다운 본문 편집기(spec 6). 미리 보기 없이 입력한 자리에서 스타일을 입힌다.
///
/// 원문(`text`)은 사용자가 친 Markdown 글자 그대로다. 화면의 서식은 TextKit 2가 문단을 만들 때
/// 속성만 얹어서 만들고, 원문에는 아무것도 더하지 않는다.
/// 창과 무관하게 `view`를 아무 곳에나 넣어 쓸 수 있다.
@MainActor
public final class MarkdownEditor {
    let controller: EditorController

    public init(theme: Theme, configuration: MarkdownEditorConfiguration = MarkdownEditorConfiguration()) {
        controller = EditorController(theme: theme, configuration: configuration)
    }

    /// 편집기 뷰(세로 스크롤 뷰). 바탕은 그리지 않는다. 안쪽 여백(`doc-pad`)은 편집기가 둔다.
    /// 바깥의 스크롤 뷰가 따로 있으면 이것 대신 `documentView`를 쓴다.
    public var view: NSView { controller.scrollView }

    /// 스크롤 뷰 없이 본문만 든 뷰(뒤집힌 좌표). 바깥이 가진 스크롤 뷰의 문서 뷰로 넣을 때 쓴다(노트 창).
    /// 바깥은 너비만 맞추고, 높이는 이 뷰가 내용에 맞춘다. 안쪽 여백은 여기에도 들어 있다.
    /// 이것을 다른 곳에 넣으면 `view`(편집기의 스크롤 뷰)는 비게 되므로 둘 중 하나만 쓴다.
    public var documentView: NSView { controller.textView }

    /// 원문. 줄바꿈은 언제나 `\n`이다: 넣을 때 `\r\n`, `\r`, U+2028, U+2029를 `\n`으로 바꾸므로
    /// 그런 글을 넣으면 읽은 값이 넣은 값과 다르다.
    /// 넣을 때는 `onTextChange`를 부르지 않고, 같은 글이면 아무것도 하지 않는다.
    /// 다른 글을 넣으면 되돌리기 기록을 비우고, 커서는 가능한 한 제자리에 둔다.
    /// 접힘은 같은 줄 번호가 새 글에서도 토글일 때만 남고, 그래서 달라지면 `onFoldChange`로 알린다.
    /// 노트를 처음 열 때는 `load(text:foldedLines:)`를 쓴다.
    public var text: String {
        get { controller.text }
        set { controller.text = newValue }
    }

    /// 노트를 연다. 원문과 접힌 줄을 한 번에 넣는다(순서를 신경 쓸 필요가 없다).
    /// `onTextChange`, `onFoldChange`를 부르지 않는다. 원문이 달라지면 되돌리기 기록을 비운다.
    public func load(text: String, foldedLines: Set<Int> = []) {
        controller.load(text: text, foldedLines: foldedLines)
    }

    /// 체크박스 모양 같은 설정. 바꾸면 곧바로 다시 그린다.
    public var configuration: MarkdownEditorConfiguration {
        get { controller.configuration }
        set { controller.configuration = newValue }
    }

    /// 사용자가 고쳐서 원문이 바뀌었을 때. `text`를 직접 넣을 때는 부르지 않는다.
    /// 한글을 조합하는 중에도 조합 중인 글자가 들어간 원문으로 부른다.
    public var onTextChange: ((String) -> Void)? {
        get { controller.onTextChange }
        set { controller.onTextChange = newValue }
    }

    /// 내용 높이(안쪽 여백 포함)가 바뀌었을 때. 노트 창이 이 높이에 맞춘다.
    public var onContentHeightChange: ((CGFloat) -> Void)? {
        get { controller.onContentHeightChange }
        set { controller.onContentHeightChange = newValue }
    }

    /// 지금의 내용 높이(안쪽 여백 포함). 뷰에 너비가 정해진 뒤에 맞는 값이 나온다.
    public var contentHeight: CGFloat { controller.contentHeight }

    /// 접힌 토글의 줄 번호(0부터). 원문에 적지 않는 보기 상태다. 지금 원문에서 토글이 아닌 줄 번호는 버린다
    /// (원문보다 먼저 넣으면 남지 않는다. 함께 넣을 때는 `load(text:foldedLines:)`).
    /// 넣을 때는 `onFoldChange`를 부르지 않는다. 편집을 되돌리면 접힘도 그 편집 전으로 돌아간다.
    public var foldedLines: Set<Int> {
        get { controller.foldedLines }
        set { controller.foldedLines = newValue }
    }

    /// 접힌 토글이 바뀌었을 때(사용자가 접고 폈거나, 원문이 바뀌어 줄 번호가 옮겨졌을 때).
    /// 값이 실제로 달라졌을 때만 한 번 부른다.
    public var onFoldChange: ((Set<Int>) -> Void)? {
        get { controller.onFoldChange }
        set { controller.onFoldChange = newValue }
    }

    /// 링크를 눌렀을 때. 정하지 않으면 기본 브라우저(메일 주소는 메일 앱)로 연다.
    /// `http`, `https`, `mailto` 주소만 온다. 다른 주소의 링크는 눌러도 열지 않는다.
    public var onOpenLink: ((URL) -> Void)? {
        get { controller.onOpenLink }
        set { controller.onOpenLink = newValue }
    }

    /// 선택 범위(원문의 UTF-16 위치).
    public var selectedRange: NSRange {
        get { controller.selectedRange }
        set { controller.selectedRange = newValue }
    }

    /// 되돌리기 기록. 편집기마다 따로 있다.
    public var undoManager: UndoManager { controller.editorUndoManager }

    /// 본문에 포커스를 준다.
    public func focus() {
        controller.focus()
    }

    /// 아직 `onTextChange`로 알리지 않은 변경이 있으면 지금 알린다(접힘, 높이도 함께).
    /// 편집기는 글자 입력이 아닌 편집을 다음 메인 큐 차례에 알릴 때가 있다. 그 전에 창을 닫거나
    /// 앱을 끝내는 쪽이 부른다. 알릴 것이 없으면 아무것도 하지 않는다.
    public func flushPendingChange() {
        controller.flushPendingChangeNow()
    }

    /// 편집 동작을 실행한다(단축키와 같은 일).
    public func perform(_ action: EditorAction) {
        controller.perform(action)
    }

    /// 창이 키 창이 아니어도 편집 중인 것처럼 커서 줄의 기호를 보인다.
    /// 화면을 캡처해 확인할 때만 쓴다(다른 앱의 포커스를 빼앗지 않기 위해).
    @_spi(Verification)
    public var forcesActiveAppearance: Bool {
        get { controller.forcesActiveAppearance }
        set { controller.forcesActiveAppearance = newValue }
    }

    /// 그 줄 왼쪽 칸 그림(체크박스, 꺾쇠)의 가운데(텍스트 뷰 좌표). 누름을 흉내 낼 때 쓴다.
    @_spi(Verification)
    public func gutterPoint(forLine line: Int) -> CGPoint? {
        controller.gutterPoint(forLine: line)
    }

    /// 그 줄 글자 영역 안의 한 점(텍스트 뷰 좌표). 마우스 올림을 흉내 낼 때 쓴다.
    @_spi(Verification)
    public func textPoint(forLine line: Int) -> CGPoint? {
        controller.textPoint(forLine: line)
    }

    /// 편집기의 텍스트 뷰. 확인용 실행 파일이 입력을 흉내 낼 때만 쓴다.
    @_spi(Verification)
    public var textView: NSTextView { controller.textView }
}
