import AppKit
import Models
import Routing
import Store
import Theme

/// 떠 있는 노트 창 전부를 맡는 곳. App이 하나 만들어 들고, `Route`를 받아 이 타입의 메서드를 부른다.
///
/// - 노트 하나에 창 하나. 이미 떠 있는 노트를 열면 그 창을 앞으로 가져온다.
/// - 창의 틀, 핀, 열림 상태는 `WindowStateStore`에 남기고 `restoreOpenNotes()`로 되살린다.
/// - 노트 내용은 `NoteStoring`의 `load`, `update`, `scheduleUpdate`만 거쳐 읽고 쓴다.
/// - "노트 모두 숨기기" 중에 노트를 열거나, 새로 만들거나, 본문에 커서를 두거나, 더 보기 메뉴를 띄우면
///   숨김이 모두 풀린다. 한 창만 보이고 나머지는 숨은 상태는 없다(`areNotesHidden`이 참이면 보이는 노트 창이 없다).
public final class NotePanelCoordinator {
    private struct TrashedNote {
        let id: NoteID
        /// 휴지통으로 보내기 직전의 창 상태(틀, 핀, 열림, 접힘). 적힌 것이 없었으면 `nil`.
        let windowState: NoteWindowState?
    }

    /// 상단 줄 표시 방식. 바꾸면 떠 있는 창에 바로 반영된다.
    public var displayOptions = NotePanelDisplayOptions() {
        didSet { controllers.values.forEach { $0.refreshChrome(animated: false) } }
    }

    /// 확인용: 끄면 노트 창이 키 창이 되지 않는다. 노트 창은 앱을 앞으로 가져오지 않고도 키 창이 되므로,
    /// 자동 확인 중에 띄운 창이 사용자가 다른 앱에 치던 글자를 받지 않게 할 때 쓴다. 기본은 켜짐.
    @_spi(Verification)
    public var allowsKeyWindows = true {
        didSet {
            controllers.values.forEach { $0.panel.allowsKey = allowsKeyWindows }
            if !allowsKeyWindows { releaseKeyWindow() }
        }
    }

    /// 확인용: 키 창인 노트 창을 키 창에서 물러나게 한다. 내렸다 다시 올리는데, 노트 창은 누르거나
    /// 일부러 시킬 때만 키 창이 되므로 다시 올려도 키 창이 되지 않는다. 겹친 차례는 지킨다.
    @_spi(Verification)
    public func releaseKeyWindow() {
        guard !areNotesHidden, keyNoteID != nil else { return }
        let stacked = recorder.backToFront(order).compactMap { controllers[$0] }
        stacked.forEach { $0.setHidden(true) }
        stacked.forEach { $0.setHidden(false) }
    }

    /// 확인용: 지금 시각을 바꿔 끼운다(마지막으로 연 때를 적는 데 쓴다).
    @_spi(Verification) public var now: () -> Date = { Date() }

    /// "노트 모두 숨기기"가 켜져 있는지(spec 4.3).
    public private(set) var areNotesHidden = false

    private let notes: any NoteStoring
    private let recorder: WindowStateRecorder
    private let log: (String) -> Void
    private var environment: NotePanelEnvironment!
    private(set) var controllers: [NoteID: NoteWindowController] = [:]
    /// 띄운 순서.
    private var order: [NoteID] = []
    private var spaceObservation: StoreObservation?
    private var storeObservation: StoreObservation?
    private var observers: [any NSObjectProtocol] = []
    private var isRefreshingStore = false
    /// 켤 때 지난번의 창을 되살리는 중이다. 사용자가 연 것이 아니므로 "마지막으로 연 때"를 적지 않는다.
    private var isRestoring = false
    /// 방금 휴지통으로 보낸 노트. "바로 뒤"가 끝나면 비운다(`endTrashUndo()`를 부르는 곳들, D-024).
    private var lastTrashed: TrashedNote? {
        didSet { if lastTrashed == nil, oldValue != nil, !isHoldingTrashUndo { onTrashUndoEnded?() } }
    }
    /// 키 창을 돌려주는 동안(`returnKey`) 되돌리기를 잠깐 비웠다 되돌린다. 그사이에는 끝났다고 알리지 않는다.
    private var isHoldingTrashUndo = false

    /// 노트를 휴지통으로 보냈다(되돌릴 수 있게 된 뒤에 불린다). 그 노트의 창이 있던 화면을 함께 넘긴다.
    /// App이 "되돌리기"가 붙은 짧은 알림을 띄운다(D-041).
    public var onMovedToTrash: ((NoteID, NSScreen?) -> Void)?
    /// 휴지통 되돌리기가 끝났다(되살렸거나, "바로 뒤"가 지났다). 알림을 거둔다.
    public var onTrashUndoEnded: (() -> Void)?
    /// 지금 휴지통으로 보내는 중인 노트. 그 창이 내려갈 때 키 입력을 어디에 둘지 정하는 데 쓴다.
    private var trashInProgress: NoteID?
    /// 그 창이 키 창인지. 시험은 실제 키 창을 만들지 않으므로(사용자의 키 입력을 가져온다) 바꿔 넣는다.
    var isKeyPanel: (NSWindow) -> Bool = { $0.isKeyWindow }
    /// 앱을 앞으로 가져온다. 시험에서 바꿔 넣는다.
    var activateApp: () -> Void = { NSApplication.shared.activate() }
    /// 앱이 앞에 있는지. 시험에서 바꿔 넣는다.
    var isAppActive: () -> Bool = { NSApplication.shared.isActive }

    /// - Parameters:
    ///   - router: 노트 창이 다른 기능을 부를 때(노트 찾기, 새 노트, AI 패널 등) 보내는 곳.
    ///   - makeBodyEditor: 본문 편집기를 만드는 곳. 주지 않으면 서식 없는 기본 편집기를 쓴다.
    ///   - log: 사용자에게 창으로 알릴 일이 아닌 문제를 남기는 곳.
    public init(
        theme: Theme,
        notes: any NoteStoring,
        windowStates: WindowStateStore,
        spaces: SpaceStore,
        router: any Routing,
        makeBodyEditor: @escaping NoteBodyEditorFactory = { PlainTextBodyEditor(theme: $0.theme) },
        log: @escaping (String) -> Void
    ) {
        self.notes = notes
        self.log = log
        recorder = WindowStateRecorder(store: windowStates, log: log)
        environment = NotePanelEnvironment(
            style: PanelStyle(theme: theme), notes: notes, spaces: spaces, router: router,
            recorder: recorder, makeBodyEditor: makeBodyEditor,
            options: { [unowned self] in displayOptions }, now: { [unowned self] in now() }, log: log
        )
        spaceObservation = spaces.observe { [weak self] in
            self?.controllers.values.forEach { $0.refreshChrome(animated: true) }
        }
        storeObservation = notes.observe { [weak self] in self?.storeDidChange($0) }
        observeAppearance(of: theme)
    }

    isolated deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
    }

    // MARK: - 열고 닫기

    /// 지난번에 떠 있던 노트를 제자리에 다시 띄운다. 띄운 노트를 돌려준다.
    /// 그사이 없어진 노트는 상태에서 지우고 넘어간다.
    @discardableResult
    public func restoreOpenNotes() -> [NoteID] {
        isRestoring = true
        defer { isRestoring = false }
        return recorder.openNoteIDs.filter { id in
            do {
                try open(id, focus: false)
                return true
            } catch StoreError.noteNotFound {
                log("떠 있던 노트의 파일이 없어 창을 되살리지 않습니다: \(id)")
                recorder.forget(id)
                return false
            } catch {
                log("노트 창을 되살리지 못했습니다(\(id)): \(error)")
                return false
            }
        }
    }

    /// 노트 창을 띄운다. 이미 떠 있으면 앞으로 가져온다.
    /// - Parameters:
    ///   - nextTo: 처음 띄우는 노트를 이 노트 옆에 둔다. 없으면 지금 쓰는 노트 옆, 그것도 없으면 화면 오른쪽 위.
    ///   - focus: 본문에 입력 커서를 둔다.
    public func open(_ id: NoteID, nextTo: NoteID? = nil, focus: Bool = true) throws {
        setAllHidden(false)
        if let controller = controllers[id] {
            controller.show(focus: focus, recordsOpening: !isRestoring)
            return
        }
        // 편집용으로 열 때는 목록의 값이 아니라 load의 값을 쓴다(충돌 기준이 여기서 잡힌다).
        let note = try notes.load(id)
        let state = recorder.state(for: id)
        let controller = NoteWindowController(
            note: note, frame: frame(for: state, nextTo: nextTo), isPinned: state.isPinned,
            environment: environment
        )
        controller.coordinator = self
        controller.panel.allowsKey = allowsKeyWindows
        controllers[id] = controller
        order.append(id)
        controller.show(focus: focus, recordsOpening: !isRestoring)
    }

    /// 새 노트를 만들어 지금 노트 옆에 띄운다. 핀이 켜진 채로 뜬다(spec 4.1).
    @discardableResult
    public func createNote(_ request: NewNoteRequest = NewNoteRequest()) throws -> NoteID {
        endTrashUndo()
        let note = try notes.create(request.draft)
        try open(note.id, nextTo: request.nextTo, focus: true)
        return note.id
    }

    /// 창만 내린다. 노트는 남는다. 미뤄 둔 변경을 쓰지 못하면 창을 남기고 상단 줄에 표시한다.
    /// 아무것도 적지 않은 노트(`Note.isBlank`)는 창과 함께 지운다(휴지통을 거치지 않는다, D-040).
    public func closeWindow(_ id: NoteID) {
        guard let controller = controllers[id], controller.flushBeforeClosing() else { return }
        let isBlank = controller.isBlankAndSettled
        recorder.recordClosed(id)
        discard(id)
        if isBlank { deleteBlankNote(id) }
    }

    /// 떠 있는 노트 가운데 아무것도 적지 않은 것을 지운다(D-040). 앱을 끝낼 때, 미뤄 둔 저장을 다 쓴 뒤에 부른다.
    /// 창은 그대로 둔다(앱이 곧 끝난다). 지운 노트를 돌려준다.
    @discardableResult
    public func deleteBlankNotes() -> [NoteID] {
        order.filter { controllers[$0]?.isBlankAndSettled == true }.filter(deleteBlankNote)
    }

    /// 빈 노트의 파일을 지운다. 창 상태는 저장소의 `.removed` 알림을 받아 잊는다.
    @discardableResult
    private func deleteBlankNote(_ id: NoteID) -> Bool {
        do {
            // 지우기 직전에 저장소의 지금 값으로 한 번 더 본다. 그사이 무엇이 적혔으면 지우지 않는다.
            guard try notes.load(id).isBlank, !notes.hasPendingChanges(id) else { return false }
            try notes.delete(id)
            recorder.forget(id)
            return true
        } catch {
            log("빈 노트를 지우지 못했습니다(\(id)): \(error)")
            return false
        }
    }

    /// 노트를 휴지통으로 보내고 창을 내린다. 확인 창을 띄우지 않는다(spec 5.3).
    /// 바로 뒤라면 `undoTrash()`로 되돌린다.
    public func moveToTrash(_ id: NoteID) {
        // 편집기가 아직 알리지 않은 글까지 받아 둔다. 저장소가 옮기기 전에 그것을 쓴다.
        controllers[id]?.flushPendingEdits()
        let screen = controllers[id]?.panel.screen
        let trashed = TrashedNote(id: id, windowState: recorder.savedState(for: id))
        trashInProgress = id
        defer { trashInProgress = nil }
        do {
            try notes.moveToTrash(id)
        } catch {
            if let controller = controllers[id] {
                controller.handleStoreFailure(error)
            } else {
                log("노트를 휴지통으로 보내지 못했습니다(\(id)): \(error)")
            }
            return
        }
        noteDisappeared(id)
        // 창이 내려가며 다음 노트가 키 창을 이어받았다면 그것은 사용자가 다른 노트로 옮겨 간 것이 아니다.
        // 이어받기가 끝난 여기서 적어, 그 키 창 알림이 되돌리기를 끝내지 않게 한다.
        lastTrashed = trashed
        onMovedToTrash?(id, screen)
    }

    /// 방금 휴지통으로 보낸 노트를 되돌릴 수 있는지(spec 5.3의 "바로 뒤라면 ⌘Z").
    ///
    /// "바로 뒤"는 다음 가운데 하나가 일어나기 전까지다(D-024). 그동안의 ⌘Z는 노트를 되살리고, 끝난 뒤의 ⌘Z는
    /// 글의 실행 취소로 간다(다른 노트에는 제 실행 취소 기록이 있다).
    /// - 다른 노트가 키 창이 되거나 사용자가 노트 창을 누른다(보낸 직후 다음 노트가 키 창을 이어받는 것은 빼고).
    /// - 글을 고친다(본문, 제목, 색) 또는 새 노트를 만든다.
    /// - 되살렸다. 또는 되살릴 수 없다는 것이 드러났다(`undoTrash()`).
    public var canUndoTrash: Bool { lastTrashed != nil }

    /// 방금 휴지통으로 보낸 노트를 되살려 제자리에 다시 띄운다(틀, 핀, 접힘 그대로). 되살린 노트를 돌려준다.
    /// 되돌릴 것이 없으면 `nil`. 되살리지 못하면 던진다. 다시 해도 되지 않을 실패(휴지통에 그 노트가 없다,
    /// 같은 노트가 이미 있다)면 되돌릴 것을 비워 다음 ⌘Z가 글의 실행 취소로 가게 하고, 잠깐의 실패
    /// (파일을 옮기지 못함 등)면 다시 시도할 수 있게 남겨 둔다.
    @discardableResult
    public func undoTrash() throws -> NoteID? {
        guard let trashed = lastTrashed else { return nil }
        do {
            try notes.restoreFromTrash(trashed.id)
        } catch let error as StoreError {
            switch error {
            case .noteNotFound, .noteAlreadyExists: lastTrashed = nil
            default: break
            }
            throw error
        }
        lastTrashed = nil
        if let state = trashed.windowState { recorder.restore(state, for: trashed.id) }
        try open(trashed.id, focus: true)
        return trashed.id
    }

    /// 떠 있는 모든 노트 창에서 고치던 제목을 마무리하고 편집기가 아직 알리지 않은 본문을 받는다.
    /// App이 끝내기 전에 `flushPendingSaves()`보다 먼저 부른다.
    public func flushPendingEdits() {
        order.compactMap { controllers[$0] }.forEach { $0.flushPendingEdits() }
    }

    /// 떠 있는 노트를 한꺼번에 감추거나 제자리에 되돌린다.
    public func toggleAllHidden() {
        setAllHidden(!areNotesHidden)
    }

    /// 되돌릴 때는 뒤에 있던 창부터 띄워 숨기기 전의 앞뒤를 지킨다.
    private func setAllHidden(_ hidden: Bool) {
        guard hidden != areNotesHidden else { return }
        areNotesHidden = hidden
        recorder.backToFront(order).compactMap { controllers[$0] }.forEach { $0.setHidden(hidden) }
    }

    // MARK: - 창마다

    /// 떠 있는 노트(띄운 순서).
    public var openNoteIDs: [NoteID] { order }

    /// 지금 글을 쓰고 있는 노트(키 창). 없으면 `nil`.
    public var keyNoteID: NoteID? {
        order.last { id in controllers[id].map { isKeyPanel($0.panel) } == true }
    }

    /// 사용자가 앱을 앞으로 가져왔을 때(Dock, ⌘Tab) 부른다. 키 창인 노트가 없으면 보이는 노트 가운데 가장
    /// 앞의 것을 키 창으로 만들어 키보드만으로 이어 쓸 수 있게 한다(D-025). 키 창인(이 된) 노트를 돌려준다.
    /// 노트를 숨긴 중이거나 보이는 노트가 없으면 아무것도 하지 않는다.
    @discardableResult
    public func focusFrontmostNote() -> NoteID? {
        guard !areNotesHidden else { return nil }
        if let key = keyNoteID { return key }
        guard let front = frontmostNoteID else { return nil }
        controllers[front]?.takeKey()
        return front
    }

    /// 키 창을 잠깐 가져갔던 다른 화면(빠른 캡처, 노트 찾기)이 닫힐 때 App이 부른다: 그 전에 키 창이던
    /// 노트가 다시 키 창이 된다. 제목을 고치던 중이 아니면 본문이 입력을 받고, 커서 자리는 그대로다.
    /// 사용자가 다른 노트로 옮겨 간 것이 아니므로 휴지통 되돌리기(`canUndoTrash`)는 끝나지 않는다.
    /// - Returns: 돌려주었으면 참. 그 노트가 떠 있지 않거나 숨겨져 있으면 아무것도 하지 않고 거짓.
    @discardableResult
    public func returnKey(to id: NoteID) -> Bool {
        guard !areNotesHidden, let controller = controllers[id], controller.panel.isVisible else { return false }
        let trashed = lastTrashed
        isHoldingTrashUndo = true
        controller.takeKey()
        lastTrashed = trashed
        isHoldingTrashUndo = false
        return true
    }

    /// 맨 앞에 있는 노트: 키 창인 노트, 없으면 보이는 노트 가운데 가장 앞에 겹친 것.
    public var frontmostNoteID: NoteID? {
        keyNoteID ?? recorder.backToFront(order).last { controllers[$0]?.panel.isVisible == true }
    }

    /// 그 노트의 창. 다른 화면을 그 노트에 붙여 띄울 때 쓴다(노트 찾기). 떠 있지 않으면 `nil`.
    public func window(for id: NoteID) -> NSWindow? {
        controllers[id]?.panel
    }

    /// 지금 노트의 다음 노트(띄운 순서, 끝에서 처음으로 돌아감)로 커서를 옮긴다. 옮겨 간 노트를 돌려준다.
    @discardableResult
    public func focusNextNote() -> NoteID? {
        guard !order.isEmpty else { return nil }
        let current = frontmostNoteID.flatMap(order.firstIndex(of:))
        let next = order[current.map { ($0 + 1) % order.count } ?? 0]
        setAllHidden(false)
        controllers[next]?.show(focus: true)
        return next
    }

    /// 제목을 그 자리에서 고치기 시작한다. 노트를 숨긴 중이면 숨김을 모두 푼다.
    public func beginTitleEditing(for id: NoteID) {
        guard let controller = controllers[id] else { return }
        setAllHidden(false)
        controller.beginTitleEditing()
    }

    public func snapshot(of id: NoteID) -> NoteWindowSnapshot? {
        controllers[id]?.snapshot
    }

    public func setPinned(_ pinned: Bool, for id: NoteID) {
        controllers[id]?.setPinned(pinned)
    }

    /// 노트 색을 바꾼다. `nil`이면 색 없음.
    public func setColor(_ colorID: PaletteID?, for id: NoteID) {
        controllers[id]?.setColor(colorID?.rawValue)
    }

    /// 노트 창을 키 창으로 만들고 본문에 커서를 둔다. 노트를 숨긴 중이면 숨김을 모두 푼다.
    public func focusBody(of id: NoteID) {
        guard let controller = controllers[id] else { return }
        setAllHidden(false)
        controller.focusBody()
    }

    /// 더 보기 메뉴를 띄운다(키보드로 열 때). 노트를 숨긴 중이면 숨김을 모두 푼다.
    public func popUpMoreMenu(for id: NoteID) {
        guard let controller = controllers[id] else { return }
        setAllHidden(false)
        controller.popUpMoreMenu()
    }

    /// 확인용: 마우스 위치와 상관없이 호버 상태를 정한다. `nil`이면 마우스를 따른다.
    public func setHoverOverride(_ hovered: Bool?, for id: NoteID) {
        controllers[id]?.hoverOverride = hovered
    }

    // MARK: - 안쪽

    /// 사용자가 노트 창의 버튼을 누르기 시작했다. 보통 창을 누른 것처럼 앱이 앞으로 온다(D-025).
    /// 키 창을 끈 확인용 실행과 시험(`allowsKeyWindows`)에서는 앱을 앞으로 가져오지 않는다.
    func noteButtonPressed() {
        guard allowsKeyWindows else { return }
        if !isAppActive() { activateApp() }
    }

    /// 휴지통 되돌리기의 "바로 뒤"가 끝났다: 사용자가 글을 고쳤거나, 새 노트를 만들었거나, 노트 창을 눌렀거나,
    /// 다른 노트가 키 창이 되었다(`canUndoTrash`).
    func endTrashUndo() {
        lastTrashed = nil
    }

    /// 노트가 없어졌고 창에 남길 글도 없다(휴지통으로 갔거나, 쓰지 못한 글 없이 파일이 지워짐).
    /// 창을 내리고 창 상태도 지운다.
    func noteDisappeared(_ id: NoteID) {
        discard(id)
        recorder.forget(id)
    }

    /// 파일이 없어진 노트의 글을 새 노트로 옮긴다. 지금 제목, 본문, 스페이스, 색, 리마인더로 새 노트를 만들어
    /// 같은 자리에 같은 핀 상태로 띄우고, 옛 창과 저장소에 남은 변경을 정리한다.
    /// 새 노트를 만들지 못하면 옛 창과 표시를 그대로 둔다.
    func replaceMissingNote(_ id: NoteID) {
        guard let old = controllers[id] else { return }
        // 편집기가 아직 알리지 않은 글(조합 중인 글자, 한 차례 늦게 알리는 편집)과 고치던 제목까지 받는다.
        old.flushPendingEdits()
        let source = old.latestNote
        let created: Note
        do {
            created = try notes.create(NoteDraft(
                title: source.title, body: source.body, spaceID: source.spaceID, colorID: source.colorID,
                reminder: source.reminder
            ))
        } catch {
            log("없어진 노트의 글을 새 노트로 저장하지 못했습니다(\(id)): \(error)")
            return
        }
        let frame = old.panel.frame
        let isPinned = old.isPinned
        let wasKey = isKeyPanel(old.panel)
        // 접힘 같은 보기 상태는 같은 글을 이어받는 새 노트로 옮긴다(틀과 핀은 지금 창의 것으로).
        var state = recorder.savedState(for: id) ?? NoteWindowState()
        state.frame = WindowFrame(frame)
        state.isPinned = isPinned
        state.isOpen = true
        notes.discardPendingChanges(id)
        // 새 창이 곧 같은 자리에 뜬다. 그 사이에 다른 노트로 키 창을 넘기지 않는다.
        discard(id, handsOffKey: false)
        recorder.forget(id)
        recorder.restore(state, for: created.id)
        do {
            try open(created.id, focus: wasKey)
        } catch {
            log("새로 저장한 노트를 띄우지 못했습니다(\(created.id)): \(error)")
        }
    }

    /// 파일이 없어진 노트의 쓰지 못한 글을 버리고 창을 내린다.
    func discardMissingNote(_ id: NoteID) {
        notes.discardPendingChanges(id)
        noteDisappeared(id)
    }

    /// 노트 창이 키 창이 되었다. 다른 프로그램이 제자리에서 고친 파일은 폴더 감시가 잡지 못하고,
    /// 노트 창은 눌러도 앱을 앞으로 가져오지 않으므로(앱이 앞으로 올 때의 `refresh`가 돌지 않는다)
    /// 여기서 노트 폴더를 다시 훑는다. 훑는 일은 파일마다 겉모습(수정 시각, 크기)만 보므로 매번 해도 가볍다.
    func noteWindowDidBecomeKey() {
        // 사용자가 다른 노트로 옮겨 갔다. 그 노트의 ⌘Z는 그 글의 실행 취소다.
        endTrashUndo()
        // 훑다가 창이 닫히면 다른 창이 키 창이 되어 다시 들어온다.
        guard !isRefreshingStore else { return }
        isRefreshingStore = true
        defer { isRefreshingStore = false }
        do {
            try notes.refresh()
        } catch {
            log("노트 폴더를 다시 읽지 못했습니다: \(error)")
        }
    }

    /// 창을 내린다. 키 창이던 창이면 키 입력을 이어 준다(`KeyHandoff`).
    private func discard(_ id: NoteID, handsOffKey: Bool = true) {
        guard let controller = controllers.removeValue(forKey: id) else { return }
        let wasKey = isKeyPanel(controller.panel)
        order.removeAll { $0 == id }
        controller.discardWindow()
        guard handsOffKey else { return }
        switch KeyHandoff.afterDiscarding(
            wasKey: wasKey, nextVisible: frontmostNoteID, afterTrash: trashInProgress == id
        ) {
        case .none: break
        case .makeKey(let next): controllers[next]?.takeKey()
        case .activateApp: activateApp()
        }
    }

    private func storeDidChange(_ change: StoreChange) {
        guard let controller = controllers[change.id] else {
            if change.kind == .removed { recorder.forget(change.id) }
            return
        }
        switch (change.kind, change.origin) {
        case (.removed, .local):
            noteDisappeared(change.id)
        case (.removed, .external):
            // 다른 프로그램이 지웠다. 쓰지 못한 글이 있는 창은 닫지 않는다.
            controller.fileWentMissing()
        default:
            controller.storeDidChange(change)
        }
    }

    private func observeAppearance(of theme: Theme) {
        let refresh: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.controllers.values.forEach { $0.themeDidChange() } }
        }
        observers = [
            NotificationCenter.default.addObserver(
                forName: Theme.didChangeNotification, object: theme, queue: nil, using: refresh
            ),
            // 대비 증가, 동작 줄이기(spec 15, 17).
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil,
                queue: .main, using: refresh
            ),
        ]
    }

    private func frame(for state: NoteWindowState, nextTo: NoteID?) -> CGRect {
        let policy = environment.sizePolicy
        let placement = environment.placement
        let screens = NSScreen.screens
        guard let main = (NSScreen.main ?? screens.first)?.visibleFrame else {
            return CGRect(x: 0, y: 0, width: policy.defaultWidth, height: policy.minHeight)
        }
        if let saved = state.frame?.cgRect {
            // 적어 둔 틀이 가장 낮은 높이보다 낮으면(그 값이 커지기 전에 적힌 틀) 위쪽 가장자리를 지킨 채 아래로 늘린다.
            let height = max(saved.height, policy.minHeight)
            let sized = CGRect(
                x: saved.minX, y: saved.maxY - height, width: policy.clampedWidth(saved.width), height: height
            )
            return placement.restoredFrame(
                saved: sized, screens: screens.map(\.frame), main: main,
                handleHeight: environment.theme.shape(.chromeHeight)
            )
        }
        let size = CGSize(width: policy.defaultWidth, height: policy.minHeight)
        let occupied = order.compactMap { controllers[$0]?.panel.frame }
        let anchorID = nextTo.flatMap { controllers[$0] != nil ? $0 : nil } ?? keyNoteID ?? order.last
        guard let anchor = anchorID.flatMap({ controllers[$0]?.panel.frame }) else {
            return placement.initialFrame(size: size, visibleFrame: main, occupied: occupied)
        }
        let visible = screens.first { $0.frame.intersects(anchor) }?.visibleFrame ?? main
        return placement.frame(nextTo: anchor, size: size, visibleFrame: visible, occupied: occupied)
    }
}
