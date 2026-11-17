import AppKit

/// 얇은 입력 커서(spec 02의 규칙 15). 너비 `caret-w`, 색 `accent`, 높이는 커서 자리 글자의 글꼴 상자
/// (ascender부터 descender까지)다. 줄 높이를 따르지 않는다.
///
/// 지금 macOS(14 이상)의 `NSTextView`는 커서를 `NSTextInsertionIndicator`라는 하위 뷰로 보인다. SDK의 머리
/// 파일에 그 뷰가 여는 것은 `displayMode`(자동, 감춤, 보임), `color`, `automaticModeOptions`,
/// `effectsViewInserter`뿐이고 너비와 높이를 정하는 것은 없다(줄 높이 전체를 덮는다). 옛 그리기 경로
/// `drawInsertionPoint(in:color:turnedOn:)`를 덮어써 얇게 그리면 표시 뷰가 따로 남아 커서가 둘이 되고
/// 지워지지 않는 자국이 생겼다(D-025). 그래서 `NSTextView.shouldDrawInsertionPoint`를 `false`로 덮어써
/// 시스템의 커서를 만들지 않게 하고(표시 뷰가 생기지 않는다. 확인용 실행 파일이 `SYSTEM-CARET`으로 적는다),
/// 이 객체가 텍스트 뷰 위에 작은 뷰 하나를 올려 대신한다. 텍스트 뷰의 그림에 그리지 않으므로 자국이 남지 않는다.
///
/// 쓰는 법:
/// 1. 텍스트 뷰의 하위 클래스에서 `shouldDrawInsertionPoint`를 `false`로 덮어쓴다.
/// 2. `TextCaret(textView:theme:)`를 만들어 텍스트 뷰가 들고 있게 한다.
/// 3. 포커스가 바뀔 때(`becomeFirstResponder`, `resignFirstResponder`) 받아들였는지를 넘겨
///    `refresh(focused:)`를, 조합 중인 글자가 바뀔 때(`setMarkedText`, `unmarkText`) `refresh()`를,
///    배치가 끝날 때(`layout()`) `reposition()`을 부른다.
///    선택, 글자, 틀, 키 창, 테마가 바뀌는 것은 스스로 듣는다.
///
/// `NSTextField`에는 `ThinCaretFieldEditor`를 필드 편집기로 넘기면 된다.
///
/// 보이는 때: 텍스트 뷰가 첫 응답자이고 그 창이 키 창이며, 고칠 수 있고, 선택이 비어 있을 때.
/// 옮기거나 글자를 친 직후에는 켜진 채로 있다가 `caret-blink`마다 켜지고 꺼진다. 보이지 않는 동안에는
/// 시계가 돌지 않는다.
@MainActor
public final class TextCaret {
    /// 커서 자리의 글꼴 상자(텍스트 뷰 좌표). `minX`가 글자 사이의 경계이고 너비는 보지 않는다.
    /// 정하지 않으면 `defaultRect()`를 쓴다. 놓을 자리가 없으면 `nil`.
    public var rectProvider: (@MainActor () -> NSRect?)?
    /// 키 창이 아니어도 보인다(화면을 캡처해 확인할 때만 쓴다).
    public var forcesVisible = false {
        didSet { refresh() }
    }

    private weak var textView: NSTextView?
    private let theme: Theme
    private let view = CaretLayerView()
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    public init(textView: NSTextView, theme: Theme) {
        self.textView = textView
        self.theme = theme
        view.isHidden = true
        textView.addSubview(view)
        applyTheme()
        observe(textView)
        refresh()
    }

    isolated deinit {
        timer?.invalidate()
        observers.forEach(NotificationCenter.default.removeObserver)
        view.removeFromSuperview()
    }

    // MARK: 상태

    /// 지금 조건에서 커서가 있어야 하는지(깜빡여 잠깐 꺼진 것과는 무관하다).
    public private(set) var isActive = false
    /// 커서의 틀(텍스트 뷰 좌표). `isActive`일 때만 뜻이 있다.
    public var frame: NSRect { view.frame }
    /// 깜빡이는 중에 꺼져 있는 순간인지.
    public var isBlinkedOff: Bool { isActive && view.isHidden }
    /// 커서의 색.
    public var color: NSColor? { view.color }

    /// 자리와 보임을 다시 정한다.
    /// - Parameters:
    ///   - restartBlink: 켜진 상태에서 깜빡임을 다시 시작한다(옮기거나 글자를 쳤을 때).
    ///   - focused: 텍스트 뷰가 첫 응답자인지. `becomeFirstResponder`, `resignFirstResponder` 안에서는 창이
    ///     아직 첫 응답자를 바꾸기 전이므로 받아들인 결과를 넘긴다. `nil`이면 창에 묻는다.
    public func refresh(restartBlink: Bool = true, focused: Bool? = nil) {
        guard let textView else { return }
        guard shouldShow(in: textView, focused: focused), let rect = (rectProvider ?? { [weak self] in self?.defaultRect() })() else {
            isActive = false
            view.isHidden = true
            stopBlinking()
            return
        }
        // 화소에 맞추되 너비는 그대로 둔다(양 끝을 따로 맞추면 자리에 따라 너비가 1과 2 사이를 오간다).
        let scale = textView.window?.backingScaleFactor ?? 2
        func aligned(_ value: CGFloat) -> CGFloat { (value * scale).rounded() / scale }
        let width = max(1 / scale, aligned(theme.component(.caretWidth)))
        let target = NSRect(x: aligned(rect.minX - width / 2), y: aligned(rect.minY), width: width, height: aligned(rect.height))
        // 움직임 없이 곧바로 옮긴다(레이어의 기본 전환이 끼면 커서가 미끄러져 보인다).
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if view.frame != target { view.frame = target }
        if !isActive || restartBlink { view.isHidden = false }
        CATransaction.commit()
        let wasActive = isActive
        isActive = true
        if restartBlink || !wasActive || timer == nil { startBlinking() }
    }

    /// 자리만 다시 잰다(배치가 달라졌을 때). 깜빡임은 그대로 둔다.
    public func reposition() {
        refresh(restartBlink: false)
    }

    private func shouldShow(in textView: NSTextView, focused: Bool?) -> Bool {
        guard textView.isEditable, textView.selectedRange().length == 0, let window = textView.window,
              focused ?? (window.firstResponder === textView) else { return false }
        return window.isKeyWindow || forcesVisible
    }

    // MARK: 기본 자리

    /// 보통의 텍스트 뷰(필드 편집기 포함)에서의 커서 자리: 커서가 놓인 줄의 세로 가운데에, 다음에 칠 글자의
    /// 글꼴 높이로 놓는다. TextKit 1과 2 어느 쪽에서도 된다(`firstRect(forCharacterRange:actualRange:)`).
    public func defaultRect() -> NSRect? {
        guard let textView, let window = textView.window else { return nil }
        let location = textView.selectedRange().location
        let onScreen = textView.firstRect(forCharacterRange: NSRange(location: location, length: 0), actualRange: nil)
        guard onScreen.height > 0 else { return nil }
        let line = textView.convert(window.convertFromScreen(onScreen), from: nil)
        let font = (textView.typingAttributes[.font] as? NSFont) ?? textView.font ?? .systemFont(ofSize: NSFont.systemFontSize)
        let height = Self.glyphBoxHeight(of: font)
        return NSRect(x: line.minX, y: line.midY - height / 2, width: 0, height: min(height, line.height))
    }

    /// 글꼴 상자의 높이(ascender부터 descender까지).
    public nonisolated static func glyphBoxHeight(of font: NSFont) -> CGFloat {
        font.ascender - font.descender
    }

    // MARK: 깜빡임

    private func startBlinking() {
        stopBlinking()
        let timer = Timer(timeInterval: theme.motion.caretBlink, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopBlinking() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        // 놓인 뒤에 달라진 것(배치, 포커스)이 있으면 여기서 따라잡는다.
        let wasHidden = view.isHidden
        refresh(restartBlink: false)
        guard isActive else { return }
        view.isHidden = !wasHidden
    }

    // MARK: 듣기

    private func observe(_ textView: NSTextView) {
        let center = NotificationCenter.default
        func add(_ name: Notification.Name, object: AnyObject?, restartBlink: Bool, filter: (@MainActor (Notification) -> Bool)? = nil) {
            observers.append(center.addObserver(forName: name, object: object, queue: .main) { [weak self] note in
                // 알림은 메인 스레드에서 온다.
                nonisolated(unsafe) let note = note
                MainActor.assumeIsolated {
                    guard let self, filter?(note) ?? true else { return }
                    self.refresh(restartBlink: restartBlink)
                }
            })
        }
        add(NSTextView.didChangeSelectionNotification, object: textView, restartBlink: true)
        add(NSText.didChangeNotification, object: textView, restartBlink: true)
        add(NSView.frameDidChangeNotification, object: textView, restartBlink: false)
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            add(name, object: nil, restartBlink: true) { [weak textView] note in
                (note.object as AnyObject?) === textView?.window
            }
        }
        observers.append(center.addObserver(forName: Theme.didChangeNotification, object: theme, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applyTheme()
                self?.refresh(restartBlink: false)
            }
        })
    }

    private func applyTheme() {
        view.color = theme.rgba(.accent).nsColor
        if timer != nil { startBlinking() }
    }
}

/// 커서 하나를 그리는 작은 뷰. 마우스를 받지 않는다(아래의 글자가 받는다).
/// 레이어의 바탕색이 아니라 `draw(_:)`로 칠한다: 창 내용을 그려 내는 확인(`cacheDisplay`)에도 찍히게.
/// 텍스트 뷰의 그림과는 따로 그리므로, 옮기거나 감춰도 글자 위에 자국이 남지 않는다.
private final class CaretLayerView: NSView {
    var color: NSColor = .clear {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        let radius = min(bounds.width, bounds.height) / 2
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var isOpaque: Bool { false }
    override var allowsVibrancy: Bool { false }
}
