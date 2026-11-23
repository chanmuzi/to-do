import Agent
import AppKit
import Library
import Models
import NotePanel
import Store
import SwiftUI
import Theme

/// 같은 대화 기록을 읽는 창에 ID로 동작을 전달한다. 창마다 별도 제안 상태를 두지 않는다.
final class TodoProposalController {
    let agent: AgentWindowCoordinator
    let notes: FileNoteStore
    let panels: NotePanelCoordinator
    let theme: Theme
    let router: AppRouter
    var showToast: (String, String, @escaping () -> Void) -> Void = { _, _, _ in }
    var showError: (String) -> Void = { _ in }
    private final class CardPanel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }
    private var cards: [NoteID: NSPanel] = [:]
    private var selected: [NoteID: UUID] = [:]
    private var expanded: Set<UUID> = []
    private var noteObserver: StoreObservation?
    private var frameObservers: [NSObjectProtocol] = []

    init(agent: AgentWindowCoordinator, notes: FileNoteStore, panels: NotePanelCoordinator, theme: Theme, router: AppRouter) {
        self.agent = agent; self.notes = notes; self.panels = panels; self.theme = theme; self.router = router
    }

    func connect(_ model: LibraryModel) {
        model.acceptProposals = { [weak self] in self?.accept($0, source: "library") }
        model.discardProposal = { [weak self] in self?.discard($0, source: "library") }
        model.openProposal = { [weak self] in self?.open($0, source: "library") }
        model.reviewProposal = { [weak self] in self?.review($0) }
        model.seenProposal = { [weak self] id in
            do { try self?.record(id)?.markProposalSeen(id) }
            catch { self?.showError("제안 열람을 저장하지 못했어요") }
        }
    }

    func start() {
        panels.windowsChanged = { [weak self] in self?.refreshCards() }
        noteObserver = notes.observe { [weak self] _ in self?.refreshCards() }
        for name in [NSWindow.didResizeNotification, NSWindow.didChangeScreenNotification, NSWindow.didMoveNotification] {
            frameObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] event in
                guard let window = event.object as? NSWindow else { return }
                MainActor.assumeIsolated {
                    guard let self,
                          let id = self.panels.openNoteIDs.first(where: { self.panels.window(for: $0) === window }),
                          let card = self.cards[id] else { return }
                    if name == NSWindow.didResizeNotification { self.refreshCards() }
                    else { self.position(card, below: window) }
                }
            })
        }
        observe()
    }

    private func observe() {
        withObservationTracking {
            _ = agent.drafts.map(\.conversation)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
        refreshCards()
    }

    private func record(_ id: UUID) -> AgentDraft? { agent.drafts.first { $0.proposal(id) != nil && !$0.deleting } }

    func open(_ id: UUID, source: String) {
        guard let draft = record(id), let p = draft.proposal(id) else { return }
        router.traceActivation("proposal-open " + source)
        if let target = p.status == .accepted ? p.createdNoteID ?? p.targetID : p.cardNoteID {
            selected[target] = id
            guard router.route(.openNote(target)) == .handled else { return }
        } else {
            guard router.route(.openLibrary) == .handled, let model = router.library?.model else { return }
            model.select(.proposals)
            model.selectProposal(id)
        }
        do { try draft.markProposalSeen(id) } catch { showError("제안 열람을 저장하지 못했어요") }
        refreshCards()
    }

    func review(_ id: UUID) {
        guard let draft = record(id), let p = draft.proposal(id) else { return }
        do {
            if let target = p.targetID { try flush(target) }
            try draft.reviewProposal(id, notes: notes)
            expanded.insert(id)
            refreshCards()
        } catch { showError("미리보기를 열 수 없어요") }
    }

    func discard(_ id: UUID, source: String) {
        guard let draft = record(id) else { return }
        router.traceActivation("proposal-discard " + source)
        do { try draft.discardProposal(id) } catch { showError("제안을 버리지 못했어요") }
    }

    func accept(_ ids: [UUID], source: String) {
        router.traceActivation("proposal-accept " + source)
        var accepted: [UUID] = []
        var chain: [NoteID: (base: String, applied: String)] = [:]
        var failed = false
        for id in ids {
            guard let draft = record(id), let p = draft.proposal(id), p.status == .pending else { continue }
            do {
                if case .newNote(_, let space?) = p.target, router.library?.model.spaces.space(for: space) == nil {
                    throw SpaceStore.MutationError.missingSpace
                }
                if let target = p.targetID { try flush(target) }
                if let target = p.targetID, let own = chain[target], own.base == p.baseVersion, p.requiresReview != true,
                   try TodoSubmission.fingerprint(Data(notes.proposalText(target).utf8)) == own.applied {
                    try draft.reviewProposal(id, notes: notes)
                }
                if try draft.acceptProposal(id, notes: notes) {
                    accepted.append(id)
                    if let target = p.targetID, let receipt = draft.proposal(id)?.receipt {
                        let applied = try TodoSubmission.fingerprint(Data(notes.proposalText(target).utf8))
                        chain[target] = (chain[target]?.base ?? receipt.previousFingerprint, applied)
                        if let item = p.scheduleItem { router.onScheduleCreated?(target, item.id) }
                    }
                    if let newID = p.createdNoteID, ids.count == 1 { router.route(.openNote(newID)) }
                }
            } catch { failed = true }
        }
        guard !accepted.isEmpty else { if failed { showError("노트가 바뀌었어요. 미리보기를 다시 확인해 주세요.") }; return }
        showToast(failed ? "일부 제안을 받았어요. 남은 제안을 확인해 주세요." : (accepted.count == 1 ? successMessage(accepted[0]) : "제안을 받았어요"), "되돌리기") { [weak self, accepted] in
            self?.undo(accepted)
        }
    }

    private func successMessage(_ id: UUID) -> String {
        switch record(id)?.proposal(id)?.content {
        case .todos: "할 일을 추가했어요"
        case .newNote: "새 노트를 만들었어요"
        case .schedule(let kind, _, _, _, _, _): kind == .event ? "일정을 추가했어요" : "리마인더를 추가했어요"
        default: "제안을 받았어요"
        }
    }

    private func undo(_ ids: [UUID]) {
        var failed = false
        var editedNewNote = false
        let scheduleTargets = Set(ids.compactMap { id -> NoteID? in
            guard let p = record(id)?.proposal(id), p.scheduleItem != nil else { return nil }
            return p.targetID
        })
        for id in ids.reversed() {
            guard let draft = record(id), let p = draft.proposal(id), let target = p.createdNoteID ?? p.targetID else { continue }
            do {
                try flush(target)
                try draft.undoProposal(id, notes: notes, sharedScheduleTarget: scheduleTargets.contains(target))
            } catch {
                failed = true
                if case StoreError.conflict = error, p.createdNoteID != nil { editedNewNote = true }
            }
        }
        if editedNewNote { showError("새 노트를 고쳐서 되돌릴 수 없어요") }
        else if failed { showError("노트가 바뀌어 되돌릴 수 없는 제안이 있어요") }
    }

    private func flush(_ id: NoteID) throws {
        panels.flushPendingEdits(for: id)
        try notes.flushProposalTarget(id)
    }

    private func spaceName(for p: AgentProposal) -> String? {
        guard case .newNote(_, let space?) = p.target else { return nil }
        return router.library?.model.spaces.space(for: space)?.name
    }

    private func refreshCards() {
        let pending = agent.history.sorted { $0.updatedAt > $1.updatedAt }.flatMap(\.requests).flatMap(\.proposals)
            .filter { $0.status == .pending }
        var visible: Set<NoteID> = []
        for id in panels.openNoteIDs {
            let candidates = pending.filter { $0.cardNoteID == id }
            guard let parent = panels.window(for: id), let p = candidates.first(where: { $0.id == selected[id] }) ?? candidates.first else { continue }
            visible.insert(id)
            let panel = cards[id] ?? CardPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false
            panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = true
            let view = TodoProposalView(theme: theme, proposal: p, note: try? notes.proposalNote(id), full: expanded.contains(p.id),
                                        spaceName: spaceName(for: p),
                                        review: { [weak self] in self?.review(p.id) },
                                        accept: { [weak self] in self?.accept([p.id], source: "card") },
                                        discard: { [weak self] in self?.discard(p.id, source: "card") })
            let width = min(parent.frame.width, theme.component(.noteWidth))
            let host = NSHostingView(rootView: view.frame(width: width).fixedSize(horizontal: false, vertical: true))
            let height = min(host.fittingSize.height, (parent.screen?.visibleFrame.height ?? parent.frame.height) * theme.ratio(.noteMaxScreenHeight))
            let scroll = NSScrollView()
            scroll.drawsBackground = false
            host.frame.size = host.fittingSize
            scroll.documentView = host
            scroll.hasVerticalScroller = host.frame.height > height
            panel.contentView = scroll
            panel.setContentSize(NSSize(width: width, height: height))
            position(panel, below: parent)
            if panel.parent !== parent { parent.addChildWindow(panel, ordered: .above) }
            cards[id] = panel
        }
        for id in Set(cards.keys).subtracting(visible) {
            if let panel = cards.removeValue(forKey: id) { panel.parent?.removeChildWindow(panel); panel.orderOut(nil) }
        }
    }

    private func position(_ card: NSPanel, below parent: NSWindow) {
        let screen = parent.screen?.visibleFrame ?? parent.frame
        let width = card.frame.width, height = card.frame.height
        let x = min(max(screen.minX, parent.frame.minX), screen.maxX - width)
        let below = parent.frame.minY - height
        let y = below >= screen.minY ? below : min(parent.frame.maxY, screen.maxY - height)
        card.setFrameOrigin(NSPoint(x: x, y: y))
    }

    #if DEBUG
    func card(for id: NoteID) -> NSWindow? { cards[id] }
    #endif
    isolated deinit { frameObservers.forEach(NotificationCenter.default.removeObserver) }
}
