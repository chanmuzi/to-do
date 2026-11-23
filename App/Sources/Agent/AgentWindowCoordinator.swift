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
        var records: [UUID: AgentDraft] = [:]
    }
    private let catalog = Catalog()
    package var drafts: [AgentDraft] { Array(catalog.records.values) }
    package var history: [AgentConversation] { catalog.records.values.map(\.conversation).filter(\.hasSubmitted) }
    package func record(id: UUID) -> AgentDraft? { catalog.records[id] }
    package var present: (AgentDraft, String) -> Void = { _, _ in }
    private var loaded = false
    package var send: (AgentDraft) -> Void = { _ in }
    package var sendAll: (AgentDraft) -> Void = { _ in }
    package var sendNow: (AgentDraft, UUID) -> Void = { _, _ in }
    package var retry: (AgentDraft, UUID) -> Void = { _, _ in }
    package var openNote: (NoteID) -> Void = { _ in }
    package var chooseTarget: (AgentDraft) -> Void = { _ in }
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
        loaded = true
    }

    package func preferred(for note: NoteID) -> AgentDraft? {
        let candidates = catalog.records.values.filter { $0.conversation.targets.contains(note) }.sorted {
            ($0.conversation.updatedAt, $0.conversation.id.uuidString) > ($1.conversation.updatedAt, $1.conversation.id.uuidString)
        }
        return candidates.first { $0.conversation.requests.last?.status == .running }
            ?? candidates.first { $0.conversation.needsAnswer }
    }

    package func record(for note: NoteID?) throws -> AgentDraft {
        try restore()
        let targets = note.map { [$0] } ?? []
        if let existing = catalog.records.values.filter({ $0.conversation.targets.first == targets.first })
            .max(by: { $0.conversation.updatedAt < $1.conversation.updatedAt }) { return existing }
        return newRecord(targets: targets)
    }

    package func newRecord(targets: [NoteID] = []) -> AgentDraft {
        let record = AgentDraft(AgentConversation(targets: targets), store: store)
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

    package func open(record draft: AgentDraft, title: String, frame: CGRect, visible: CGRect) {
        draft.showsHistory = false
        draft.markSeen()
        let id = draft.conversation.id
        let panel: AgentPanel
        if let existing = sessions[id] {
            panel = existing.panel
        } else {
            panel = AgentPanel(contentRect: frame, styleMask: [.borderless, .resizable, .closable, .nonactivatingPanel],
                               backing: .buffered, defer: false)
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
            let view = AgentWindowView(theme: theme, title: title, draft: draft,
                                       history: { [weak self] in self?.history ?? [] },
                                       openHistory: { [weak self, weak panel] id in
                                           guard let self, let next = record(id: id) else { return }
                                           present(next, "clock")
                                           if id != draft.conversation.id { panel?.close() }
                                       },
                                       newChat: { [weak self, weak panel] in
                                           guard let self else { return }
                                           present(newRecord(targets: draft.conversation.targets), "new")
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
                                       openNote: openNote, chooseTarget: { [weak self] in self?.chooseTarget(draft) },
                                       titleForNote: titleForNote, fit: { [weak panel, theme] height in
                guard let panel else { return }
                let maxHeight = visible.height * theme.ratio(.noteMaxScreenHeight)
                let target = min(maxHeight, max(frame.height, height.rounded(.up)))
                guard target > panel.frame.height else { return }
                var rect = panel.frame
                rect.origin.y = max(visible.minY, rect.maxY - target)
                rect.size.height = target
                panel.setFrame(rect, display: true)
            }) { [weak panel] in panel?.close() }
            let host = NSHostingView(rootView: view)
            host.sizingOptions = []
            // NSHostingView가 창의 크기 제한을 갱신하지 않도록 AppKit 컨테이너가 크기를 소유한다.
            let container = NSView(frame: CGRect(origin: .zero, size: frame.size))
            host.frame = container.bounds
            host.autoresizingMask = [.width, .height]
            container.addSubview(host)
            panel.contentView = container
            panel.minSize = CGSize(width: theme.component(.noteWidthMin), height: frame.height)
            panel.maxSize = CGSize(width: theme.component(.noteWidthMax), height: max(frame.height, visible.height))
            panel.setFrame(frame, display: false)
            sessions[id] = Session(panel: panel, draft: draft)
        }
        if allowsKeyWindows { panel.makeKeyAndOrderFront(nil) } else { panel.orderFront(nil) }
    }

    public func windowWillClose(_ notification: Notification) {
        guard let panel = notification.object as? AgentPanel,
              let id = sessions.first(where: { $0.value.panel === panel })?.key else { return }
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
    package func performForVerification(_ action: String, for note: NoteID) {
        guard let draft = sessions.values.first(where: { $0.draft.conversation.targets.first == note })?.draft else { return }
        switch action {
        case "history": draft.showsHistory.toggle()
        case "send": send(draft)
        case "retry": if let id = draft.conversation.requests.last?.id { retry(draft, id) }
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
    public func window(for note: NoteID) -> NSWindow? { sessions.values.first { $0.draft.conversation.targets.first == note }?.panel }
    public func setDraft(_ text: String, for note: NoteID) { sessions.values.first { $0.draft.conversation.targets.first == note }?.draft.update(text) }
    public func draft(for note: NoteID) -> String? { sessions.values.first { $0.draft.conversation.targets.first == note }?.draft.conversation.draft }
    #endif
}
