import AppKit

/// 캡처 바에서 키로 하는 동작(spec 7, 13).
enum CaptureCommand: Hashable {
    /// ↵: 오늘 노트에 투두로 넣는다.
    case submit
    /// ⌘↵: 새 노트로 만들어 띄운다.
    case submitAsNewNote
    /// ⇥, ⇧⇥: 스페이스를 차례로 바꾼다.
    case nextSpace, previousSpace
    /// ⌘R: 리마인더를 직접 고른다.
    case cycleReminder
    /// esc: 닫는다.
    case cancel
}

/// 캡처 바의 한 줄 입력 칸. 글자 입력은 시스템 텍스트 뷰에 맡기고 명령 키만 가로챈다.
///
/// 한글 조합: 조합 중인 글자가 있을 때 ↵는 조합을 끝내기만 하고 넣지 않는다. 조합 중에도 글이 바뀔 때마다
/// `onTextChange`를 부르되 글 저장소는 건드리지 않으므로(밑줄은 임시 속성) 조합이 끊기지 않는다.
final class CaptureTextView: NSTextView {
    var onCommand: ((CaptureCommand) -> Void)?
    var onTextChange: (() -> Void)?
    var caretWidth: CGFloat = 1

    /// 이번 키 입력이 시작될 때 조합 중이었는지. 입력기가 조합을 끝낸 뒤 같은 키로 ↵ 명령을 보내는 경우를 가린다.
    private var wasComposingAtKeyDown = false

    override func keyDown(with event: NSEvent) {
        wasComposingAtKeyDown = hasMarkedText()
        defer { wasComposingAtKeyDown = false }
        super.keyDown(with: event)
    }

    override func doCommand(by selector: Selector) {
        switch selector {
        case #selector(insertNewline(_:)):
            if hasMarkedText() || wasComposingAtKeyDown {
                if hasMarkedText() { unmarkText() }
                return
            }
            onCommand?(.submit)
        case #selector(insertTab(_:)):
            onCommand?(.nextSpace)
        case #selector(insertBacktab(_:)):
            onCommand?(.previousSpace)
        case #selector(cancelOperation(_:)), #selector(complete(_:)):
            // esc는 텍스트 뷰에서 낱말 완성으로 넘어가기도 한다. 여기서는 언제나 닫기다.
            onCommand?(.cancel)
        case #selector(insertNewlineIgnoringFieldEditor(_:)), #selector(insertLineBreak(_:)),
             #selector(insertParagraphSeparator(_:)), #selector(insertTabIgnoringFieldEditor(_:)):
            // 한 줄짜리 칸이다. 줄바꿈과 탭 글자는 넣지 않는다.
            return
        default:
            super.doCommand(by: selector)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        switch (event.charactersIgnoringModifiers, flags) {
        case ("\r", .command), ("\u{3}", .command):
            if hasMarkedText() { unmarkText() }
            onCommand?(.submitAsNewNote)
            return true
        case ("r", .command), ("R", .command), ("ㄱ", .command):
            onCommand?(.cycleReminder)
            return true
        default:
            return performEditShortcut(event.charactersIgnoringModifiers, flags: flags)
                || super.performKeyEquivalent(with: event)
        }
    }

    /// 편집 단축키(전체 선택, 복사, 오려두기, 붙여넣기, 실행 취소). 이 창은 다른 앱이 앞에 있을 때도 떠서
    /// 그 앱의 메뉴 막대가 보이는 중일 수 있다. 메뉴에 기대지 않고 직접 받는다.
    private func performEditShortcut(_ key: String?, flags: NSEvent.ModifierFlags) -> Bool {
        switch (key?.lowercased(), flags) {
        case ("a", .command): selectAll(nil)
        case ("c", .command): copy(nil)
        case ("x", .command): cut(nil)
        case ("v", .command): pasteAsPlainText(nil)
        case ("z", .command): undoManager?.undo()
        case ("z", [.command, .shift]): undoManager?.redo()
        default: return false
        }
        return true
    }

    // MARK: - 글이 바뀔 때

    /// 조합을 끝내는 중이다. 그사이 텍스트 뷰가 글을 잠깐 비웠다가 다시 넣을 수 있어, 끝난 뒤에 한 번만 알린다.
    private var isUnmarking = false

    private func notifyTextChange() {
        guard !isUnmarking else { return }
        onTextChange?()
    }

    override func didChangeText() {
        super.didChangeText()
        notifyTextChange()
    }

    /// 조합 중인 글자가 바뀔 때는 `didChangeText`가 오지 않는다.
    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        notifyTextChange()
    }

    override func unmarkText() {
        isUnmarking = true
        super.unmarkText()
        isUnmarking = false
        notifyTextChange()
    }

    /// 붙여 넣은 글의 줄바꿈과 탭은 공백으로 바꿔 넣는다.
    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        guard let replacement = replacementString,
              replacement.rangeOfCharacter(from: Self.lineBreaksAndTabs) != nil
        else { return super.shouldChangeText(in: affectedCharRange, replacementString: replacementString) }
        let flattened = replacement.components(separatedBy: Self.lineBreaksAndTabs).joined(separator: " ")
        insertText(flattened, replacementRange: affectedCharRange)
        return false
    }

    private static let lineBreaksAndTabs = CharacterSet.newlines.union(CharacterSet(charactersIn: "\t"))

    // MARK: - 커서

    /// 얇은 일반 커서(규칙 15).
    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        var thin = rect
        thin.size.width = caretWidth
        super.drawInsertionPoint(in: thin, color: color, turnedOn: flag)
    }

    override func setNeedsDisplay(_ rect: NSRect, avoidAdditionalLayout flag: Bool) {
        super.setNeedsDisplay(rect.insetBy(dx: -caretWidth, dy: 0), avoidAdditionalLayout: flag)
    }
}
