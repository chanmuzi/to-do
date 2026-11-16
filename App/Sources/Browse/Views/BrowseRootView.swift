import AppKit
import Theme

/// 노트 찾기의 내용(spec 8, 화면 9): `surface` 바탕에 `outline` 테두리, 안쪽 여백 6, 모서리 8.
/// 위에 검색 칸, 그 아래에 목록. 목록이 높이 한도를 넘으면 스크롤된다.
final class BrowseRootView: NSView {
    private let style: BrowseStyle
    let searchField: BrowseSearchField
    let listView: BrowseListView
    private let scrollView = NSScrollView()

    init(style: BrowseStyle) {
        self.style = style
        searchField = BrowseSearchField(style: style)
        listView = BrowseListView(style: style)
        super.init(frame: .zero)
        wantsLayer = true

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        // 스크롤 막대는 스크롤할 때만 보인다(spec 16).
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.documentView = listView
        [searchField, scrollView].forEach(addSubview)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("코드로만 만든다")
    }

    /// 검색 칸과 위아래 여백을 더한, 목록을 뺀 높이.
    private var chromeHeight: CGFloat {
        let theme = style.theme
        return theme.component(.browsePadding) * 2
            + theme.component(.browseFindHeight) + theme.component(.browseFindGap)
    }

    /// 내용에 맞는 창 높이. `limit`을 넘지 않는다.
    /// 스크롤 막대는 내용이 한도를 넘을 때만 둔다(높이가 내용을 따라가는 동안 잠깐 나타나지 않게).
    func fittingHeight(limit: CGFloat) -> CGFloat {
        let wanted = chromeHeight + listView.contentHeight
        scrollView.hasVerticalScroller = wanted > max(limit, chromeHeight)
        return min(wanted, max(limit, chromeHeight))
    }

    func refreshTheme() {
        searchField.refreshTheme()
        listView.refreshTheme()
        needsDisplay = true
        needsLayout = true
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let theme = style.theme
        layer?.cornerRadius = theme.component(.browseRadius)
        layer?.borderWidth = theme.shape(.borderWidth)
        layer?.borderColor = style.cgColor(.outline, in: self)
        layer?.backgroundColor = style.cgColor(.surface, in: self)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let theme = style.theme
        let padding = theme.component(.browsePadding)
        let width = max(0, bounds.width - padding * 2)
        searchField.frame = NSRect(x: padding, y: padding, width: width, height: theme.component(.browseFindHeight))
        let listTop = searchField.frame.maxY + theme.component(.browseFindGap)
        scrollView.frame = NSRect(
            x: padding, y: listTop, width: width, height: max(0, bounds.height - padding - listTop)
        )
        listView.frame.size = NSSize(width: width, height: listView.contentHeight)
    }
}
