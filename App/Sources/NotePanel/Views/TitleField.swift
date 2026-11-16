import AppKit
import Theme

/// 상단 줄의 제목 칸(규칙 12: 본문과 별개). 평소에는 글자만 보이고, 누르면 그 자리에서 고친다.
/// 고칠 때도 상자는 없고 글자가 `text`가 되며 커서만 생긴다(spec 5.2).
final class TitleField: NSTextField, NSTextFieldDelegate {
    /// 고치는 중에 글자가 바뀔 때마다.
    var onChange: ((String) -> Void)?
    var onEditingChange: ((Bool) -> Void)?
    /// Return으로 끝냈을 때.
    var onReturn: (() -> Void)?

    private let style: PanelStyle
    private(set) var isEditing = false
    private var titleBeforeEditing = ""
    private var isPlaceholder = false
    private var colorToken: ColorToken = .text3

    init(style: PanelStyle) {
        self.style = style
        super.init(frame: .zero)
        wantsLayer = true
        isBordered = false
        isBezeled = false
        drawsBackground = false
        isEditable = false
        isSelectable = false
        focusRingType = .none
        usesSingleLineMode = true
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

    // MARK: - 고치기

    func beginEditing(title: String) {
        guard !isEditing, let window else { return }
        isEditing = true
        titleBeforeEditing = title
        isEditable = true
        isSelectable = true
        stringValue = title
        font = style.theme.nsFont(.title)
        textColor = style.color(.text)
        placeholderAttributedString = NSAttributedString(
            string: TopRowState.untitled,
            attributes: [
                .font: style.theme.nsFont(.title, weight: style.theme.tokens.textStyle(.body).weight),
                .foregroundColor: style.color(.text3),
            ]
        )
        onEditingChange?(true)
        window.makeFirstResponder(self)
        if let editor = currentEditor() as? NSTextView {
            editor.insertionPointColor = style.color(.accent)
            editor.setSelectedRange(NSRange(location: (title as NSString).length, length: 0))
        }
    }

    func endEditing() {
        guard isEditing else { return }
        window?.makeFirstResponder(nil)
    }

    func controlTextDidChange(_ notification: Notification) {
        onChange?(stringValue)
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard isEditing else { return }
        isEditing = false
        isEditable = false
        isSelectable = false
        placeholderAttributedString = nil
        onEditingChange?(false)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.cancelOperation(_:)):
            stringValue = titleBeforeEditing
            onChange?(titleBeforeEditing)
            endEditing()
            return true
        case #selector(NSResponder.insertNewline(_:)):
            endEditing()
            onReturn?()
            return true
        default:
            return false
        }
    }
}
