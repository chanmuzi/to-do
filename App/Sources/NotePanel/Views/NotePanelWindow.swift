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

    /// 확인용 실행에서 끈다. 꺼져 있으면 키 창이 되지 않아 사용자가 다른 앱에 치던 글자를 가져오지 않는다.
    var allowsKey = true

    private var isKeyRequested = false

    /// 제목 막대가 없는 창은 기본으로 키 창이 되지 못한다. 글을 쓰려면 되어야 한다.
    ///
    /// 노트 창은 앱이 앞에 있지 않아도 키 창이 되어 키 입력을 받는다. 그래서 사용자가 이 창을 눌렀거나
    /// (`mouseDown`) 앱이 일부러 시켰을 때(`becomeKeyByRequest()`)만 키 창이 된다. 앱을 켜며 되살린 창이나
    /// 앞으로 가져오기만 한 창이 저절로 키 창이 되어 다른 앱에 치던 글자를 가져오지 않는다.
    override var canBecomeKey: Bool {
        canBecomeKey(during: NSApplication.shared.currentEvent)
    }

    /// - Parameter event: 지금 처리 중인 이벤트. 이 창을 누른 것이면 키 창이 될 수 있다.
    func canBecomeKey(during event: NSEvent?) -> Bool {
        guard allowsKey else { return false }
        if isKeyRequested || isKeyWindow { return true }
        guard let event, [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type) else { return false }
        return event.windowNumber == windowNumber
    }

    /// 앱이 시켜서 키 창이 된다(본문에 커서 두기, 제목 고치기, 다음 노트로).
    func becomeKeyByRequest() {
        isKeyRequested = true
        defer { isKeyRequested = false }
        makeKeyAndOrderFront(nil)
    }
    override var canBecomeMain: Bool { false }

    /// 핀이 켜지면 다른 앱 위에 뜬다. 끄면 보통 창처럼 뒤로 갈 수 있다.
    func setPinned(_ pinned: Bool) {
        isFloatingPanel = pinned
        level = pinned ? .floating : .normal
    }
}
