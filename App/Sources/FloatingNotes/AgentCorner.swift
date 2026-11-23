import Agent
import AppKit
import Models
import NotePanel
import SwiftUI
import Theme

/// 재생성과 상태 갱신은 창의 순서와 타이핑 초점을 바꾸지 않는다.
final class AgentCorner: NSObject {
    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private let theme: Theme
    private let agent: AgentWindowCoordinator
    private weak var notes: NotePanelCoordinator?
    private weak var router: AppRouter?
    private var lastScreenNumber: NSNumber?
    private(set) var window: NSPanel?
    private var preferredID: UUID?
    private var state = AgentFaceState.idle
    private var enabled = false

    init(theme: Theme, agent: AgentWindowCoordinator, router: AppRouter, notes: NotePanelCoordinator) {
        self.theme = theme
        self.agent = agent
        self.router = router
        self.notes = notes
        super.init()
        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didChangeScreenNotification] {
            center.addObserver(self, selector: #selector(screenChanged), name: name, object: nil)
        }
        center.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        follow()
    }

    @objc private func screenChanged(_ event: Notification) {
        if let panel = event.object as? NSWindow {
            guard panel.isKeyWindow, let screen = panel.screen else { return }
            lastScreenNumber = screen.deviceDescription[.init("NSScreenNumber")] as? NSNumber
        }
        place()
    }

    private func follow() {
        let values = withObservationTracking {
            agent.history.sorted { ($0.updatedAt, $0.id.uuidString) > ($1.updatedAt, $1.id.uuidString) }
        } onChange: { [weak self] in Task { @MainActor in self?.follow() } }
        let working = values.filter { $0.requests.last?.status == .running }
        let waiting = values.filter(\.needsAnswer)
        let active = working + waiting
        let preferred = active.first ?? values.first
        preferredID = preferred?.id
        var faces: [NoteID: AgentFaceState] = [:]
        for conversation in active {
            for note in conversation.targets where faces[note] == nil { faces[note] = face(conversation) }
        }
        if notes?.agentFaces != faces { notes?.agentFaces = faces }
        let next = preferred.map(face) ?? .idle
        if state != next { state = next; updateContent() }
    }

    private func face(_ value: AgentConversation) -> AgentFaceState {
        if let last = value.requests.last, last.status == .running { return last.face }
        return value.needsAnswer ? .done : .idle
    }

    func setEnabled(_ value: Bool) {
        guard value != enabled else { return }
        enabled = value
        guard value else { window?.orderOut(nil); return }
        if window == nil {
            let panel = Panel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window = panel
            updateContent()
        }
        place()
        window?.orderFrontRegardless()
    }

    private var diameter: CGFloat { theme.component(.agentFaceLarge) * 2 }
    private var inset: CGFloat { theme.component(.agentInputInset) }

    static func circleFrame(visible: CGRect, diameter: CGFloat, inset: CGFloat) -> CGRect {
        CGRect(x: visible.maxX - diameter - inset, y: visible.minY + inset, width: diameter, height: diameter)
    }

    private func place() {
        guard enabled else { return }
        let last = lastScreenNumber.flatMap { number in
            NSScreen.screens.first { $0.deviceDescription[.init("NSScreenNumber")] as? NSNumber == number }
        }
        guard let screen = last ?? NSScreen.screens.first else { return }
        let circle = Self.circleFrame(visible: screen.visibleFrame, diameter: diameter, inset: inset)
        window?.setFrame(circle.insetBy(dx: -inset, dy: -inset), display: true)
    }

    private func updateContent() {
        guard let window else { return }
        let button = CornerButton(theme: theme, state: state, diameter: diameter, inset: inset) { [weak self] in
            self?.open()
        }
        window.contentView = NSHostingView(rootView: button)
    }

    private func open() {
        let draft = preferredID.flatMap(agent.record(id:)) ?? agent.newRecord()
        router?.showAgent(draft, source: "corner")
    }
}

private struct CornerButton: View {
    let theme: Theme
    let state: AgentFaceState
    let diameter: CGFloat
    let inset: CGFloat
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            AgentFace(theme: theme, state: state, size: .large)
                .frame(width: diameter, height: diameter)
                .background(theme.color(.surface), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("에이전트 열기").accessibilityValue(state.rawValue)
        .padding(inset)
        .background {
            let layers = theme.shadow(.pop)
            Canvas { context, size in
                let circle = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
                context.withCGContext { cg in
                    for layer in layers {
                        let shape = circle.insetBy(dx: -layer.spread, dy: -layer.spread)
                        cg.saveGState()
                        if layer.blur > 0 {
                            cg.setShadow(offset: CGSize(width: layer.x, height: layer.y),
                                         blur: layer.blur / 2, color: layer.color.nsColor.cgColor)
                            cg.setFillColor(NSColor.black.cgColor)
                        } else {
                            cg.setFillColor(layer.color.nsColor.cgColor)
                        }
                        cg.fillEllipse(in: shape)
                        cg.restoreGState()
                    }
                }
            }.allowsHitTesting(false)
        }
    }
}
