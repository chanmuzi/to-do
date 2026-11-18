import AppKit
import Models
import Theme
import DateTime

/// 상단 줄의 제목 칸(규칙 12: 본문과 별개). 평소에는 글자만 보이고, 누르면 그 자리에서 고친다.
/// 고칠 때도 상자는 없고 글자가 `text`가 되며 커서만 생긴다(spec 5.2).
final class TitleField: NSTextField, NSTextFieldDelegate {
    /// 고치는 중에 글자가 바뀔 때마다.
    var onChange: ((String) -> Void)?
    var onEditingChange: ((Bool) -> Void)?
    /// Return으로 끝냈을 때.
    var onReturn: (() -> Void)?
    var recognizesDates = true { didSet { if oldValue != recognizesDates { updateDateSuggestion() } } }
    var onAcceptDate: ((InlineDateAcceptance) throws -> InlineDateEffect)?
    var onDateError: (Error) -> Void = { _ in }
    var dateSuggestion: InlineDateProposal?
    var dismissedDate: String?
    var dateObserver: NSObjectProtocol?

    isolated deinit {
        if let dateObserver { NotificationCenter.default.removeObserver(dateObserver) }
    }

    let style: PanelStyle
    private(set) var isEditing = false
    var titleBeforeEditing = ""
    private var isPlaceholder = false
    private var colorToken: ColorToken = .text3

    init(style: PanelStyle) {
        self.style = style
        super.init(frame: .zero)
        cell = PlainTextInputCell(textCell: "")
        wantsLayer = true
        isBordered = false
        isBezeled = false
        drawsBackground = false
        isEditable = false
        isSelectable = false
        focusRingType = .none
        // 단일 줄 셀의 축약된 글꼴 메트릭과 필드 편집기의 TextKit 메트릭이 달라
        // Pretendard에서 편집을 시작할 때 기준선이 움직였다. 같은 줄 배치를 사용한다.
        usesSingleLineMode = false
        maximumNumberOfLines = 1
        lineBreakMode = .byTruncatingTail
        cell?.truncatesLastVisibleLine = true
        cell?.isScrollable = true
        delegate = self
        setAccessibilityLabel("제목")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("코드로만 만든다")
    }

    /// 제목이 다 보이는 너비.
    var idealWidth: CGFloat {
        (cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: 10_000, height: 10_000)).width ?? 0).rounded(.up)
    }

    var idealHeight: CGFloat {
        (cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: 10_000, height: 10_000)).height ?? 0).rounded(.up)
    }

    /// 고치는 중에는 글자를 건드리지 않고 색만 맞춘다.
    func show(title: String, isPlaceholder: Bool, color: ColorToken, animated: Bool) {
        let colorChanged = color != colorToken
        colorToken = color
        if !isEditing {
            self.isPlaceholder = isPlaceholder
            if stringValue != title { stringValue = title }
            font = displayFont
        }
        if colorChanged && animated { style.crossfade(self) }
        textColor = style.color(isEditing ? .text : color)
    }

    func refreshTheme() {
        font = isEditing ? style.theme.nsFont(.title) : displayFont
        textColor = style.color(isEditing ? .text : colorToken)
    }

    /// "제목 없음"은 보통 굵기로 보인다(spec 5.2).
    private var displayFont: NSFont {
        isPlaceholder
            ? style.theme.nsFont(.title, weight: style.theme.tokens.textStyle(.body).weight)
            : style.theme.nsFont(.title)
    }

    var titleCursor: NSCursor { isEditing && window?.isKeyWindow == true ? .iBeam : .arrow }

    override func resetCursorRects() { addCursorRect(bounds, cursor: titleCursor) }
    override func cursorUpdate(with event: NSEvent) { titleCursor.set() }

    // MARK: - 고치기

    func beginEditing(title: String) {
        guard !isEditing, let window else { return }
        isEditing = true
        titleBeforeEditing = NoteTitle.singleLine(title)
        isEditable = true
        isSelectable = true
        stringValue = titleBeforeEditing
        font = style.theme.nsFont(.title)
        textColor = style.color(.text)
        placeholderAttributedString = NSAttributedString(
            string: TopRowState.untitled,
            attributes: [
                .font: style.theme.nsFont(.title, weight: style.theme.tokens.textStyle(.body).weight),
                .foregroundColor: style.color(.text3),
            ]
        )
        window.invalidateCursorRects(for: self)
        onEditingChange?(true)
        window.makeFirstResponder(self)
        if let editor = currentEditor() as? NSTextView {
            observeDateSelection(editor)
            editor.insertionPointColor = style.color(.accent)
            editor.setSelectedRange(NSRange(location: (stringValue as NSString).length, length: 0))
        }
    }

    func endEditing() {
        guard isEditing else { return }
        window?.makeFirstResponder(nil)
    }

    func controlTextDidChange(_ notification: Notification) {
        // 조합 범위를 고쳐 쓰면 입력기가 끊긴다. 확정/편집 종료 때 한 줄로 정리한다.
        guard (currentEditor() as? NSTextView)?.hasMarkedText() != true else { hideDateSuggestion(); return }
        onChange?(normalizeTitle())
        updateDateSuggestion()
    }

    @discardableResult
    private func normalizeTitle() -> String {
        let editor = currentEditor() as? NSTextView
        let text = editor?.string ?? stringValue
        let title = NoteTitle.singleLine(text)
        guard title != text else { return title }
        let selection = editor?.selectedRange()
        stringValue = title
        if let editor, let selection, selection.location != NSNotFound {
            // CRLF가 한 글자로 줄어도 UTF-16 선택 위치를 보존한다(이모지 포함).
            let source = text as NSString
            let start = NoteTitle.singleLine(source.substring(to: min(selection.location, source.length))).utf16.count
            let end = NoteTitle.singleLine(source.substring(to: min(NSMaxRange(selection), source.length))).utf16.count
            editor.string = title
            editor.setSelectedRange(NSRange(location: start, length: end - start))
        }
        return title
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard isEditing else { return }
        isEditing = false
        hideDateSuggestion()
        isEditable = false
        isSelectable = false
        placeholderAttributedString = nil
        // 조합 중이던 글자는 편집이 끝나면서 확정되는데, 그때는 글자가 바뀌었다는 알림이 오지 않는다.
        // 칸에 보이는 마지막 값을 넘겨 저장소가 화면과 같은 제목을 갖게 한다.
        onChange?(normalizeTitle())
        window?.invalidateCursorRects(for: self)
        onEditingChange?(false)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if textView.hasMarkedText() {
            hideDateSuggestion()
            return onAcceptDate != nil && (selector == #selector(NSResponder.insertTab(_:)) || selector == #selector(NSResponder.insertBacktab(_:)))
        }
        switch selector {
        case #selector(NSResponder.insertTab(_:)) where dateSuggestion != nil:
            return acceptDateSuggestion(in: textView)
        case #selector(NSResponder.cancelOperation(_:)):
            if dateSuggestion != nil {
                dismissedDate = textView.string
                updateDateSuggestion()
                return true
            }
            stringValue = titleBeforeEditing
            onChange?(titleBeforeEditing)
            endEditing()
            return true
        case #selector(NSResponder.insertTab(_:)),
             #selector(NSResponder.insertNewline(_:)),
             #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)),
             #selector(NSResponder.insertLineBreak(_:)),
             #selector(NSResponder.insertParagraphSeparator(_:)):
            endEditing()
            onReturn?()
            return true
        default:
            return false
        }
    }
}
