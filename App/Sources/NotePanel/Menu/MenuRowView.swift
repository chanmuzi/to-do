import AppKit
import Theme

/// 메뉴 한 줄(spec 5.4): 높이 `row-h`, 왼쪽에 14pt 아이콘, 고르는 중이면 `hover` 바탕. 단축키는 적지 않는다(규칙 4).
final class MenuRowView: NSView {
    private let style: PanelStyle
    private let highlightView = NSView()
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let stateView = NSImageView()
    private var isShowingHighlight = false

    /// - Parameters:
    ///   - isOn: 켜진 항목이면 오른쪽 끝에 체크를 보인다.
    ///   - isDimmed: 누를 수 없는 줄(설명 줄, 아직 이어지지 않은 화면을 여는 항목).
    init(style: PanelStyle, title: String, symbolName: String?, isOn: Bool = false, isDimmed: Bool = false) {
        self.style = style
        let theme = style.theme
        super.init(frame: NSRect(
            x: 0, y: 0, width: theme.component(.menuWidth), height: theme.component(.rowHeight)
        ))
        wantsLayer = true
        autoresizingMask = [.width]
        highlightView.wantsLayer = true
        iconView.image = symbolName.flatMap { style.symbol($0, size: .iconLarge) }
        iconView.contentTintColor = style.color(isDimmed ? .text3 : .text2)
        iconView.imageScaling = .scaleNone
        label.stringValue = title
        label.font = theme.nsFont(.body, size: theme.tokens.textStyle(.title).size)
        label.textColor = style.color(isDimmed ? .text3 : .text)
        label.lineBreakMode = .byTruncatingTail
        stateView.image = isOn ? style.symbol("checkmark", size: .iconSmall) : nil
        stateView.contentTintColor = style.color(.text3)
        stateView.imageScaling = .scaleNone
        [highlightView, iconView, label, stateView].forEach(addSubview)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("코드로만 만든다")
    }

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    override func layout() {
        super.layout()
        let theme = style.theme
        let edge = theme.space(.sp1)
        let icon = theme.component(.iconLarge)
        let state = theme.component(.iconSmall)
        func centered(x: CGFloat, width: CGFloat, height: CGFloat) -> NSRect {
            NSRect(x: x, y: ((bounds.height - height) / 2).rounded(), width: width, height: height)
        }
        highlightView.frame = bounds.insetBy(dx: edge, dy: 0)
        let contentX = edge + theme.space(.sp2)
        iconView.frame = theme.symbolFrame(centered(x: contentX, width: icon, height: icon))
        let stateX = bounds.width - contentX - state
        stateView.frame = theme.symbolFrame(centered(x: stateX, width: state, height: state))
        let labelX = contentX + icon + theme.space(.sp2)
        label.frame = centered(
            x: labelX, width: max(0, stateX - theme.space(.sp2) - labelX),
            height: label.intrinsicContentSize.height.rounded(.up)
        )
    }

    /// 메뉴가 고른 줄을 바꾸면 다시 그리라는 요청이 온다. 그때 바탕을 `dur` 동안 바꾼다.
    /// 줄의 바탕은 불투명한 `surface`다. 메뉴의 반투명 재질이 뒤의 노트(흰 노트, 색 노트)를 비춰 글자가
    /// 바래 보이지 않게 한다(라이트와 다크 모두).
    override func updateLayer() {
        layer?.backgroundColor = style.cgColor(.surface, in: self)
        // 메뉴 위아래 여백도 같은 바탕으로 칠한다. 반투명 여백이 뒤를 비쳐 어두운 띠가 생기지 않게 한다.
        fillEnclosingMenuBackground(with: style.cgColor(.surface, in: self))
        highlightView.layer?.cornerRadius = style.theme.shape(.chipRadius)
        let highlighted = enclosingMenuItem?.isHighlighted == true && enclosingMenuItem?.isEnabled == true
        guard highlighted != isShowingHighlight else { return }
        isShowingHighlight = highlighted
        style.animate {
            highlightView.layer?.backgroundColor = highlighted ? style.cgColor(.hover, in: self) : CGColor.clear
        }
    }

    /// 줄 안의 글자와 아이콘이 누름을 가로채지 않게 줄이 통째로 받는다(글자 칸은 제 누름 처리로 뗀 이벤트를 삼킬 수 있다).
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, frame.contains(point) else { return nil }
        return self
    }

    override func mouseUp(with event: NSEvent) {
        guard let item = enclosingMenuItem, item.isEnabled, let menu = item.menu else { return }
        menu.cancelTracking()
        menu.performActionForItem(at: menu.index(of: item))
    }
}
