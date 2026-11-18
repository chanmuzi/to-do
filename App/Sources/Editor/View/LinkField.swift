import AppKit
import Theme

/// 링크 주소를 적는 작은 칸. 고른 글자 바로 아래에 본문 뷰의 하위 뷰로 놓인다(창을 따로 띄우지 않는다).
/// Return으로 넣고 Esc나 다른 곳을 누르면 그만둔다.
final class LinkField: NSView, NSTextFieldDelegate {
    var onCommit: ((String) -> Void)?
    var onCancel: (() -> Void)?
    let input: CommandInputField
    private var padX: CGFloat = 0

    init(theme: Theme) {
        input = CommandInputField(theme: theme)
        super.init(frame: .zero)
        wantsLayer = true
        input.lineBreakMode = .byTruncatingHead
        input.cell?.isScrollable = true
        input.delegate = self
        input.setAccessibilityLabel("링크 주소")
        addSubview(input)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var address: String {
        get { input.stringValue }
        set { input.stringValue = newValue }
    }

    func apply(theme: Theme, style: EditorStyle) {
        padX = style.metrics.linkFieldPadX
        layer?.backgroundColor = style.surface2.cgColor
        layer?.borderColor = style.line.cgColor
        layer?.borderWidth = style.borderWidth
        layer?.cornerRadius = theme.shape(.controlRadius)
        input.apply(font: theme.nsFont(.ui), ink: style.text, placeholder: "https://", placeholderInk: style.text3)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let height = ceil(input.intrinsicContentSize.height)
        input.frame = CGRect(x: padX, y: ((bounds.height - height) / 2).rounded(), width: max(0, bounds.width - padX * 2), height: height)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard !textView.hasMarkedText() else { return false }
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            onCommit?(input.stringValue)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onCancel?()
            return true
        default:
            return false
        }
    }

    /// 다른 곳을 눌러 칸이 포커스를 잃으면 그만둔다.
    func controlTextDidEndEditing(_ notification: Notification) {
        onCancel?()
    }
}
