import AppKit
import Models
import Routing
import Store
import Theme

/// 빠른 캡처 바(spec 7, 화면 3). App이 하나 만들어 `.openCapture`와 어디서나 쓰는 단축키에 잇는다.
///
/// - ↵: 고른 스페이스의 오늘 노트 맨 아래에 투두 한 줄로 넣고 닫는다(없으면 만든다).
/// - ⌘↵: 새 노트를 만들어 띄우도록 `Route.newNote`를 보내고, 만들어졌으면 닫는다.
/// - ⇥: 스페이스를 차례로 바꾼다. ⌘R: 리마인더를 직접 고른다. esc, 바깥 클릭: 닫는다.
@MainActor
public final class CaptureCoordinator {
    private let theme: Theme
    private let notes: any NoteStoring
    private let spaces: SpaceStore
    private let router: any Routing
    private let log: @MainActor (String) -> Void
    private let style: CaptureStyle

    private var panel: CapturePanel?
    private var barView: CaptureBarView?
    private var observers: [NSObjectProtocol] = []
    /// 사라지는 중(알파가 0으로 가는 중)이다. 이때는 보이지 않는 것으로 치고 명령도 받지 않는다.
    private var isClosing = false
    /// 나타나는 전환이 끝날 때 제자리와 끝의 알파로 놓는 일. 움직임이 끝났는지에 기대지 않고 `dur` 뒤에 한다.
    private var entranceSettle: Task<Void, Never>?
    /// 사라지는 전환이 끝날 때 창을 내리는 일. 그사이 다시 띄우면 취소한다.
    private var closingSettle: Task<Void, Never>?
    /// 바가 놓이는 자리. 나타날 때는 이보다 조금 아래에서 올라오고, 사라질 때는 그리로 내려간다.
    private var restingFrame: NSRect = .zero

    /// ⇥로 고른 스페이스. 바를 닫아도 다음에 열 때까지 기억한다.
    private var selectedSpace: SpaceID?
    private var hasSelectedSpace = false
    /// ⌘R로 고른 리마인더. 바를 열 때마다 비운다.
    private var manualReminder: Date?
    /// 이번에 연 뒤로 ⇥를 눌렀는지. 빈 바에는 스페이스를 보이지 않지만(화면 3), 바꾸는 중에는 보여야 한다.
    private var hasCycledSpace = false

    /// 닫히기 시작할 때 불린다. 인자가 참이면 열기 전에 키 입력을 받던 곳으로 포커스를 돌려줄 때다
    /// (esc, ⌘W, ↵로 넣음, `hide()`). 거짓이면 포커스가 갈 곳이 따로 있다(바깥을 누름, ⌘↵로 새 노트를 띄움).
    /// 키 창을 누구에게 돌려줄지는 App이 정한다.
    public var onDismiss: (@MainActor (_ returnsFocus: Bool) -> Void)?
    /// ↵로 넣지 못했을 때 불린다(`log`에도 남는다). App이 사용자에게 알린다. 알리는 동안 바가 키 창에서
    /// 물러나도(알림 창) 닫히지 않고, 돌아오면 적은 글을 그대로 둔 채 다시 입력을 받는다.
    public var onFailure: (@MainActor (Error) -> Void)?
    /// ↵로 넣은 줄이 들어간 노트. 바가 닫히기 시작한 뒤에 한 번 불린다(App이 짧은 알림을 띄운다, D-041).
    public var onCaptured: (@MainActor (NoteID) -> Void)?
    /// 넣지 못한 것을 알리는 중이거나 ⌘↵의 요청이 돌아오기를 기다리는 중이다. 이때는 키 창에서 물러나도
    /// (알림 창, 새로 뜬 노트) 닫지 않는다. 닫을지는 그 일이 끝난 뒤에 정한다.
    private var staysOpenWithoutKey = false

    /// 확인용: 지금 시각과 달력을 바꿔 끼운다.
    @_spi(Verification) public var now: @MainActor () -> Date = { Date() }
    @_spi(Verification) public var calendar: Calendar = .current
    /// 확인용: 거짓이면 바를 띄울 때 키 창으로 만들지 않는다(다른 앱의 입력을 빼앗지 않는다).
    @_spi(Verification) public var takesKeyOnShow = true
    /// 확인용: 거짓이면 창을 화면에 올리되 완전히 투명하게 두고 마우스도 받지 않는다(테스트가 쓰는 사람의 화면을 가리지 않게).
    @_spi(Verification) public var isShownOpaque = true
    /// 확인용: 띄울 화면을 정한다. 없으면 마우스가 있는 화면.
    @_spi(Verification) public var preferredScreen: NSScreen?
    /// 확인용: 알림을 걸 곳. 처음 띄우기 전에만 바꾼다.
    @_spi(Verification) public var notificationCenter: NotificationCenter = .default

    public init(
        theme: Theme,
        notes: any NoteStoring,
        spaces: SpaceStore,
        router: any Routing,
        log: @escaping @MainActor (String) -> Void
    ) {
        self.theme = theme
        self.notes = notes
        self.spaces = spaces
        self.router = router
        self.log = log
        style = CaptureStyle(theme: theme)
    }

    isolated deinit {
        observers.forEach(notificationCenter.removeObserver)
    }

    public var isVisible: Bool { panel?.isVisible == true && !isClosing }

    /// 마우스가 있는 화면(없으면 주 화면)의 가운데 아래쪽에 띄우고 입력 칸에 커서를 둔다.
    public func show() {
        let panel = preparedPanel()
        guard let barView else { return }
        closingSettle?.cancel()
        closingSettle = nil
        isClosing = false
        barView.textView.isEditable = true
        manualReminder = nil
        hasCycledSpace = false
        selectedSpace = CaptureSpaceCycle.initial(
            remembered: hasSelectedSpace ? .some(selectedSpace) : nil, in: spaces.spaces
        )
        barView.textView.string = ""
        barView.textView.undoManager?.removeAllActions()

        restingFrame = frame(on: preferredScreen ?? Self.screenWithMouse())
        // 새로 뜰 때는 조금 아래에서 시작한다. 사라지는 중에 다시 열면 지금 자리에서 되돌아온다.
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.setFrame(offstageFrame, display: false)
        }
        refresh(animated: false)
        barView.layoutSubtreeIfNeeded()

        if takesKeyOnShow {
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
        panel.makeFirstResponder(barView.textView)
        panel.ignoresMouseEvents = !isShownOpaque
        // 떠오르며 나타난다: 자리와 투명도가 함께 `dur`, `ease`로 바뀐다. 바 안의 요소는 창과 함께 움직일 뿐 서로의 자리는 그대로다.
        let resting = restingFrame
        let opaque = isShownOpaque
        style.animate {
            panel.animator().setFrame(resting, display: true)
            if opaque { panel.animator().alphaValue = 1 }
        }
        // 움직임은 꾸밈이다. 제자리에 놓는 일은 `dur` 뒤에 따로 한다(화면이 꺼져 있으면 움직임이 나아가지 않는다).
        entranceSettle?.cancel()
        entranceSettle = style.afterTransition { [weak self] in self?.finishShowing() }
    }

    private func finishShowing() {
        entranceSettle = nil
        guard let panel, panel.isVisible, !isClosing else { return }
        land(panel, frame: restingFrame, alpha: isShownOpaque ? 1 : 0)
    }

    private func finishClosing() {
        closingSettle = nil
        guard let panel, isClosing else { return }
        isClosing = false
        panel.orderOut(nil)
        land(panel, frame: offstageFrame, alpha: 0)
    }

    /// 가던 움직임을 멈추고 끝의 값으로 놓는다.
    private func land(_ panel: NSPanel, frame: NSRect, alpha: CGFloat) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            panel.animator().setFrame(frame, display: true)
            panel.animator().alphaValue = alpha
        }
        panel.setFrame(frame, display: true)
        panel.alphaValue = alpha
    }

    /// `dur` 동안 조금 내려가며 흐려진 뒤 내려간다(나타날 때의 반대).
    /// 포커스를 열기 전의 자리로 돌려줄 때라고 `onDismiss`로 알린다.
    public func hide() {
        dismiss(returningFocus: true)
    }

    private func dismiss(returningFocus: Bool) {
        guard let panel, panel.isVisible, !isClosing else { return }
        isClosing = true
        entranceSettle?.cancel()
        entranceSettle = nil
        // 사라지는 동안에는 글도 명령도 받지 않는다(보이지 않게 된 바가 키 입력을 먹지 않게).
        barView?.textView.isEditable = false
        let offstage = offstageFrame
        style.animate {
            panel.animator().alphaValue = 0
            panel.animator().setFrame(offstage, display: true)
        }
        // 창을 내리는 일은 움직임이 끝났다는 알림이 아니라 `dur` 뒤의 시계가 한다("동작 줄이기"면 바로).
        closingSettle = style.afterTransition { [weak self] in self?.finishClosing() }
        onDismiss?(returningFocus)
    }

    private var offstageFrame: NSRect {
        CapturePlacement.offstageFrame(for: restingFrame, rise: theme.component(.captureRise))
    }

    public func toggle() {
        if isVisible { hide() } else { show() }
    }

    // MARK: - 확인용 창구

    @_spi(Verification) public var window: NSWindow? { panel }
    @_spi(Verification) public var inputView: NSTextView? { barView?.textView }
    /// 오른쪽에 보이는 스페이스와 리마인더 글자, 밑줄 자리, 자리 글자가 보이는지.
    @_spi(Verification) public var displayedSpace: String? { barView?.spaceContent?.text }
    @_spi(Verification) public var displayedReminder: String? { barView?.reminderContent?.text }
    /// 리마인더가 지난 때의 모습(흐린 글자에 가운데 줄)으로 보이는지.
    @_spi(Verification) public var displaysReminderAsPast: Bool { barView?.reminderContent?.isStruckOut ?? false }
    @_spi(Verification) public var underlinedRanges: [NSRange] { barView?.timeUnderlineRanges ?? [] }
    /// 밑줄이 한 곳일 때의 그 자리.
    @_spi(Verification) public var underlinedRange: NSRange? {
        underlinedRanges.count == 1 ? underlinedRanges.first : nil
    }
    /// 바가 놓이는 자리(움직이는 중이어도 끝의 값)와, 나타나기 전과 사라진 뒤의 자리.
    @_spi(Verification) public var settledFrame: NSRect { restingFrame }
    @_spi(Verification) public var entranceFrame: NSRect { offstageFrame }
    @_spi(Verification) public var showsPlaceholder: Bool { barView?.isPlaceholderVisible ?? false }

    // MARK: - 창

    private func preparedPanel() -> CapturePanel {
        if let panel { return panel }
        let size = NSSize(width: theme.component(.captureWidth), height: theme.component(.captureHeight))
        let panel = CapturePanel(contentRect: NSRect(origin: .zero, size: size))
        let barView = CaptureBarView(style: style)
        barView.frame = NSRect(origin: .zero, size: size)
        barView.autoresizingMask = [.width, .height]
        panel.contentView = barView
        barView.textView.onCommand = { [weak self] in self?.perform($0) }
        barView.textView.onTextChange = { [weak self] in self?.refresh(animated: true) }

        let center = notificationCenter
        observers = [
            // 바깥을 누르면 키 창에서 물러난다. 그때 닫는다.
            center.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.resignedKey() }
            },
            center.addObserver(forName: Theme.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.themeDidChange() }
            },
        ]
        self.panel = panel
        self.barView = barView
        return panel
    }

    /// 바깥을 눌렀다. 포커스는 누른 곳에 둔다. 넣지 못한 것을 알리는 중이거나(알림 창이 키 창이 됨)
    /// ⌘↵의 답을 기다리는 중이면 닫지 않는다.
    private func resignedKey() {
        guard !staysOpenWithoutKey else { return }
        dismiss(returningFocus: false)
    }

    private func themeDidChange() {
        guard let panel, let barView else { return }
        barView.refreshTheme()
        if panel.isVisible, !isClosing, let screen = panel.screen ?? NSScreen.main {
            restingFrame = frame(on: screen)
            panel.setFrame(restingFrame, display: true)
        }
        refresh(animated: false)
    }

    private func frame(on screen: NSScreen?) -> NSRect {
        let size = NSSize(width: theme.component(.captureWidth), height: theme.component(.captureHeight))
        guard let screen else { return NSRect(origin: .zero, size: size) }
        return CapturePlacement.frame(
            size: size, visibleFrame: screen.visibleFrame, bottomRatio: theme.ratio(.captureBottomScreen)
        )
    }

    private static func screenWithMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
    }

    // MARK: - 읽기와 표시

    private func interpretation() -> CaptureInterpretation {
        CaptureInterpretation(
            raw: barView?.textView.string ?? "",
            spaces: spaces.spaces,
            selectedSpace: selectedSpace,
            manualReminder: manualReminder,
            now: now(),
            calendar: calendar
        )
    }

    private func refresh(animated: Bool) {
        guard let barView else { return }
        let entry = interpretation()
        // 읽은 때는 지났어도 보여 준다(무엇으로 읽혔는지 알 수 있게). 지난 때는 흐린 글자에 가운데 줄이고, 걸리지 않는다.
        let reminder = entry.resolvedReminder.map { date in
            let text = CaptureReminderText.text(for: date, now: now(), calendar: calendar)
            return CaptureBadgeView.Content(
                symbolName: "clock", symbolSize: .iconSmall, text: text,
                accessibilityLabel: entry.isReminderPast
                    ? "지난 시각 \(text), 리마인더로 걸리지 않습니다" : "리마인더 \(text)",
                isStruckOut: entry.isReminderPast
            )
        }
        // 들어갈 스페이스는 글을 적기 시작하면(또는 ⇥로 바꾸면) 보인다. 빈 바에는 자리 글자만 있다.
        let showsSpace = !barView.textView.string.isEmpty || hasCycledSpace
        barView.apply(
            space: showsSpace ? entry.spaceID.flatMap(spaces.space(for:)).map(Self.badge(for:)) : nil,
            reminder: reminder,
            timeRanges: entry.timeRanges,
            animated: animated
        )
    }

    /// 스페이스는 아이콘과 이름으로 보인다(spec 7). 이미지 아이콘은 Library 단계에서 만든다. 그때까지는 이름만.
    private static func badge(for space: Space) -> CaptureBadgeView.Content {
        var content = CaptureBadgeView.Content(
            symbolName: nil, symbolSize: .iconMedium, text: space.name, accessibilityLabel: "스페이스 \(space.name)"
        )
        switch space.icon {
        case .symbol(let name, _): content.symbolName = name
        case .emoji(let emoji): content.text = space.name.isEmpty ? emoji : "\(emoji) \(space.name)"
        case .customSymbol(let name, _): content.symbolName = name
        case .none, .image: break
        }
        return content
    }

    // MARK: - 동작

    @_spi(Verification) public func performSubmit() { perform(.submit) }
    @_spi(Verification) public func performSubmitAsNewNote() { perform(.submitAsNewNote) }
    @_spi(Verification) public func performCycleReminder() { perform(.cycleReminder) }

    private func perform(_ command: CaptureCommand) {
        // 닫히는 중의 키 입력은 버린다: ↵를 잇달아 두 번 눌러도 한 번만 들어간다.
        guard !isClosing else { return }
        switch command {
        case .submit: submit()
        case .submitAsNewNote: submitAsNewNote()
        case .nextSpace: cycleSpace(backward: false)
        case .previousSpace: cycleSpace(backward: true)
        case .cycleReminder:
            manualReminder = CaptureReminderPresets.next(after: manualReminder, now: now(), calendar: calendar)
            refresh(animated: true)
        case .cancel: dismiss(returningFocus: true)
        }
    }

    private func cycleSpace(backward: Bool) {
        selectedSpace = CaptureSpaceCycle.next(after: selectedSpace, in: spaces.spaces, backward: backward)
        hasSelectedSpace = true
        hasCycledSpace = true
        refresh(animated: true)
    }

    /// ↵: 오늘 노트에 투두로 넣고 닫는다. 넣지 못했으면 글을 그대로 둔 채 열어 둔다.
    private func submit() {
        let entry = interpretation()
        guard !entry.isEmpty else { return }
        do {
            let outcome = try CaptureWriter(notes: notes, calendar: calendar).add(entry, now: now())
            switch outcome {
            case .appended(let id): log("캡처: 노트 \(id)에 투두를 붙였습니다")
            case .created(let id): log("캡처: 오늘 노트 \(id)를 만들어 투두를 넣었습니다")
            case .redirected(let id, let blocked, let reason):
                log("캡처: 오늘 노트 \(blocked)에 풀리지 않은 문제가 있어(\(reason)) 노트 \(id)에 투두를 넣었습니다")
            }
            if entry.isReminderPast {
                log("캡처: 읽은 때가 이미 지나 리마인더는 걸지 않았습니다")
            }
            rememberSpace(entry.spaceID)
            hide()
            onCaptured?(outcome.noteID)
        } catch {
            log("캡처: 넣지 못했습니다: \(error)")
            reportFailure(error)
        }
    }

    /// 넣지 못한 것을 App에 알린다. 알림 창이 떠 있는 동안 바는 그대로 있고, 닫히면 다시 입력을 받는다.
    private func reportFailure(_ error: Error) {
        guard let onFailure else { return }
        staysOpenWithoutKey = true
        onFailure(error)
        staysOpenWithoutKey = false
        reclaimKey()
    }

    /// 알림 창이 가져갔던 키 입력을 바로 되찾는다. 적은 글은 그대로다.
    private func reclaimKey() {
        guard let panel, let barView, panel.isVisible, !isClosing, takesKeyOnShow else { return }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(barView.textView)
    }

    /// ⌘↵: 적은 글을 제목으로 한 새 노트를 띄운다(임시, D-026). 만들고 띄우는 일은 App이 한다.
    /// 요청을 먼저 보내고, 만들어졌을 때만 닫는다. 만들지 못했으면(알리는 일은 받은 쪽이 했다) 적은 글을
    /// 그대로 둔 채 다시 입력을 받는다.
    private func submitAsNewNote() {
        let entry = interpretation()
        guard !entry.isEmpty else { return }
        staysOpenWithoutKey = true
        let result = router.route(.newNote(NewNoteRequest(
            draft: NoteDraft(title: entry.text, spaceID: entry.spaceID, reminder: entry.reminder)
        )))
        staysOpenWithoutKey = false
        switch result {
        case .handled:
            rememberSpace(entry.spaceID)
            // 새 노트가 키 창이 되었다. 열기 전의 자리로 포커스를 돌려주지 않는다.
            dismiss(returningFocus: false)
        case .failed:
            log("캡처: 새 노트를 만들지 못해 적은 글을 그대로 둡니다")
            reclaimKey()
        case .unconnected:
            log("캡처: 새 노트를 만드는 곳이 이어져 있지 않아 적은 글을 그대로 둡니다")
            reclaimKey()
        }
    }

    private func rememberSpace(_ id: SpaceID?) {
        selectedSpace = id
        hasSelectedSpace = true
    }
}
