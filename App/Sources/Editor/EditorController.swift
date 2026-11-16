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
    /// 바깥이 마지막으로 알고 있는 값과 달라졌을 때만 한 번 부른다.
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
    /// 바깥이 알고 있는 접힘(바깥에서 넣었거나 마지막으로 알린 값). 이것과 달라지면 `onFoldChange`를 부른다.
    var reportedFolds: Set<Int> = []
    /// 원문이 바뀌기 직전의 접힘. 편집이 접힘을 바꿨으면 되돌리기에 함께 적는다.
    var foldsBeforeEdit: Set<Int>?
    /// 마지막으로 알린 뒤에 원문에 가해진 편집들(바뀌기 전의 원문, 바뀐 범위, 길이 변화).
    var editsSinceFlush: [(old: MarkdownDocument, range: NSRange, delta: Int)] = []
    /// 접힌 줄 번호를 스스로 정한 편집(줄 옮기기, 줄 머리 바꾸기)이 있었다. 되돌릴 때 접힘을 그대로 되살려야 한다.
    var editSetFoldsExplicitly = false
    /// 되돌리기, 다시 하기가 진행 중이다.
    var isReplayingUndo = false
    /// 되돌리기, 다시 하기가 시작될 때의 접힘과, 끝난 뒤에 되살릴 접힘.
    var foldsBeforeUndo: Set<Int>?
    var pendingFoldRestore: Set<Int>?
    /// 원문이 바뀌었는데 아직 바깥에 알리지 않았다(조합 중인 글자는 `textDidChange`가 오지 않는다).
    var hasPendingChange = false
    var isFlushScheduled = false
    var isHeightReportScheduled = false
    /// 텍스트 뷰에 넣어 둔 문서 끝 빈 줄의 문단 모양(`updateTrailingLineStyle`).
    var appliedTrailingStyle: NSParagraphStyle?
    /// 지금 넣는 편집이 접혀서 감춘 줄까지 일부러 고치는 것인지(`TextEdit.includesHiddenLines`).
    var allowsHiddenEdit = false
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

    /// 원문. 줄바꿈은 언제나 `\n`이다(넣을 때 `\r\n`, `\r`, U+2028, U+2029를 `\n`으로 바꾼다).
    /// 넣을 때는 `onTextChange`를 부르지 않고, 같은 글이면 아무것도 하지 않는다.
    /// 다른 글을 넣으면 되돌리기 기록을 비우고, 커서는 가능한 한 제자리에 둔다.
    /// 새 글에서 토글이 아니게 된 줄의 접힘은 버리고 `onFoldChange`로 알린다.
    var text: String {
        get { document.text }
        set {
            let normalized = LineEndings.normalized(newValue)
            guard normalized != document.text else { return }
            replaceText(normalized)
            notifyFoldChangeIfNeeded()
        }
    }

    /// 노트를 연다. 원문과 접힘을 한 번에 넣고 아무것도 알리지 않는다.
    func load(text newText: String, foldedLines: Set<Int>) {
        let normalized = LineEndings.normalized(newText)
        if normalized != document.text { replaceText(normalized) }
        setFolded(foldedLines, notify: false)
    }

    /// 접힌 토글의 줄 번호(0부터). 원문에는 적지 않는 보기 상태다. 지금 원문에서 토글이 아닌 줄 번호는 버린다.
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
        observeUndo()
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
        appliedTrailingStyle = nil
        textView.defaultParagraphStyle = nil
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

    private func replaceText(_ newText: String) {
        guard let storage = textView.textStorage else { return }
        let selection = textView.selectedRange()
        isSettingText = true
        if textView.hasMarkedText() { textView.unmarkText() }
        storage.setAttributedString(NSAttributedString(string: newText, attributes: baseAttributes))
        editorUndoManager.removeAllActions()
        hasPendingChange = false
        foldsBeforeEdit = nil
        editsSinceFlush = []
        editSetFoldsExplicitly = false
        pendingFoldRestore = nil
        isSettingText = false
        textView.setSelectedRange(clamped(selection))
        hoveredLink = nil
        setHoveredCodeBlock(nil)
        restyleAll()
        reportContentHeight()
    }

    /// - Parameter notify: 사용자가 접고 편 것이면 `true`. 바깥에서 넣은 값이면 `false`(알리지 않는다).
    func setFolded(_ newValue: Set<Int>, notify: Bool) {
        applyFolds(newValue)
        if notify { notifyFoldChangeIfNeeded() } else { reportedFolds = folded }
    }

    /// 접힘을 바꾸고 화면에 입힌다. 알리지는 않는다.
    func applyFolds(_ newValue: Set<Int>) {
        let sanitized = FoldState.sanitized(newValue, in: document)
        guard sanitized != folded else { return }
        folded = sanitized
        refreshStyling()
        reportContentHeight()
    }

    /// 접힘이 바깥이 알고 있는 값과 달라졌으면 알린다. 되돌리는 중에는 끝난 뒤에 한 번만 알린다.
    func notifyFoldChangeIfNeeded() {
        guard !isReplayingUndo, folded != reportedFolds else { return }
        reportedFolds = folded
        onFoldChange?(folded)
    }
}
