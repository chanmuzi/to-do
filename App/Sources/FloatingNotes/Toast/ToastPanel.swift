import AppKit

/// 짧은 알림의 창(D-041). 앱을 앞으로 가져오지 않고 키 창도 되지 않는다: 떠도 사용자가 쓰던 곳(다른 앱, 노트)이
/// 계속 입력을 받는다. 동작 단추는 키 창이 아니어도 첫 누름에 동작한다(`ToastActionButton`).
final class ToastPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        hidesOnDeactivate = false
        isFloatingPanel = true
        // 노트 창(`floating`)보다 위, 캡처 바와 노트 찾기와 같은 단계.
        level = .modalPanel
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        isRestorable = false
        // 나타나고 사라지는 것은 알파로 직접 움직인다(규칙 8).
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
