import AppKit
import Models
import Routing
import Store
import Theme

/// 노트 찾기(spec 8, 화면 9): 다른 노트로 빠르게 가는 작은 목록. App이 하나 만들어 `.openBrowse`에 잇는다.
///
/// - 줄을 고르면 `Route.openNote`를 보내고 닫는다. 떠 있는 노트로 포커스를 옮기거나 새 창으로 띄우는 일은 App이 한다.
/// - "“검색어” 새 노트 만들기"는 `Route.newNote`, "라이브러리 열기"는 `Route.openLibrary`를 보낸다.
///   "라이브러리 열기"는 그 요청이 이어져 있을 때만 보인다(`Routing.isConnected`).
/// - esc, ⌘W, 바깥 클릭으로 닫힌다. esc로 닫으면 포커스를 열기 전의 자리로 돌려줄 때라고 알린다(`onDismiss`).
@MainActor
public final class BrowseCoordinator {
    private let theme: Theme
    private let notes: any NoteStoring
    private let spaces: SpaceStore
    private let router: any Routing
    private let windowStates: WindowStateStore?
    public var onSetPinned: ((NoteID, Bool) -> Void)?
    private let log: @MainActor (String) -> Void
    private let style: BrowseStyle

    private var panel: BrowsePanel?
    private var rootView: BrowseRootView?
    private var observers: [NSObjectProtocol] = []
    private var storeObservation: StoreObservation?
    /// 창 상태(떠 있는 노트, 핀, 연 때)와 스페이스 목록의 변경 알림. 열려 있는 동안만 건다.
    private var stateObservations: [StoreObservation] = []
    /// 다음 차례에 목록을 다시 읽기로 해 두었다. 그사이의 변경은 한 번에 읽는다.
    private var isReloadScheduled = false
    /// 사라지는 중(알파가 0으로 가는 중)이다. 이때는 보이지 않는 것으로 치고 명령도 받지 않는다.
    private var isClosing = false
    /// 사라지는 전환이 끝날 때 창을 내리는 일. 움직임이 끝났는지에 기대지 않고 `dur` 뒤에 한다. 다시 띄우면 취소한다.
    private var closingSettle: Task<Void, Never>?
    /// 높이가 바뀌는 전환이 끝날 때 마지막으로 정한 틀에 놓고 그림자를 다시 만드는 일. 다음 변경이 오면 취소한다.
    private var frameSettle: Task<Void, Never>?
    /// 목록을 읽지 못한 것을 알리는 중이거나 고른 줄의 요청이 돌아오기를 기다리는 중이다. 이때는 키 창에서
    /// 물러나도(알림 창, 고른 노트의 창) 닫지 않는다. 닫을지와 포커스는 그 일이 끝난 뒤에 정한다.
    private var staysOpenWithoutKey = false

    private var indexedNotes: [BrowseIndexedNote] = []
    private var floating: [NoteID] = []
    private var lastOpened: [NoteID: Date] = [:]
    private var current: NoteID?
    private weak var anchorWindow: NSWindow?
    /// 목록의 위쪽 가장자리와 왼쪽 자리. 높이가 바뀌어도 여기는 그대로다.
    private var topLeft: CGPoint = .zero
    private var maxHeight: CGFloat = 0
    /// 마지막으로 정한 창 틀(움직이는 중이면 가려는 곳).
    private var targetFrame: CGRect = .null

    /// 닫히기 시작할 때 불린다. 인자가 참이면 열기 전에 키 입력을 받던 곳으로 포커스를 돌려줄 때다
    /// (esc, ⌘W, `hide()`, 고른 줄의 요청이 이루어지지 못함). 거짓이면 포커스가 갈 곳이 따로 있다
    /// (바깥을 누름, 고른 줄의 요청이 이루어짐).
    /// 키 창을 누구에게 돌려줄지는 App이 정한다. 이 모듈은 노트 창을 직접 키 창으로 만들지 않는다.
    public var onDismiss: (@MainActor (_ returnsFocus: Bool) -> Void)?
    /// 띄울 때 노트 목록을 읽지 못했으면 불린다(`log`에도 남는다). App이 사용자에게 알린다. 알리는 동안
    /// 키 창에서 물러나도(알림 창) 닫히지 않고, 돌아오면 다시 입력을 받는다.
    /// 열려 있는 동안 다시 읽다가 난 실패는 기록만 하고 보이던 목록을 그대로 둔다.
    public var onFailure: (@MainActor (Error) -> Void)?

    /// 확인용: 거짓이면 띄울 때 키 창으로 만들지 않는다(다른 앱의 입력을 빼앗지 않는다).
    @_spi(Verification) public var takesKeyOnShow = true
    /// 확인용: 거짓이면 창을 화면에 올리되 완전히 투명하게 두고 마우스도 받지 않는다(테스트가 쓰는 사람의 화면을 가리지 않게).
    @_spi(Verification) public var isShownOpaque = true
    /// 확인용: 띄울 화면을 정한다. 없으면 마우스가 있는 화면.
    @_spi(Verification) public var preferredScreen: NSScreen?
    /// 확인용: 알림을 걸 곳. 처음 띄우기 전에만 바꾼다.
    @_spi(Verification) public var notificationCenter: NotificationCenter = .default
    /// 확인용: 노트 목록을 저장소에서 읽은 횟수.
    @_spi(Verification) public private(set) var listReadCount = 0

    /// - Parameter windowStates: 떠 있는 노트를 알아내는 창 상태. 주지 않으면 "떠 있는 노트" 구획과 핀이 보이지 않는다.
    public init(
        theme: Theme,
        notes: any NoteStoring,
        spaces: SpaceStore,
        router: any Routing,
        windowStates: WindowStateStore? = nil,
        log: @escaping @MainActor (String) -> Void
    ) {
        self.theme = theme
        self.notes = notes
        self.spaces = spaces
        self.router = router
        self.windowStates = windowStates
        self.log = log
        style = BrowseStyle(theme: theme)
    }

    isolated deinit {
        observers.forEach(notificationCenter.removeObserver)
    }

    public var isVisible: Bool { panel?.isVisible == true && !isClosing }

    /// 노트 창의 상단 줄 아래에 띄운다. 창을 주지 않으면 마우스가 있는 화면의 가운데 위쪽에 띄운다.
    /// - Parameter current: 노트 찾기를 연 노트. 목록에서 빠지고, 새 노트는 그 옆에 뜬다.
    public func show(anchoredTo window: NSWindow?, excluding current: NoteID?) {
        let panel = preparedPanel()
        guard let rootView else { return }
        closingSettle?.cancel()
        closingSettle = nil
        isClosing = false
        rootView.searchField.textView.isEditable = true
        self.current = current
        anchorWindow = window
        let failure = reloadNotes()
        storeObservation = notes.observe { [weak self] _ in self?.contentDidChange() }
        // 떠 있는 노트, 핀, 스페이스 이름이 바뀌어도 열려 있는 목록이 따라간다.
        stateObservations = [
            windowStates?.observe { [weak self] in self?.contentDidChange() },
            spaces.observe { [weak self] in self?.contentDidChange() },
        ].compactMap { $0 }

        let textView = rootView.searchField.textView
        rootView.searchField.input.stringValue = ""
        textView.string = ""
        textView.undoManager?.removeAllActions()
        place(on: window?.screen ?? preferredScreen ?? Self.screenWithMouse(), anchor: window)
        targetFrame = .null
        rebuild(animated: false)

        if !panel.isVisible { panel.alphaValue = 0 }
        if takesKeyOnShow {
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
        panel.makeFirstResponder(rootView.searchField.input)
        panel.ignoresMouseEvents = !isShownOpaque
        if isShownOpaque { style.animate { panel.animator().alphaValue = 1 } }
        if let failure { reportFailure(failure) }
    }

    /// 목록을 읽지 못한 것을 App에 알린다. 알림 창이 떠 있는 동안 목록은 그대로 있고("새 노트 만들기" 같은
    /// 남은 줄이 보인다), 닫히면 다시 입력을 받는다.
    private func reportFailure(_ error: Error) {
        guard let onFailure else { return }
        staysOpenWithoutKey = true
        onFailure(error)
        staysOpenWithoutKey = false
        guard let panel, let rootView, panel.isVisible, !isClosing, takesKeyOnShow else { return }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(rootView.searchField.input)
    }

    /// `dur` 동안 흐려진 뒤 내려간다. 포커스를 열기 전의 자리로 돌려줄 때라고 `onDismiss`로 알린다(spec 17).
    public func hide() {
        close(returningFocus: true)
    }

    // MARK: - 확인용 창구

    @_spi(Verification) public var window: NSWindow? { panel }
    @_spi(Verification) public var inputView: NSTextView? { rootView?.searchField.textView }
    @_spi(Verification) public var showsPlaceholder: Bool { rootView?.searchField.isPlaceholderVisible ?? false }
    /// 목록 안에 실제로 놓인 뷰의 수와, 목록에 걸려 있는 전환(겹쳐 넘기기)의 수. 옛 줄이 남아 겹쳐 보이지 않는지 볼 때 쓴다.
    @_spi(Verification) public var drawnRowCount: Int { rootView?.listView.entryViews.count ?? 0 }
    @_spi(Verification) public var listTransitionCount: Int { rootView?.listView.layer?.animationKeys()?.count ?? 0 }
    /// 창이 가려는 틀(움직이는 중이어도 끝의 값).
    @_spi(Verification) public var settledFrame: CGRect { targetFrame }
    /// 목록의 줄을 위에서부터 글로 적은 것. 고른 줄 앞에는 `*`가 붙는다.
    @_spi(Verification) public var rowDescriptions: [String] {
        guard let listView = rootView?.listView else { return [] }
        return listView.entries.enumerated().map { index, entry in
            (index == listView.selectedIndex ? "*" : " ") + Self.describe(entry, view: listView.entryViews[index])
        }
    }

    private static func describe(_ entry: BrowseEntry, view: BrowseEntryView) -> String {
        switch entry {
        case .header(let title): return "header \(title)"
        case .separator: return "separator"
        case .library: return "library \((view as? BrowseActionRowView)?.title ?? "")"
        case .create: return "create \((view as? BrowseActionRowView)?.title ?? "")"
        case .note(let row):
            let rowView = view as? BrowseNoteRowView
            let parts = [
                "note \(row.id)", rowView?.titleText ?? "", rowView?.previewText.string ?? "",
                "-", row.isFloating ? "pin" : "-",
            ]
            return parts.joined(separator: " | ")
        }
    }

    // MARK: - 창

    private func preparedPanel() -> BrowsePanel {
        if let panel { return panel }
        let width = theme.component(.browseWidth)
        let panel = BrowsePanel(contentRect: NSRect(x: 0, y: 0, width: width, height: width))
        let rootView = BrowseRootView(style: style)
        rootView.frame = NSRect(x: 0, y: 0, width: width, height: width)
        rootView.autoresizingMask = [.width, .height]
        panel.contentView = rootView

        let textView = rootView.searchField.textView
        textView.onCommand = { [weak self] in self?.perform($0) }
        textView.onTextChange = { [weak self] in self?.rebuild(animated: true) }
        rootView.listView.onHover = { [weak self] in self?.rootView?.listView.select($0, animated: true) }
        rootView.listView.onActivate = { [weak self] in self?.activate($0) }

        let center = notificationCenter
        observers = [
            // 바깥을 누르면 키 창에서 물러난다. 그때 닫는다(포커스는 누른 곳에 둔다).
            center.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.resignedKey() }
            },
            center.addObserver(forName: Theme.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.themeDidChange() }
            },
        ]
        self.panel = panel
        self.rootView = rootView
        return panel
    }

    /// 바깥을 눌렀다. 포커스는 누른 곳에 둔다. 실패를 알리는 중이거나(알림 창이 키 창이 됨) 고른 줄의 답을
    /// 기다리는 중이면 닫지 않는다.
    private func resignedKey() {
        guard !staysOpenWithoutKey else { return }
        close(returningFocus: false)
    }

    private func close(returningFocus: Bool) {
        guard let panel, panel.isVisible, !isClosing else { return }
        isClosing = true
        pickTarget = nil
        storeObservation = nil
        stateObservations = []
        anchorWindow = nil
        // 사라지는 동안에는 글도 명령도 받지 않는다(보이지 않게 된 목록이 키 입력을 먹지 않게).
        rootView?.searchField.textView.isEditable = false
        style.animate { panel.animator().alphaValue = 0 }
        // 창을 내리는 일은 움직임이 끝났다는 알림이 아니라 `dur` 뒤의 시계가 한다("동작 줄이기"면 바로).
        closingSettle = style.afterTransition { [weak self] in self?.finishClosing() }
        onDismiss?(returningFocus)
    }

    private func finishClosing() {
        closingSettle = nil
        guard let panel, isClosing else { return }
        isClosing = false
        panel.orderOut(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            panel.animator().alphaValue = 0
        }
        panel.alphaValue = 0
    }

    private func themeDidChange() {
        guard let rootView else { return }
        rootView.refreshTheme()
        if isVisible { rebuild(animated: false) }
    }

    private static func screenWithMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
    }

    /// 위쪽 가장자리와 높이 한도를 정한다.
    private func place(on screen: NSScreen?, anchor: NSWindow?) {
        guard let visibleFrame = (screen ?? NSScreen.main)?.visibleFrame else { return }
        let anchorMetrics = anchor.map {
            BrowsePlacement.Anchor(
                frame: $0.frame,
                chromeHeight: theme.shape(.chromeHeight),
                gap: theme.component(.browseAnchorGap),
                inset: theme.component(.browseAnchorInset)
            )
        }
        topLeft = BrowsePlacement.topLeft(
            width: theme.component(.browseWidth), anchor: anchorMetrics,
            visibleFrame: visibleFrame, topRatio: theme.ratio(.browseTopScreen),
            heightRatio: theme.ratio(.browseMaxScreenHeight)
        )
        maxHeight = BrowsePlacement.maxHeight(
            top: topLeft.y, visibleFrame: visibleFrame, heightRatio: theme.ratio(.browseMaxScreenHeight)
        )
    }

    // MARK: - 내용

    /// 노트 목록과 떠 있는 노트를 다시 읽는다.
    ///
    /// 목록을 읽지 못하면 까닭을 `log`로 알리고, 앞서 읽은 목록이 있으면 그대로 둔다(열려 있던 목록이 비지 않게).
    /// 처음부터 읽지 못했으면 노트 줄 없이 "새 노트 만들기"(글자를 치면)와 "라이브러리 열기"만 보인다.
    /// - Returns: 목록을 읽지 못했으면 그 까닭.
    @discardableResult
    private func reloadNotes() -> Error? {
        listReadCount += 1
        var failure: Error?
        do {
            let listing = try notes.list()
            listing.failures.forEach { log("노트 찾기: 읽지 못한 노트 \($0.id): \($0.error)") }
            indexedNotes = listing.notes.map(BrowseIndexedNote.init)
        } catch {
            log("노트 찾기: 노트 목록을 읽지 못했습니다: \(error)")
            failure = error
        }
        let states = windowStates?.all ?? [:]
        floating = BrowseFloating.ids(from: states)
        lastOpened = BrowseRecency.openedTimes(from: states)
        return failure
    }

    /// 열려 있는 동안 노트나 창 상태, 스페이스 목록이 바뀌면 목록을 다시 만든다. 변경이 잇달아 와도
    /// (여러 노트를 한꺼번에 저장, 폴더 다시 훑기, 창 상태를 잇달아 적음) 다음 차례에 한 번만 다시 읽는다.
    private func contentDidChange() {
        guard isVisible, !isReloadScheduled else { return }
        isReloadScheduled = true
        DispatchQueue.main.async { [weak self] in self?.reloadAfterChanges() }
    }

    /// 고른 줄은 같은 것으로 둔다(노트 줄은 같은 노트).
    private func reloadAfterChanges() {
        isReloadScheduled = false
        guard isVisible, let listView = rootView?.listView else { return }
        let selected = listView.selectedIndex.map { listView.entries[$0] }
        reloadNotes()
        rebuild(animated: true, keeping: selected)
    }

    private func rebuild(animated: Bool, keeping selected: BrowseEntry? = nil) {
        guard let panel, let rootView else { return }
        let textView = rootView.searchField.textView
        let query = BrowseQuery(textView.string, isComposing: textView.hasMarkedText())
        let content = BrowseContent(
            notes: indexedNotes, floating: floating, lastOpened: lastOpened, query: query, excluding: current,
            // 눌러도 아무 일이 없는 줄은 내놓지 않는다.
            showsLibrary: router.isConnected(.openLibrary)
        )
        let views = content.entries.map(makeView(for:))
        let selection = BrowseSelection.index(keeping: selected, in: content.entries)
        rootView.listView.setEntries(content.entries, views: views, selected: selection)

        let frame = BrowsePlacement.frame(
            topLeft: topLeft, width: theme.component(.browseWidth),
            height: rootView.fittingHeight(limit: maxHeight)
        )
        // 움직이는 중의 `panel.frame`은 가는 길의 값이다. 마지막으로 정한 틀과 견준다.
        guard frame != targetFrame else { return }
        targetFrame = frame
        frameSettle?.cancel()
        frameSettle = nil
        if animated, panel.isVisible {
            // 높이는 위쪽을 고정한 채 `dur` 동안 내용을 따라간다. 움직임은 꾸밈이고, 끝의 틀에 놓는 일은
            // `dur` 뒤에 따로 한다(화면이 꺼져 있으면 움직임이 나아가지 않는다).
            style.animate { panel.animator().setFrame(frame, display: true) }
            frameSettle = style.afterTransition { [weak self] in self?.landOnTargetFrame() }
        } else {
            landOnTargetFrame()
        }
    }

    /// 가던 움직임이 있으면 멈추고 마지막으로 정한 틀에 놓는다.
    /// 투명한 테두리 없는 창의 그림자는 모양이 바뀐 뒤에 다시 만들어야 옛 모양이 남지 않는다.
    private func landOnTargetFrame() {
        frameSettle = nil
        guard let panel, !targetFrame.isNull else { return }
        let frame = targetFrame
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            panel.animator().setFrame(frame, display: true)
        }
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
    }

    private func makeView(for entry: BrowseEntry) -> BrowseEntryView {
        switch entry {
        case .header(let title):
            return BrowseHeaderView(style: style, title: title)
        case .separator:
            return BrowseSeparatorView(style: style)
        case .library:
            return BrowseActionRowView(style: style, symbolName: "sidebar.left", title: "라이브러리 열기", textColor: .text)
        case .create(let query):
            return BrowseActionRowView(
                style: style, symbolName: "plus", title: "“\(query)” 새 노트 만들기", textColor: .text2
            )
        case .note(let row):
            let space = row.spaceID.flatMap(spaces.space(for:))
            let view = BrowseNoteRowView(style: style, row: row, space: space, directory: spaces.imageDirectory)
            view.onOpen = { [weak self, weak view] in
                guard let view, let index = self?.rootView?.listView.entryViews.firstIndex(of: view) else { return }
                self?.activate(index)
            }
            view.onPin = { [weak self] in self?.onSetPinned?(row.id, !row.isFloating) }
            return view
        }
    }

    // MARK: - 동작

    private func perform(_ command: BrowseCommand) {
        // 닫히는 중의 키 입력은 버린다: esc 바로 뒤의 ↵가 줄을 열지 않는다.
        guard !isClosing, let listView = rootView?.listView else { return }
        switch command {
        case .moveUp, .moveDown:
            let step = command == .moveUp ? -1 : 1
            listView.select(
                BrowseSelection.moved(from: listView.selectedIndex, by: step, in: listView.entries), animated: true
            )
        case .open:
            if let index = listView.selectedIndex { activate(index) }
        case .cancel:
            close(returningFocus: true)
        }
    }

    /// 줄을 연다: 요청을 보내고 닫는다. 요청이 이루어졌으면 포커스는 받은 쪽이 정했고(고른 노트가 키 창이 된다),
    /// 이루어지지 못했으면(받은 쪽이 사용자에게 알렸다) 열기 전의 자리로 포커스를 돌려줄 때라고 알린다.
    package var pickTarget: ((NoteID) -> Void)?

    private func activate(_ index: Int) {
        guard !isClosing, let listView = rootView?.listView, listView.entries.indices.contains(index),
              let route = BrowseSelection.route(for: listView.entries[index], current: current)
        else { return }
        if let pickTarget {
            if case .openNote(let id) = route {
                close(returningFocus: false)
                pickTarget(id)
            }
            return
        }
        staysOpenWithoutKey = true
        let result = router.route(route)
        staysOpenWithoutKey = false
        if result == .unconnected { log("노트 찾기: 아직 이어지지 않은 요청입니다: \(route)") }
        close(returningFocus: result != .handled)
    }
}
