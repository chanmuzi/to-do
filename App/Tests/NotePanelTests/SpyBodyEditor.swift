import AppKit
@testable import NotePanel

/// 실제 편집기(Editor 모듈)가 하는 일을 흉내 내는 시험용 편집기.
/// 밖에서 `text`에 넣은 횟수와 값을 적어 둔다. 실제 편집기는 다른 글을 받으면 실행 취소 기록을 비우고
/// 조합 중인 글자를 버리므로, 노트 창이 필요 없이 넣지 않는지를 이것으로 본다.
@MainActor
final class SpyBodyEditor: NoteBodyEditing {
    let view: NSView = FlippedView()
    var onTextChange: ((String) -> Void)?
    var isChangingUserFold = false
    var onContentHeightChange: ((CGFloat) -> Void)?
    /// 밖에서 `text`에 넣은 값(넣은 차례대로).
    private(set) var assignments: [String] = []
    private var shown = ""
    /// 마지막으로 주고받은 글.
    private var notified = ""
    /// 밖에서 끝에 덧붙인 글(붙인 차례대로).
    private(set) var appended: [String] = []
    private(set) var flushCount = 0
    private let normalizesLineEndings: Bool

    /// - Parameter normalizesLineEndings: 받은 글의 CRLF를 LF로 고쳐 보인다(실제 편집기처럼).
    init(normalizesLineEndings: Bool = false) {
        self.normalizesLineEndings = normalizesLineEndings
    }

    var text: String {
        get { shown }
        set {
            assignments.append(newValue)
            shown = normalizesLineEndings ? newValue.replacingOccurrences(of: "\r\n", with: "\n") : newValue
            notified = shown
        }
    }

    private(set) var focusCount = 0

    func focus() {
        focusCount += 1
    }

    /// 실제 편집기처럼 지금 보이는 글(조합 중인 글자 포함) 끝에 붙이고, 조합과 알리지 않은 변경은 그대로 둔다.
    func appendFromOutside(_ suffix: String) {
        appended.append(suffix)
        let hadUnnotified = shown != notified
        shown += suffix
        if !hadUnnotified { notified = shown }
    }

    /// 밖에서 바뀐 본문을 통째로 받은 것(받은 차례대로). 실제 편집기는 달라진 곳만 바꾼다.
    private(set) var applied: [String] = []

    /// 실제 편집기처럼 받은 글로 맞추고, 미뤄 둔 알림은 버린다. `text`에 넣은 것으로 세지 않는다.
    func applyOutsideChange(to newText: String) {
        applied.append(newText)
        shown = normalizesLineEndings ? newText.replacingOccurrences(of: "\r\n", with: "\n") : newText
        notified = shown
    }

    /// 화면에만 있고 아직 알리지 않은 글(조합 중이거나 한 차례 늦게 알리려던 것)을 알린다.
    func flushPendingChange() {
        guard shown != notified else { return }
        notified = shown
        flushCount += 1
        onTextChange?(shown)
    }

    /// 사용자가 글을 쳐서 편집기가 알린다.
    func type(_ text: String) {
        shown = text
        notified = text
        onTextChange?(text)
    }

    /// 조합 중인 글자가 화면에만 있고 아직 알리지 않았다.
    func compose(_ text: String) {
        shown = text
    }

    private final class FlippedView: NSView {
        override var isFlipped: Bool { true }
    }
}
