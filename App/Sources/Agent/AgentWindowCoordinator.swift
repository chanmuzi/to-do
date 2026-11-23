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
    private var sessions: [NoteID: Session] = [:]
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
        let panel: AgentPanel
        if let existing = sessions[note] {
            panel = existing.panel
        } else {
            let previous = try store.loadConversations(warning: warning).first { $0.targets == [note] && $0.requests.isEmpty }
            let draft = AgentDraft(previous ?? AgentConversation(targets: [note]), store: store)
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
            let view = AgentWindowView(theme: theme, title: title, draft: draft) { [weak panel] in panel?.close() }
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
            sessions[note] = Session(panel: panel, draft: draft)
        }
        if allowsKeyWindows { panel.makeKeyAndOrderFront(nil) } else { panel.orderFront(nil) }
    }

    public func windowWillClose(_ notification: Notification) {
        guard let panel = notification.object as? AgentPanel,
              let id = sessions.first(where: { $0.value.panel === panel })?.key else { return }
        sessions.removeValue(forKey: id)
    }

    public func flushFailedDrafts() throws {
        for session in sessions.values where session.draft.writeError != nil {
            session.draft.save()
            if let error = session.draft.writeError { throw error }
        }
    }

    #if DEBUG
    public func window(for note: NoteID) -> NSWindow? { sessions[note]?.panel }
    public func setDraft(_ text: String, for note: NoteID) { sessions[note]?.draft.update(text) }
    public func draft(for note: NoteID) -> String? { sessions[note]?.draft.conversation.draft }
    #endif
}
