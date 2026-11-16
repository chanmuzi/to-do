import AppKit
import Theme

/// 줄별 모양을 정하는 상태. 이 값이 같으면 모양도 같다.
struct KeyStamp: Equatable {
    var documentVersion: Int
    var active: ClosedRange<Int>?
    var folded: Set<Int>
    var hoveredLine: Int?
    var hoveredOffset: Int?
}

/// 편집기의 실제 구현. TextKit 2 스택과 텍스트 뷰를 들고, 원문을 풀어 화면에 입히고, 명령을 실행한다.
/// 공개 창구는 `MarkdownEditor`다.
@MainActor
final class EditorController: NSObject {
    /// 사용자가 고쳐서 원문이 바뀌었을 때. `text`를 직접 넣을 때는 부르지 않는다.
    var onTextChange: ((String) -> Void)?
    /// 내용 높이(안쪽 여백 포함)가 바뀌었을 때. 노트 창이 이 높이에 맞춘다.
    var onContentHeightChange: ((CGFloat) -> Void)?
    /// 접힌 토글이 바뀌었을 때(사용자가 접고 폈거나, 원문이 바뀌어 줄 번호가 옮겨졌을 때).
    var onFoldChange: ((Set<Int>) -> Void)?
    /// 링크를 눌렀을 때. 정하지 않으면 기본 브라우저로 연다.
    var onOpenLink: ((URL) -> Void)?

    var configuration: MarkdownEditorConfiguration {
        didSet {
            guard configuration != oldValue else { return }
            reloadStyle()
        }
    }

    let theme: Theme
    var style: EditorStyle
    let contentStorage = NSTextContentStorage()
    let layoutManager = NSTextLayoutManager()
    let textContainer = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
    let textView: EditorTextView
    let scrollView = NSScrollView()
    let editorUndoManager = UndoManager()
    let copyButton = CodeCopyButton()

    var document = MarkdownDocument("")
    var folded: Set<Int> = []
    /// 화면에 입혀 둔 줄별 모양. 다음 모양과 견주어 달라진 줄만 다시 입힌다.
    var appliedKeys: [LineRenderKey] = []
    var isApplyingEdit = false
    var isSettingText = false
    var isRestyling = false
    var hoveredLink: (line: Int, offset: Int)?
    var hoveredCodeBlock: ClosedRange<Int>?
    var lastContentHeight: CGFloat = -1
    var observers: [NSObjectProtocol] = []
    /// 창이 키 창이 아니어도 편집 중인 것처럼 기호를 보인다(확인용).
    var forcesActiveAppearance = false {
        didSet { refreshStyling() }
    }
    /// 원문이 바뀔 때마다 올린다. 줄별 모양을 다시 계산할지 가리는 데 쓴다.
    var documentVersion = 0
    var keysCache: (stamp: KeyStamp, keys: [LineRenderKey])?
    /// 원문이 바뀌면서 접힌 줄 번호가 옮겨졌는지(다음 `textDidChange`에서 알린다).
    var foldChangedByEdit = false
    /// 코드 블록 복사 버튼이 쓰는 클립보드.
    var codePasteboard: NSPasteboard = .general

    init(theme: Theme, configuration: MarkdownEditorConfiguration = MarkdownEditorConfiguration()) {
        self.theme = theme
        self.configuration = configuration
        self.style = EditorStyle(theme: theme, configuration: configuration, increaseContrast: Self.increaseContrast)
        layoutManager.textContainer = textContainer
        contentStorage.addTextLayoutManager(layoutManager)
        textView = EditorTextView(frame: .zero, textContainer: textContainer)
        super.init()
        configureViews()
        applyStyleToViews()
        observeEnvironment()
    }

    // MARK: 공개

    /// 편집기 뷰(스크롤 뷰). 바탕은 그리지 않는다.
    var view: NSView { scrollView }

    /// 원문. 넣을 때는 `onTextChange`를 부르지 않고, 같은 글이면 아무것도 하지 않는다.
    /// 다른 글을 넣으면 되돌리기 기록을 비우고, 커서는 가능한 한 제자리에 둔다.
    var text: String {
        get { document.text }
        set { setText(newValue) }
    }

    /// 접힌 토글의 줄 번호(0부터). 원문에는 적지 않는 보기 상태다. 토글이 아닌 줄 번호는 버린다.
    var foldedLines: Set<Int> {
        get { folded }
        set { setFolded(newValue, notify: false) }
    }

    /// 지금의 내용 높이(안쪽 여백 포함).
    var contentHeight: CGFloat { measureContentHeight() }

    /// 선택 범위(원문의 UTF-16 위치).
    var selectedRange: NSRange {
        get { textView.selectedRange() }
        set { textView.setSelectedRange(clamped(newValue)) }
    }

    /// 본문에 포커스를 준다.
    func focus() {
        textView.window?.makeFirstResponder(textView)
    }

    /// 편집 동작을 실행한다(단축키와 같은 일).
    func perform(_ action: EditorAction) {
        run(action)
    }

    // MARK: 구성

    private func configureViews() {
        textContainer.widthTracksTextView = true
        textContainer.lineFragmentPadding = 0
        contentStorage.delegate = self
        layoutManager.delegate = self

        textView.editor = self
        textView.delegate = self
        textView.textStorage?.delegate = self
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.setAccessibilityLabel("본문")

        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        copyButton.onPress = { [weak self] in self?.copyHoveredCodeBlock() }
        textView.addSubview(copyButton)
    }

    /// 글꼴, 색, 여백을 뷰에 옮긴다.
    private func applyStyleToViews() {
        let padding = theme.docPadding
        textView.textContainerInset = NSSize(
            width: (padding.leading + padding.trailing) / 2,
            height: (padding.top + padding.bottom) / 2
        )
        textView.containerOrigin = NSPoint(x: padding.leading, y: padding.top)
        textView.caretWidth = theme.component(.caretWidth)
        textView.insertionPointColor = style.accent
        textView.font = style.body.font
        textView.textColor = style.text
        textView.typingAttributes = baseAttributes
        textView.selectedTextAttributes = [.backgroundColor: theme.rgba(.hover).nsColor]
        copyButton.apply(theme: theme, tint: style.text3)
    }

    /// 원문에 붙여 두는 기본 속성. 화면의 서식은 여기 넣지 않는다.
    var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: style.body.font, .foregroundColor: style.text]
    }

    private func observeEnvironment() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: Theme.didChangeNotification, object: theme, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadStyle() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadStyle() }
        })
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let windowID = (note.object as AnyObject?).map(ObjectIdentifier.init)
                MainActor.assumeIsolated {
                    guard let self, windowID == self.textView.window.map(ObjectIdentifier.init) else { return }
                    self.refreshStyling()
                }
            })
        }
    }

    isolated deinit {
        MainActor.assumeIsolated {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        }
    }

    static var increaseContrast: Bool { NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast }
    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// 테마나 설정이 바뀌면 모양 값을 다시 풀고 모든 줄을 다시 입힌다.
    func reloadStyle() {
        style = EditorStyle(theme: theme, configuration: configuration, increaseContrast: Self.increaseContrast)
        applyStyleToViews()
        if let storage = textView.textStorage, storage.length > 0 {
            isRestyling = true
            storage.addAttributes(baseAttributes, range: NSRange(location: 0, length: storage.length))
            isRestyling = false
        }
        restyleAll()
        reportContentHeight()
    }

    func clamped(_ range: NSRange) -> NSRange {
        let location = min(max(range.location, 0), document.length)
        return NSRange(location: location, length: min(max(range.length, 0), document.length - location))
    }

    // MARK: 원문 넣기

    private func setText(_ newText: String) {
        guard newText != document.text, let storage = textView.textStorage else { return }
        let selection = textView.selectedRange()
        isSettingText = true
        if textView.hasMarkedText() { textView.unmarkText() }
        storage.setAttributedString(NSAttributedString(string: newText, attributes: baseAttributes))
        editorUndoManager.removeAllActions()
        isSettingText = false
        textView.setSelectedRange(clamped(selection))
        hoveredLink = nil
        setHoveredCodeBlock(nil)
        restyleAll()
        reportContentHeight()
    }

    func setFolded(_ newValue: Set<Int>, notify: Bool) {
        let sanitized = FoldState.sanitized(newValue, in: document)
        guard sanitized != folded else { return }
        folded = sanitized
        refreshStyling()
        reportContentHeight()
        if notify { onFoldChange?(folded) }
    }
}
