import AppKit

/// 캡처 바의 창(spec 4.1): 테두리 없는 패널. 앱을 앞으로 가져오지 않고 키 창이 되며, 노트 창보다 위에 뜬다.
final class CapturePanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        hidesOnDeactivate = false
        isFloatingPanel = true
        level = .modalPanel
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        isRestorable = false
        // 나타나고 사라지는 것은 알파로 직접 움직인다(규칙 8).
        animationBehavior = .none
    }

    /// 테두리 없는 창은 기본으로 키 창이 되지 못한다. 글을 쓰려면 되어야 한다.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
