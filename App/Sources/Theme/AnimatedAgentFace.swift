import AppKit
import SwiftUI

/// 얼굴 프레임은 고정 크기 NSView의 그리기만 무효화한다.
struct AnimatedAgentFace: NSViewRepresentable {
    let face: AgentFace

    func makeNSView(context: Context) -> AgentFaceView { AgentFaceView(frame: .zero) }

    func updateNSView(_ view: AgentFaceView, context: Context) {
        view.configure(face, blinkPeriod: face.theme.tokens.period(.blink))
    }
}

final class AgentFaceView: NSView {
    private var face: AgentFace?
    private var blinkPeriod: TimeInterval = 0
    private var timer: Timer?
    private static let frameInterval: TimeInterval = 1.0 / 30

    func configure(_ next: AgentFace, blinkPeriod: TimeInterval) {
        let changed = next.state != face?.state || self.blinkPeriod != blinkPeriod
        face = next
        self.blinkPeriod = blinkPeriod
        if changed { updateClock() }
        needsDisplay = true
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if let window {
            NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: window)
        }
        timer?.invalidate()
        timer = nil
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            NotificationCenter.default.addObserver(self, selector: #selector(updateClock),
                name: NSWindow.didChangeOcclusionStateNotification, object: window)
        }
        updateClock()
    }

    override func viewDidHide() { super.viewDidHide(); updateClock() }
    override func viewDidUnhide() { super.viewDidUnhide(); updateClock() }

    @objc private func updateClock() {
        timer?.invalidate()
        timer = nil
        needsDisplay = true
        guard let face, let window, window.occlusionState.contains(.visible),
              !isHiddenOrHasHiddenAncestor else { return }
        let idle = face.state == .idle
        if idle && blinkPeriod <= 0 { return }
        let delay = idle ? nextBlinkDelay : Self.frameInterval
        let clock = Timer(timeInterval: delay, repeats: !idle) { [weak self] _ in
            MainActor.assumeIsolated {
                if idle { self?.updateClock() }
                else { self?.needsDisplay = true }
            }
        }
        clock.fireDate = Date(timeIntervalSinceNow: delay)
        timer = clock
        RunLoop.main.add(clock, forMode: .common)
    }

    // 한 주기의 마지막 5%에 눈을 감고, 다음 주기에 다시 뜬다.
    private var blinkPhase: TimeInterval {
        Date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: blinkPeriod)
    }
    private var nextBlinkDelay: TimeInterval {
        let phase = blinkPhase, closedAt = blinkPeriod * 0.95
        return (phase < closedAt ? closedAt : blinkPeriod) - phase
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let face, !bounds.isEmpty, let context = NSGraphicsContext.current?.cgContext else { return }
        let time: TimeInterval?
        if timer == nil { time = nil }
        else if face.state == .idle { time = blinkPhase >= blinkPeriod * 0.95 ? blinkPeriod * 0.95 : nil }
        else { time = Date.timeIntervalSinceReferenceDate }
        let scheme: ColorScheme = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
        let renderer = ImageRenderer(content: face.glyph(at: time)
            .frame(width: bounds.width, height: bounds.height).environment(\.colorScheme, scheme))
        renderer.render(rasterizationScale: window?.backingScaleFactor ?? 1) { _, draw in draw(context) }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
