import AppKit
import Theme
import DateTime

/// 입력할 글자 또는 선택 전체에 적용되는 인라인 서식. highlight는 글자색 또는 바탕색 식별자이며 0은 색 없음이다.
public struct EditorFormattingState: Equatable, Sendable {
    public let bold: Bool
    public var underline = false
    public let strikethrough: Bool
    public let inlineCode: Bool
    public let highlight: Int
    public var link = false
    public var checklist = false
    public var bullet = false
}

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

    /// 바깥(이 편집기가 아닌 쪽)이 원문 끝에 글을 덧붙였을 때 그 글만 넘긴다(빠른 캡처가 떠 있는 노트에
    /// 한 줄을 덧붙임). 커서와 선택, 접힘, 되돌리기 기록, 조합 중인 글자를 그대로 둔다. 되돌리기에 적히지
    /// 않으므로 ⌘Z는 붙인 글을 지우지 않는다. `onTextChange`를 부르지 않는다.
    /// 줄바꿈 없이 끝나는 글이 붙으면 문서 끝의 커서는 그 뒤로 가고, 이어 치는 글은 새 줄에서 시작한다.
    /// 이 약속은 잇달아 붙는 글에도 이어진다(두 번째로 붙는 글이 줄바꿈으로 시작해도 커서가 따라간다).
    public func appendFromOutside(_ suffix: String) {
        controller.appendFromOutside(suffix)
    }

    /// 바깥(이 편집기가 아닌 쪽)이 원문을 `newText`로 바꿨을 때 부른다. 지금 원문과 견주어 앞뒤의 같은
    /// 부분은 그대로 두고 달라진 가운데만 바꿔 넣는다. 통째로 넣는 것(`text`)과 달리 되돌리기 기록,
    /// 접힘, 조합 중인 글자를 지키고, 커서는 바뀐 부분 밖이면 제자리에 둔다. `onTextChange`를 부르지 않는다.
    ///
    /// - 바깥의 변경은 되돌리기에 적히지 않는다: ⌘Z는 바깥이 쓴 글을 지우지도 되살리지도 않는다. 사용자의
    ///   되돌리기 기록은 그대로 남고, 기록이 가리키는 위치는 이 변경만큼 따라 옮겨진다(되돌리면 사용자가 고친
    ///   자리만 돌아간다). 바깥의 변경이 사용자가 고친 자리(넣은 글, 지운 자리)에 겹치면 그 단계는 옮길 수
    ///   없으므로, 그 단계와 그보다 오래된 단계를 버린다(다시 하기 쪽은 그 단계와 그 뒤의 단계). 통째로 다른
    ///   글이 오면 기록이 모두 사라진다.
    /// - 커서가 문서 끝에 있었고 바깥의 글이 그 줄에 이어 붙었으면(문서 끝에 닿는 변경이고 줄바꿈으로
    ///   시작하지 않는다. 예: 빈 마지막 줄에 `[ ] 우유\n`) 커서는 그 글 뒤로 간다. 그 글이 줄바꿈으로
    ///   끝나면 커서는 새 빈 마지막 줄에 놓이고, 아니면 사용자가 이어 치는 글이 새 줄에서 시작한다
    ///   (바깥이 붙인 줄에 붙지 않는다). 바깥의 글이 줄바꿈으로 시작하면 커서의 줄은 그대로이므로 제자리다.
    ///   커서나 선택의 끝이 바뀐 부분 안에 있었으면 바뀐 부분 뒤로 간다. 그 밖에는 제자리다.
    /// - 한글을 조합하는 중이면 화면에 넣는 일을 조합이 끝날 때까지 미룬다. 미룬 동안에도 `text`와
    ///   `onTextChange`로 나가는 원문에는 바깥의 변경이 들어 있다. 바뀐 부분이 조합 중인 글자에 겹치면
    ///   미루지 않고 조합을 끝낸 뒤 넣는다.
    public func applyOutsideChange(to newText: String) {
        controller.applyOutsideChange(to: newText)
    }

    /// 체크박스 모양 같은 설정. 바꾸면 곧바로 다시 그린다.
    public var configuration: MarkdownEditorConfiguration {
        get { controller.configuration }
        set { controller.configuration = newValue }
    }

    /// 사용자가 고쳐서 원문이 바뀌었을 때. `text`를 직접 넣을 때는 부르지 않는다.
    /// 한글을 조합하는 중에도 조합 중인 글자가 들어간 원문으로 부른다.
    package func editedRange(from previous: String) -> NSRange? {
        controller.lastBodyEdit.flatMap { $0.previous == previous ? $0.range : nil }
    }

    public var onTextChange: ((String) -> Void)? {
        get { controller.onTextChange }
        set { controller.onTextChange = newValue }
    }

    public var onFocusTitle: (() -> Void)? {
        get { controller.onFocusTitle }
        set { controller.onFocusTitle = newValue }
    }

    package func setScheduleMarkers(_ markers: [Int: ScheduleLineMarker]) {
        controller.updateScheduleButtons(markers)
    }

    package var onOpenSchedule: ((String?, NSView) -> Void)? {
        get { controller.onOpenSchedule }
        set { controller.onOpenSchedule = newValue }
    }

    #if DEBUG
    package func previewScheduleButton(line: Int, open: Bool) {
        guard let button = controller.scheduleButtons[line], !button.isHidden else { return }
        if open { button.openSchedule() } else { button.hovered = true }
    }

    package var scheduleButtonFrames: [Int: CGRect] {
        controller.scheduleButtons.filter { !$0.value.isHidden }.mapValues(\.frame)
    }
    #endif

    public func scheduleRemoved(fromBodyLine line: Int) {
        controller.scheduleRemoved(fromBodyLine: line)
    }

    package var onDeleteScheduleLines: ((String, String, UUID) throws -> InlineDateEffect?)? {
        get { controller.onDeleteScheduleLines }
        set { controller.onDeleteScheduleLines = newValue }
    }
    package func undoScheduleDeletion(_ token: UUID) {
        let history = controller.history
        guard (history.open ?? history.undoStack.last)?.dateEffect == token else { return }
        controller.replayUndo(redo: false)
    }

    public var onAcceptDate: ((InlineDateAcceptance) throws -> InlineDateEffect)? {
        get { controller.onAcceptDate }
        set { controller.onAcceptDate = newValue }
    }
    public var onDateError: (Error) -> Void {
        get { controller.onDateError }
        set { controller.onDateError = newValue }
    }
    #if DEBUG
    package func pasteBlocksForVerification(_ text: String, inside: Bool) {
        controller.pasteSource(text, inside: inside)
    }

    package func selectBlocksForVerification() { controller.selectBlocks() }
    package func clearBlocksForVerification() { controller.clearBlocks() }
    package var selectedBlockRows: ClosedRange<Int>? { controller.blockSelection?.rows }
    package func unfoldingFrame(for row: Int, draw: () -> Void) {
        guard let transition = controller.foldTransitions[row], transition.to == 1 else { return }
        let clock = controller.foldClock
        defer { controller.foldClock = clock }
        controller.foldClock = { transition.start + transition.duration / 2 }
        controller.advanceFoldMotion()
        draw()
    }

    @_spi(Verification) public func removeBodyLineForVerification(_ index: Int) {
        let document = controller.document
        guard document.lines.indices.contains(index) else { return }
        var range = document.lines[index].fullRange
        if index == document.lines.count - 1, index > 0 {
            range.location -= 1
            range.length += 1
        }
        controller.apply(EditorCommands.insert(document, "", replacing: range))
    }
    #endif

    @_spi(Verification) public func refreshDateSuggestion() { controller.updateDateSuggestion() }

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

    public var onFormattingChange: (() -> Void)? {
        get { controller.onFormattingChange }
        set { controller.onFormattingChange = newValue }
    }

    public var isEditingBody: Bool { controller.isActive }

    public var formattingState: EditorFormattingState { controller.formattingState }

    package static var editLinkAction: Selector { #selector(EditorTextView.editMarkdownLink(_:)) }
    package static var duplicateBlockAction: Selector { #selector(EditorTextView.duplicateMarkdownBlock(_:)) }
    package var hasSelectedInk: Bool { controller.selectedInk != nil }
    package var lastInkToken: ColorToken { EditorController.lastInk.token }
    package func inkMenu() -> NSMenu { controller.inkMenu() }

    package static var underlineAction: Selector { #selector(EditorTextView.toggleMarkdownUnderline(_:)) }
    package static var pasteInsideAction: Selector { #selector(EditorTextView.pasteInsideBlock(_:)) }
    package static var toggleBoldAction: Selector { #selector(EditorTextView.toggleMarkdownBold(_:)) }

    /// 선택 범위(원문의 UTF-16 위치).
    public var selectedRange: NSRange {
        get { controller.selectedRange }
        set { controller.selectedRange = newValue }
    }

    /// 되돌리기 기록. 편집기마다 따로 있다. 기록은 편집기가 직접 들고(바깥의 변경을 건너 위치를 옮길 수
    /// 있게), 이것은 메뉴와 단축키가 쓰는 창구다: `undo()`, `redo()`, `canUndo`, `canRedo`, `removeAllActions()`,
    /// `beginUndoGrouping()`과 `endUndoGrouping()`(그 사이의 편집이 한 단계)만 뜻이 있다. `registerUndo`는
    /// 받지 않는다. 묶음을 열지 않으면 런 루프 한 차례의 편집이 한 단계이고 이어 친 글자는 합쳐진다.
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

    /// 떠 있는 링크 주소 칸에 주소를 적고 Return을 누른 것과 같다(`perform(.link)` 뒤에 부른다).
    @_spi(Verification)
    public func commitLink(_ address: String) {
        controller.commitLink(address)
    }

    /// 창이 키 창이 아니어도 편집 중인 것으로 본다(편집 단축키를 받는다).
    /// 화면을 캡처해 확인할 때만 쓴다(다른 앱의 포커스를 빼앗지 않기 위해).
    @_spi(Verification)
    public var forcesActiveAppearance: Bool {
        get { controller.forcesActiveAppearance }
        set { controller.forcesActiveAppearance = newValue }
    }

    /// 입력 커서의 틀(텍스트 뷰 좌표). 커서가 없을 때(포커스가 없다, 선택이 있다)는 `nil`.
    @_spi(Verification)
    public var caretFrame: NSRect? {
        guard let caret = controller.textView.caret, caret.isActive else { return nil }
        return caret.frame
    }

    /// 그 줄 왼쪽 칸 그림(체크박스, 꺾쇠)의 가운데(텍스트 뷰 좌표). 누름을 흉내 낼 때 쓴다.
    @_spi(Verification)
    public func gutterPoint(forLine line: Int) -> CGPoint? {
        controller.gutterPoint(forLine: line)
    }

    @_spi(Verification)
    public func previewCheckboxHover(line: Int?) { controller.setHoveredCheckbox(line) }

    /// 그 줄 글자 영역 안의 한 점(텍스트 뷰 좌표). 마우스 올림을 흉내 낼 때 쓴다.
    @_spi(Verification)
    public func textPoint(forLine line: Int) -> CGPoint? {
        controller.textPoint(forLine: line)
    }

    /// 편집기의 텍스트 뷰. 확인용 실행 파일이 입력을 흉내 낼 때만 쓴다.
    @_spi(Verification)
    public var textView: NSTextView { controller.textView }

    @_spi(Verification) public var selectionFrames: [CGRect] { controller.selectionRects() }
}
