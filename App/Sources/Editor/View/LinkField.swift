import AppKit
import Theme

/// 링크 주소를 적는 작은 칸. 고른 글자 바로 아래에 본문 뷰의 하위 뷰로 놓인다(창을 따로 띄우지 않는다).
/// Return으로 넣고 Esc나 다른 곳을 누르면 그만둔다.
final class LinkField: NSView, NSTextFieldDelegate {
    var onCommit: ((String) -> Void)?
    var onCancel: (() -> Void)?
    let input = NSTextField()
    private var padX: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        input.isBordered = false
        input.isBezeled = false
        input.drawsBackground = false
        input.focusRingType = .none
        input.usesSingleLineMode = true
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
        input.font = theme.nsFont(.ui)
        input.textColor = style.text
        // 빈 칸이 무엇을 받는지 알 수 있게 주소의 머리만 흐리게 보인다(안내 문장은 두지 않는다, 규칙 3).
        input.placeholderAttributedString = NSAttributedString(
            string: "https://",
            attributes: [.font: theme.nsFont(.ui), .foregroundColor: style.text3]
        )
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let height = ceil(input.intrinsicContentSize.height)
        input.frame = CGRect(x: padX, y: ((bounds.height - height) / 2).rounded(), width: max(0, bounds.width - padX * 2), height: height)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
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
