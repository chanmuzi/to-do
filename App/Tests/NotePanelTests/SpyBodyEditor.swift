import AppKit
@testable import NotePanel

/// 실제 편집기(Editor 모듈)가 하는 일을 흉내 내는 시험용 편집기.
/// 밖에서 `text`에 넣은 횟수와 값을 적어 둔다. 실제 편집기는 다른 글을 받으면 실행 취소 기록을 비우고
/// 조합 중인 글자를 버리므로, 노트 창이 필요 없이 넣지 않는지를 이것으로 본다.
@MainActor
final class SpyBodyEditor: NoteBodyEditing {
    let view: NSView = FlippedView()
    var onTextChange: ((String) -> Void)?
    var onContentHeightChange: ((CGFloat) -> Void)?
    /// 밖에서 `text`에 넣은 값(넣은 차례대로).
    private(set) var assignments: [String] = []
    private var shown = ""
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
        }
    }

    func focus() {}

    /// 사용자가 글을 쳐서 편집기가 알린다.
    func type(_ text: String) {
        shown = text
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
