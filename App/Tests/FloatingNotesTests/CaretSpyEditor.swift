import AppKit
import NotePanel

/// 노트 창이 편집기를 어떻게 부르는지 적어 두는 시험용 편집기(`NoteBodyEditing`). Editor 모듈에 기대지 않고
/// App의 조립(캡처 바, 저장소, 노트 창)이 밖에서 바뀐 본문을 약속대로 넘기는지 본다.
///
/// 커서는 실제 편집기가 지키는 규칙을 흉내 낸다: 밖에서 글이 바뀌어도 커서는 제 글자 곁에 머물고, 문서 끝에
/// 있던 커서는 끝에 머문다(붙은 줄 앞에 끼어 남지 않는다).
final class CaretSpyEditor: NoteBodyEditing {
    let view: NSView = FlippedView()
    var onTextChange: ((String) -> Void)?
    var onContentHeightChange: ((CGFloat) -> Void)?

    /// 밖에서 `text`에 통째로 넣은 값(넣은 차례대로). 편집기를 만든 직후의 한 번만 있어야 한다.
    private(set) var assignments: [String] = []
    /// `appendFromOutside(_:)`로 받은 글.
    private(set) var appended: [String] = []
    /// `applyOutsideChange(to:)`로 받은 본문.
    private(set) var applied: [String] = []
    private var shown = ""
    /// 커서 자리(UTF-16).
    var caret = 0

    private var length: Int { (shown as NSString).length }

    var text: String {
        get { shown }
        set {
            assignments.append(newValue)
            shown = newValue
            caret = min(caret, length)
        }
    }

    func focus() {}
    func flushPendingChange() {}

    func appendFromOutside(_ suffix: String) {
        appended.append(suffix)
        let wasAtEnd = caret == length
        shown += suffix
        if wasAtEnd { caret = length }
    }

    func applyOutsideChange(to newText: String) {
        applied.append(newText)
        let old = shown as NSString
        let new = newText as NSString
        let wasAtEnd = caret == old.length
        // 앞뒤에서 그대로인 글자를 빼고 달라진 곳만 바꾼다.
        var prefix = 0
        while prefix < min(old.length, new.length), old.character(at: prefix) == new.character(at: prefix) {
            prefix += 1
        }
        var suffix = 0
        while suffix < min(old.length, new.length) - prefix,
              old.character(at: old.length - 1 - suffix) == new.character(at: new.length - 1 - suffix) {
            suffix += 1
        }
        shown = newText
        if wasAtEnd {
            caret = new.length
        } else if caret > old.length - suffix {
            caret += new.length - old.length
        } else if caret > prefix {
            caret = prefix
        }
    }

    /// 사용자가 커서 자리에 글을 친다.
    func type(_ typed: String) {
        shown = (shown as NSString).replacingCharacters(in: NSRange(location: caret, length: 0), with: typed)
        caret += (typed as NSString).length
        onTextChange?(shown)
    }

    private final class FlippedView: NSView {
        override var isFlipped: Bool { true }
    }
}
