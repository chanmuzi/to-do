import AppKit

/// 플로팅 노트 창(spec 4.1, 19). 앱을 앞으로 가져오지 않고 키 창이 되며, 모든 Spaces와 전체 화면 앱 위에 보인다.
final class NotePanelWindow: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        hidesOnDeactivate = false
        isFloatingPanel = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // 창은 상단 줄로만 끈다. 본문을 끌면 글자 선택이다.
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        isRestorable = false
        animationBehavior = .none
    }

    /// 제목 막대가 없는 창은 기본으로 키 창이 되지 못한다. 글을 쓰려면 되어야 한다.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// 핀이 켜지면 다른 앱 위에 뜬다. 끄면 보통 창처럼 뒤로 갈 수 있다.
    func setPinned(_ pinned: Bool) {
        isFloatingPanel = pinned
        level = pinned ? .floating : .normal
    }
}
