import AppKit
import Theme

/// 서식 없는 기본 본문 편집기. Markdown 편집기(Editor 모듈)가 끼워지기 전까지 노트 창을 쓸 수 있게 한다.
public final class PlainTextBodyEditor: NSObject, NoteBodyEditing, NSTextViewDelegate, NSLayoutManagerDelegate {
    public var onTextChange: ((String) -> Void)?
    public var onContentHeightChange: ((CGFloat) -> Void)?

    private let theme: Theme
    private let textView: PlainBodyTextView
    private let layoutManager = NSLayoutManager()
    private let container = NSTextContainer(
        size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
    )
    private var reportedHeight: CGFloat?
    /// 이 편집기만의 실행 취소 기록. 창의 것을 함께 쓰면 본문을 비울 때 제목 칸의 기록까지 지워진다.
    private let undoManager = UndoManager()
    /// 밖에서 글을 넣는 중. 이때 생기는 변경 알림(조합을 끊으며 나오는 것)은 사용자가 고친 것이 아니다.
    private var isAssigningText = false
    private var themeObservation: (any NSObjectProtocol)?

    public init(theme: Theme) {
        self.theme = theme
        let storage = NSTextStorage()
        storage.addLayoutManager(layoutManager)
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        layoutManager.usesFontLeading = false
        textView = PlainBodyTextView(frame: .zero, textContainer: container)
        super.init()
        configure()
        applyTheme()
        observe()
    }

    public var view: NSView { textView }

    public var text: String {
        get { textView.string }
        set {
            guard newValue != textView.string else { return }
            isAssigningText = true
            defer { isAssigningText = false }
            let selection = textView.selectedRange()
            if textView.hasMarkedText() { textView.unmarkText() }
            textView.breakUndoCoalescing()
            textView.string = newValue
            // 밖에서 넣은 글은 실행 취소 기록에 없다. 옛 기록을 남기면 ⌘Z가 새 글에 없는 범위를 건드린다.
            undoManager.removeAllActions()
            applyTextAttributes()
            let length = (newValue as NSString).length
            textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
            measure()
        }
    }

    public func focus() {
        textView.window?.makeFirstResponder(textView)
    }

    public func undoManager(for view: NSTextView) -> UndoManager? {
        undoManager
    }

    public func textDidChange(_ notification: Notification) {
        measure()
        guard !isAssigningText else { return }
        onTextChange?(textView.string)
    }

    /// 줄 높이(`lh-body`)가 글꼴보다 크면 글자가 줄 아래쪽에 붙는다. 남는 높이의 반만큼 올려 가운데에 둔다.
    public func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>,
        lineFragmentUsedRect: UnsafeMutablePointer<NSRect>,
        baselineOffset: UnsafeMutablePointer<CGFloat>,
        in textContainer: NSTextContainer,
        forGlyphRange glyphRange: NSRange
    ) -> Bool {
        let extra = theme.lineHeight(.body) - layoutManager.defaultLineHeight(for: theme.nsFont(.body))
        guard extra > 0 else { return false }
        baselineOffset.pointee -= (extra / 2).rounded(.down)
        return true
    }

    // MARK: - 설정

    private func configure() {
        textView.delegate = self
        layoutManager.delegate = self
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.setAccessibilityLabel("본문")
    }

    private func observe() {
        // 테마는 메인에서만 알린다. queue를 주지 않아 알린 그 자리에서 바로 받는다.
        themeObservation = NotificationCenter.default.addObserver(
            forName: Theme.didChangeNotification, object: theme, queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyTheme() }
        }
        textView.onWidthChange = { [weak self] in self?.measure() }
    }

    isolated deinit {
        if let themeObservation { NotificationCenter.default.removeObserver(themeObservation) }
    }

    private func applyTheme() {
        textView.padding = theme.docPadding
        textView.caretWidth = theme.component(.caretWidth)
        textView.insertionPointColor = theme.nsColor(.accent)
        textView.textColor = theme.nsColor(.text)
        textView.selectedTextAttributes = [.backgroundColor: theme.nsColor(.hover)]
        applyTextAttributes()
        measure()
    }

    private var textAttributes: [NSAttributedString.Key: Any] {
        let font = theme.nsFont(.body)
        let lineHeight = theme.lineHeight(.body)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        paragraph.lineBreakMode = .byWordWrapping
        return [
            .font: font,
            .foregroundColor: theme.nsColor(.text),
            .paragraphStyle: paragraph,
        ]
    }

    private func applyTextAttributes() {
        let attributes = textAttributes
        textView.typingAttributes = attributes
        guard let storage = textView.textStorage, storage.length > 0 else { return }
        storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length))
    }

    /// 여백을 포함한 내용 높이. 빈 노트도 한 줄 높이를 가진다(커서 자리).
    private func measure() {
        guard textView.frame.width > 0 else { return }
        layoutManager.ensureLayout(for: container)
        let used = layoutManager.usedRect(for: container).height
        let padding = theme.docPadding
        let height = (max(used, theme.lineHeight(.body)) + padding.top + padding.bottom).rounded(.up)
        guard height != reportedHeight else { return }
        reportedHeight = height
        onContentHeightChange?(height)
    }
}
