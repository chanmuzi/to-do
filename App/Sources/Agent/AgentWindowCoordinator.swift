import AppKit
import Models
import Store
import SwiftUI
import Theme

private final class AgentPanel: NSPanel {
    var allowsKey = true
    var canClose: () -> Bool = { true }
    override func close() { if canClose() { super.close() } }
    override var canBecomeKey: Bool { allowsKey }
    override func performClose(_ sender: Any?) { close() }
}

public final class AgentWindowCoordinator: NSObject, NSWindowDelegate {
    private struct Session {
        let panel: AgentPanel
        let draft: AgentDraft
    }
    private var sessions: [UUID: Session] = [:]
    @Observable fileprivate final class Catalog {
        var recentBarID: UUID?
        var records: [UUID: AgentDraft] = [:]
    }
    private let catalog = Catalog()
    package var drafts: [AgentDraft] { Array(catalog.records.values) }
    package var history: [AgentConversation] { catalog.records.values.map(\.conversation).filter(\.hasSubmitted) }
    package func record(id: UUID) -> AgentDraft? { catalog.records[id] }
    package var modelPicker: ((Bool, CommandLineSpace) -> AnyView)?
    package var present: (AgentDraft, String) -> Void = { _, _ in }
    private weak var lastPresentedPanel: AgentPanel?
    private var lastBarFrame: CGRect?
    private var loaded = false
    package var send: (AgentDraft) -> Void = { _ in }
    package var sendAll: (AgentDraft) -> Void = { _ in }
    package var sendNow: (AgentDraft, UUID) -> Void = { _, _ in }
    package var retry: (AgentDraft, UUID) -> Void = { _, _ in }
    package var openProposal: (UUID) -> Void = { _ in }
    package var openNote: (NoteID) -> Void = { _ in }
    package var contextControls = AgentContextControls()

    func chooseContext(_ draft: AgentDraft) {
        if let panel = draft.contextPanel { panel.close(); return }
        draft.contextPanel = AgentContextPanel(draft: draft, controls: contextControls, theme: theme, allowsKey: allowsKeyWindows)
    }
    package var titleForNote: (NoteID) -> String? = { _ in nil }
    package var stopBeforeDelete: (AgentDraft) async throws -> Void = { _ in }

    package var finishDeletion: (AgentDraft) -> Void = { _ in }

    package func delete(_ draft: AgentDraft) async throws {
        let id = draft.conversation.id
        guard catalog.records[id] === draft, !draft.deleting, draft.conversation.hasSubmitted else { return }
        draft.deleting = true
        defer { draft.deleting = false; finishDeletion(draft) }
        try await stopBeforeDelete(draft)
        try draft.deleteFile()
        sessions[id]?.panel.close()
        catalog.records.removeValue(forKey: id)
    }
    package var onClose: () -> Void = {}

    package func restore() throws {
        guard !loaded else { return }
        for var value in try store.loadConversations(warning: warning) {
            if value.requests.contains(where: { $0.status == .running }) {
                for i in value.requests.indices where value.requests[i].status == .running {
                    value.interruptForShutdown(at: i)
                }
                try store.save(value)
            }
            catalog.records[value.id] = AgentDraft(value, store: store)
        }
        do { catalog.recentBarID = try store.recentBarID() }
        catch { warning("직전 막대 대화를 읽지 못했습니다. " + error.localizedDescription) }
        loaded = true
    }

    package var recentBar: AgentDraft? {
        catalog.recentBarID.flatMap { catalog.records[$0] }
    }

    package func rememberBar(_ draft: AgentDraft) {
        catalog.recentBarID = draft.conversation.id
        do { try store.rememberBar(draft.conversation.id) }
        catch { warning("직전 막대 대화를 기록하지 못했습니다. " + error.localizedDescription) }
    }

    package func showsConversation(_ id: UUID) -> Bool {
        guard let session = sessions[id], !session.draft.showsHistory else { return false }
        return session.panel.isVisible && !session.panel.isMiniaturized && session.panel.occlusionState.contains(.visible)
    }

    package func preferred(for note: NoteID) -> AgentDraft? {
        let candidates = catalog.records.values.filter { $0.conversation.origin == note }.sorted {
            ($0.conversation.updatedAt, $0.conversation.id.uuidString) > ($1.conversation.updatedAt, $1.conversation.id.uuidString)
        }
        return candidates.first { $0.conversation.requests.last?.status == .running }
            ?? candidates.first { $0.conversation.needsAnswer }
    }

    package func record(for note: NoteID?) throws -> AgentDraft {
        try restore()
        let context = note.map { [AgentContextItem.note($0)] } ?? []
        if let existing = catalog.records.values.filter({ $0.conversation.origin == note })
            .max(by: { $0.conversation.updatedAt < $1.conversation.updatedAt }) { return existing }
        return newRecord(origin: note, context: context)
    }

    package func newRecord(origin: NoteID? = nil, context: [AgentContextItem] = []) -> AgentDraft {
        let record = AgentDraft(AgentConversation(origin: origin, context: context), store: store)
        catalog.records[record.conversation.id] = record
        return record
    }
    private let store: AgentStore
    private let theme: Theme
    private let warning: (String) -> Void
    public var allowsKeyWindows = true

    public init(store: AgentStore, theme: Theme, warning: @escaping (String) -> Void) {
        self.store = store
        self.theme = theme
        self.warning = warning
    }

    public func open(note: NoteID, title: String, frame: CGRect, visible: CGRect) throws {
        try restore()
        try open(record: preferred(for: note) ?? record(for: note), title: title, frame: frame, visible: visible)
    }

    package func open(record draft: AgentDraft, title: String, frame: CGRect, visible: CGRect, reuseForBar: Bool = false) {
        draft.showsHistory = false
        draft.markSeen()
        let id = draft.conversation.id
        let panel: AgentPanel
        if let existing = sessions[id] {
            panel = existing.panel
        } else {
            var opening = frame
            let candidate = lastPresentedPanel ?? sessions.values.first(where: { $0.panel.isVisible })?.panel
            let reusable = reuseForBar ? candidate : nil
            if let reusable, let old = sessions.first(where: { $0.value.panel === reusable }), old.value.draft.writeError == nil {
                old.value.draft.contextPanel?.close()
                sessions.removeValue(forKey: old.key)
                panel = reusable
                opening = reusable.frame
                if !visible.intersects(opening) { opening.origin = frame.origin }
            } else {
                if reuseForBar, let lastBarFrame, visible.contains(lastBarFrame) {
                    opening.origin = CGPoint(x: lastBarFrame.minX, y: lastBarFrame.maxY - frame.height)
                }
                panel = AgentPanel(contentRect: opening, styleMask: [.borderless, .resizable, .closable, .nonactivatingPanel],
                               backing: .buffered, defer: false)
            }
            panel.allowsKey = allowsKeyWindows
            panel.title = "에이전트"
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.level = .floating
            panel.isMovableByWindowBackground = true
            panel.delegate = self
            panel.canClose = { [weak draft] in
                if draft?.writeError != nil { draft?.save() }
                return draft?.writeError == nil
            }
            let view = AgentWindowView(theme: theme, modelPicker: modelPicker, title: title, draft: draft,
                                       history: { [weak self] in self?.history ?? [] },
                                       openHistory: { [weak self, weak panel] id in
                                           guard let self, let next = record(id: id) else { return }
                                           present(next, "clock")
                                           if id != draft.conversation.id { panel?.close() }
                                       },
                                       newChat: { [weak self, weak panel] in
                                           guard let self else { return }
                                           present(newRecord(origin: draft.conversation.origin, context: draft.conversation.context), "new")
                                           panel?.close()
                                       },
                                       delete: { [weak self] in
                                           Task {
                                               do { try await self?.delete(draft) }
                                               catch { draft.writeError = error }
                                           }
                                       },
                                       send: { [weak self] in self?.send(draft) },
                                       sendAll: { [weak self] in self?.sendAll(draft) },
                                       retry: { [weak self] in self?.retry(draft, $0) },
                                       sendNow: { [weak self] in self?.sendNow(draft, $0) },
                                       openProposal: openProposal, openNote: openNote, contextControls: contextControls,
                                       chooseTarget: { [weak self] in self?.chooseContext(draft) },
                                       titleForNote: titleForNote, fit: { [weak panel, weak self, theme] height in
                guard let panel, self?.sessions[id]?.panel === panel else { return }
                let screen = panel.screen?.visibleFrame ?? visible
                let maxHeight = min(theme.component(.agentWindowHeightLimit), screen.height * theme.ratio(.noteMaxScreenHeight))
                let target = min(maxHeight, max(frame.height, height.rounded(.up)))
                guard target > panel.frame.height else { return }
                var rect = panel.frame
                rect.origin.y = max(screen.minY, rect.maxY - target)
                rect.size.height = target
                panel.setFrame(rect, display: true)
            }) { [weak panel] in panel?.close() }
            let host = NSHostingView(rootView: view)
            host.sizingOptions = []
            // NSHostingView가 창의 크기 제한을 갱신하지 않도록 AppKit 컨테이너가 크기를 소유한다.
            let container = NSView(frame: CGRect(origin: .zero, size: opening.size))
            host.frame = container.bounds
            host.autoresizingMask = [.width, .height]
            container.addSubview(host)
            panel.contentView = container
            panel.minSize = CGSize(width: theme.component(.noteWidthMin), height: frame.height)
            panel.maxSize = CGSize(width: theme.component(.noteWidthMax), height: max(frame.height, visible.height))
            panel.setFrame(opening, display: false)
            sessions[id] = Session(panel: panel, draft: draft)
        }
        lastPresentedPanel = panel
        if panel.isMiniaturized { panel.deminiaturize(nil) }
        if allowsKeyWindows { panel.makeKeyAndOrderFront(nil) } else { panel.orderFront(nil) }
    }

    public func windowWillClose(_ notification: Notification) {
        guard let panel = notification.object as? AgentPanel,
              let id = sessions.first(where: { $0.value.panel === panel })?.key else { return }
        if sessions[id]?.draft.conversation.barRequestID != nil { lastBarFrame = panel.frame }
        if lastPresentedPanel === panel { lastPresentedPanel = nil }
        sessions.removeValue(forKey: id)
        if let record = catalog.records[id], record.conversation.requests.isEmpty,
           record.conversation.draft.isEmpty, record.conversation.queued.isEmpty,
           record.conversation.createdAt == record.conversation.updatedAt {
            catalog.records.removeValue(forKey: id)
        }
        onClose()
    }

    public func flushFailedDrafts() throws {
        for draft in catalog.records.values where draft.writeError != nil {
            draft.save()
            if let error = draft.writeError { throw error }
        }
    }

    #if DEBUG
    package func contextState(for note: NoteID) -> [String: Any]? {
        guard let session = sessions.values.first(where: { $0.draft.conversation.origin == note }) else { return nil }
        let draft = session.draft
        let picker = draft.contextPanel?.model
        return ["origin": draft.conversation.origin?.rawValue ?? "", "count": draft.conversation.context.count,
                "hover": draft.previewContextHover != nil, "picker": picker != nil, "space": picker?.space?.rawValue ?? "",
                "checked": picker?.choices.filter { row in
                    if case .item(let item) = row { return draft.conversation.context.contains(item) }
                    return false
                }.count ?? 0]
    }

    package func performForVerification(_ action: String, for note: NoteID) {
        guard let draft = sessions.values.first(where: { $0.draft.conversation.origin == note })?.draft else { return }
        switch action {
        case "context-hover": draft.previewContextHover = draft.conversation.context.dropFirst().first
        case "context-open": draft.previewContextHover = nil; chooseContext(draft)
        case "context-remove-week": draft.toggleContext(.period(.thisWeek))
        case "context-space":
            if let panel = draft.contextPanel, let id = panel.model.catalog.orderedSpaces.first?.id { panel.model.enter(id) }
        case "context-clear":
            draft.contextPanel?.close()
            draft.change { $0.context.removeAll() }
        case "history": draft.showsHistory.toggle()
        case "send": send(draft)
        case "retry": if let id = draft.conversation.requests.last?.id { retry(draft, id) }
        case "progress-hover-summary": draft.previewProgressHover = "summary"
        case "progress-hover-link": draft.previewProgressHover = "link"
        case "progress-hover-off": draft.previewProgressHover = nil
        case "scroll-top": draft.verificationBottom = false
        case "measure-progress": draft.measuresProgress = true
        case "expand": if let id = draft.conversation.requests.last?.id { draft.expanded.insert(id) }
        case "collapse": draft.expanded.removeAll()
        case "hover": draft.hovered = draft.conversation.queued.last?.id
        case "unhover": draft.hovered = nil
        case "now": if let id = draft.conversation.queued.last?.id { sendNow(draft, id) }
        case "still": draft.still = true
        case "motion": draft.still = false
        default: break
        }
    }
    package func window(id: UUID) -> NSWindow? { sessions[id]?.panel }
    public func window(for note: NoteID) -> NSWindow? { sessions.values.first { $0.draft.conversation.origin == note }?.panel }
    public func setDraft(_ text: String, for note: NoteID) { sessions.values.first { $0.draft.conversation.origin == note }?.draft.update(text) }
    public func draft(for note: NoteID) -> String? { sessions.values.first { $0.draft.conversation.origin == note }?.draft.conversation.draft }
    #endif
}
