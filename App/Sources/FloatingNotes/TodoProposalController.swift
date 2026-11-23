import Agent
import AppKit
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
        guard let draft = record(id), let p = draft.proposal(id), let target = p.targetID else { return }
        selected[target] = id
        router.traceActivation("proposal-open " + source)
        guard router.route(.openNote(target)) == .handled else { return }
        do { try draft.markProposalSeen(id) } catch { showError("제안 열람을 저장하지 못했어요") }
        refreshCards()
    }

    func review(_ id: UUID) {
        guard let draft = record(id), let target = draft.proposal(id)?.targetID else { return }
        do {
            try flush(target)
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
            guard let draft = record(id), let p = draft.proposal(id), let target = p.targetID, p.status == .pending else { continue }
            do {
                try flush(target)
                if let own = chain[target], own.base == p.baseVersion, p.requiresReview != true,
                   try TodoSubmission.fingerprint(Data(notes.proposalText(target).utf8)) == own.applied {
                    try draft.reviewProposal(id, notes: notes)
                }
                if try draft.acceptProposal(id, notes: notes), let receipt = draft.proposal(id)?.receipt {
                    accepted.append(id)
                    chain[target] = (chain[target]?.base ?? receipt.previousFingerprint, receipt.appliedFingerprint)
                }
            } catch { failed = true }
        }
        guard !accepted.isEmpty else { if failed { showError("노트가 바뀌었어요. 미리보기를 다시 확인해 주세요.") }; return }
        showToast(failed ? "일부 제안을 받았어요. 남은 제안을 확인해 주세요." : "할 일을 추가했어요", "되돌리기") { [weak self, accepted] in
            self?.undo(accepted)
        }
    }

    private func undo(_ ids: [UUID]) {
        var failed = false
        for id in ids.reversed() {
            guard let draft = record(id), let target = draft.proposal(id)?.targetID else { continue }
            do {
                try flush(target)
                try draft.undoProposal(id, notes: notes)
            } catch { failed = true }
        }
        if failed { showError("노트가 바뀌어 되돌릴 수 없는 제안이 있어요") }
    }

    private func flush(_ id: NoteID) throws {
        panels.flushPendingEdits(for: id)
        try notes.flushProposalTarget(id)
    }

    private func refreshCards() {
        let pending = agent.history.sorted { $0.updatedAt > $1.updatedAt }.flatMap(\.requests).flatMap(\.proposals)
            .filter { $0.status == .pending }
        var visible: Set<NoteID> = []
        for id in panels.openNoteIDs {
            let candidates = pending.filter { $0.targetID == id }
            guard let parent = panels.window(for: id), let p = candidates.first(where: { $0.id == selected[id] }) ?? candidates.first else { continue }
            visible.insert(id)
            let panel = cards[id] ?? CardPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false
            panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = true
            let view = TodoProposalView(theme: theme, proposal: p, note: try? notes.proposalNote(id), full: expanded.contains(p.id),
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
